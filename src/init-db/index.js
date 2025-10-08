const mysql = require("mysql2/promise");
const AWS = require("aws-sdk");
const https = require("https");
const url = require("url");
const secretsManager = new AWS.SecretsManager();

// Function to send response to CloudFormation
async function sendResponse(event, context, responseStatus, responseData, physicalResourceId) {
  const responseBody = JSON.stringify({
    Status: responseStatus,
    Reason: responseData.Message || "See CloudWatch logs for details",
    PhysicalResourceId: physicalResourceId || context.logStreamName,
    StackId: event.StackId,
    RequestId: event.RequestId,
    LogicalResourceId: event.LogicalResourceId,
    Data: responseData,
  });

  console.log("Response body:", responseBody);

  const parsedUrl = url.parse(event.ResponseURL);
  const options = {
    hostname: parsedUrl.hostname,
    port: 443,
    path: parsedUrl.path,
    method: "PUT",
    headers: {
      "content-type": "",
      "content-length": responseBody.length,
    },
  };

  return new Promise((resolve, reject) => {
    const request = https.request(options, (response) => {
      console.log("Status code:", response.statusCode);
      resolve();
    });

    request.on("error", (error) => {
      console.error("sendResponse Error:", error);
      reject(error);
    });

    request.write(responseBody);
    request.end();
  });
}

async function initializeDatabase() {
  let connection;
  try {
    console.log("Starting database initialization...");

    const secretArn = process.env.RDS_SECRET_ARN;
    const dbHost = process.env.DB_HOST;
    const dbName = process.env.DB_NAME;

    console.log("Environment variables:", {
      secretArn: secretArn ? "Set" : "Missing",
      dbHost: dbHost ? "Set" : "Missing",
      dbName: dbName ? "Set" : "Missing",
    });

    if (!secretArn || !dbHost || !dbName) {
      throw new Error("Missing required environment variables");
    }

    console.log("Getting database credentials from Secrets Manager...");
    const secretValue = await secretsManager
      .getSecretValue({ SecretId: secretArn })
      .promise();
    const creds = JSON.parse(secretValue.SecretString);

    console.log("Connecting to database:", {
      host: dbHost,
      user: creds.username,
    });

    connection = await mysql.createConnection({
      host: dbHost,
      user: creds.username,
      password: creds.password,
      database: dbName,
    });

    console.log("Creating report table...");
    const reportTableDDL = `
      CREATE TABLE IF NOT EXISTS report (
        id VARCHAR(255) PRIMARY KEY,
        tickets_sold VARCHAR(255) NOT NULL UNIQUE,
        event_name VARCHAR(255),        
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP        
      );
    `;

    await connection.execute(reportTableDDL);
    console.log("✅ Users table created/verified successfully");

    console.log("Creating events table...");
    const eventsTableDDL = `
      CREATE TABLE IF NOT EXISTS events (
        id INT AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        description TEXT,
        start_date DATETIME NOT NULL,
        duration INT,
        capacity INT NOT NULL,
        status VARCHAR(20) DEFAULT 'ACTIVE',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
      );
    `;

    await connection.execute(eventsTableDDL);
    console.log("✅ Events table created/verified successfully");

    console.log("Creating event_assistance table...");
    const assistanceTableDDL = `
      CREATE TABLE IF NOT EXISTS event_assistance (
        id INT AUTO_INCREMENT PRIMARY KEY,
        event_id INT NOT NULL,
        user_id VARCHAR(255) NOT NULL,
        user_name VARCHAR(255),
        user_email VARCHAR(255),
        tickets_purchased INT DEFAULT 1,
        attendance_status ENUM('REGISTERED', 'CONFIRMED', 'ATTENDED', 'CANCELLED') DEFAULT 'REGISTERED',
        registration_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        attendance_date TIMESTAMP NULL,
        notes TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE,
        UNIQUE KEY unique_user_event (event_id, user_id),
        INDEX idx_user_id (user_id),
        INDEX idx_user_email (user_email)
      );
    `;

    await connection.execute(assistanceTableDDL);
    console.log("✅ Event assistance table created/verified successfully");

    console.log("Creating database indexes...");
    const indexes = [
      {
        name: "idx_users_email",
        sql: "CREATE INDEX idx_users_email ON users(email)",
      },
      {
        name: "idx_users_cognito",
        sql: "CREATE INDEX idx_users_cognito ON users(cognito_sub)",
      },
      { name: "idx_status", sql: "CREATE INDEX idx_status ON events(status)" },
      {
        name: "idx_start_date",
        sql: "CREATE INDEX idx_start_date ON events(start_date)",
      },
      {
        name: "idx_created_at",
        sql: "CREATE INDEX idx_created_at ON events(created_at)",
      },
      {
        name: "idx_assistance_event",
        sql: "CREATE INDEX idx_assistance_event ON event_assistance(event_id)",
      },
      {
        name: "idx_assistance_user",
        sql: "CREATE INDEX idx_assistance_user ON event_assistance(user_id)",
      },
      {
        name: "idx_assistance_status",
        sql: "CREATE INDEX idx_assistance_status ON event_assistance(attendance_status)",
      },
    ];

    for (const index of indexes) {
      try {
        await connection.execute(index.sql);
        console.log(`✅ Created index: ${index.name}`);
      } catch (indexErr) {
        if (indexErr.code === "ER_DUP_KEYNAME") {
          console.log(`ℹ️ Index ${index.name} already exists, skipping`);
        } else {
          console.error(
            `⚠️ Error creating index ${index.name}:`,
            indexErr.message
          );
        }
      }
    }
    console.log("✅ Database indexes processing completed");

    // Test the connection by doing a simple query
    console.log("Testing database connection...");
    const [rows] = await connection.execute(
      "SELECT COUNT(*) as count FROM events"
    );
    console.log(
      `✅ Database test successful. Current events count: ${rows[0].count}`
    );

    return {
      success: true,
      message: "Database initialized successfully",
      tablesCreated: ["report", "events", "event_assistance"],
      indexesCreated: 8,
      currentEventsCount: rows[0].count,
    };
  } catch (err) {
    console.error("❌ Error initializing database:", err);
    throw err;
  } finally {
    if (connection) {
      try {
        await connection.end();
        console.log("Database connection closed");
      } catch (closeErr) {
        console.error("Error closing database connection:", closeErr);
      }
    }
  }
}

exports.handler = async (event, context) => {
  console.log("Received event:", JSON.stringify(event, null, 2));

  // Check if this is a CloudFormation Custom Resource request
  if (event.RequestType) {
    try {
      // Only initialize on Create and Update, not on Delete
      if (event.RequestType === "Create" || event.RequestType === "Update") {
        const result = await initializeDatabase();
        await sendResponse(event, context, "SUCCESS", {
          Message: result.message,
          TablesCreated: result.tablesCreated.join(", "),
          IndexesCreated: result.indexesCreated,
          EventsCount: result.currentEventsCount,
        });
      } else if (event.RequestType === "Delete") {
        // On delete, just acknowledge - don't drop tables
        await sendResponse(event, context, "SUCCESS", {
          Message: "Database tables retained (not deleted)",
        });
      }
    } catch (err) {
      console.error("Error:", err);
      await sendResponse(event, context, "FAILED", {
        Message: err.message || "Database initialization failed",
      });
    }
  } else {
    // Direct Lambda invocation (not from CloudFormation)
    try {
      const result = await initializeDatabase();
      return {
        statusCode: 200,
        body: JSON.stringify(result),
      };
    } catch (err) {
      console.error("Error:", err);
      return {
        statusCode: 500,
        body: JSON.stringify({
          error: "Database initialization failed",
          message: err.message,
          code: err.code || "UNKNOWN_ERROR",
        }),
      };
    }
  }
};
