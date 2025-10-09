const mysql = require("mysql2/promise");
const AWS = require("aws-sdk");
const secretsManager = new AWS.SecretsManager();

exports.handler = async (event) => {
  let connection;
  try {
    console.log("🚀 Starting Post Event Assistance Lambda");
    console.log("Environment variables:", {
      DB_HOST: process.env.DB_HOST,
      DB_NAME: process.env.DB_NAME,
      RDS_SECRET_ARN: process.env.RDS_SECRET_ARN ? "✅ Present" : "❌ Missing"
    });

    // 1. Parse request body
    console.log("📋 Parsing request body...");
    let bodyData;
    try {
      bodyData = typeof event.body === 'string' ? JSON.parse(event.body) : event.body;
    } catch (parseError) {
      console.error("❌ Error parsing JSON body:", parseError);
      return {
        statusCode: 400,
        body: JSON.stringify({ error: "Invalid JSON format in request body" }),
      };
    }

    // Extract all fields from body
    const { eventId, userId, userName, userEmail, ticketsPurchased, attendanceStatus } = bodyData;
    console.log("✅ Parsed event data:", { eventId, userId, userName, userEmail, ticketsPurchased, attendanceStatus });

    // Validate required fields
    if (!eventId || !userId || !userName || !userEmail || !ticketsPurchased) {
      return {
        statusCode: 400,
        body: JSON.stringify({ 
          error: "Missing required fields: eventId, userId, userName, userEmail, ticketsPurchased" 
        }),
      };
    }

    // 2. Get database credentials from Secrets Manager
    console.log("📡 Fetching credentials from Secrets Manager...");
    const secretArn = process.env.RDS_SECRET_ARN;
    const secretValue = await secretsManager
      .getSecretValue({ SecretId: secretArn })
      .promise();
    const creds = JSON.parse(secretValue.SecretString);
    console.log("✅ Credentials fetched successfully");

    // 3. Connect to database
    console.log("🔌 Attempting database connection...");
    connection = await mysql.createConnection({
      host: process.env.DB_HOST,
      user: creds.username,
      password: creds.password,
      database: process.env.DB_NAME,
      connectTimeout: 10000,
    });
    console.log("✅ Database connection established");

    // 4. Get event details
    console.log("📋 Fetching event details...");
    const [eventRows] = await connection.execute(
      "SELECT id, name, description, start_date, capacity, status FROM events WHERE id = ?",
      [eventId]
    );

    if (eventRows.length === 0) {
      return {
        statusCode: 404,
        body: JSON.stringify({ error: "Event not found" }),
      };
    }

    const eventData = eventRows[0];
    console.log("✅ Event found:", eventData);

    if (eventData.status !== 'ACTIVE') {
      return {
        statusCode: 400,
        body: JSON.stringify({ error: "Event is not active" }),
      };
    }

    // 5. Check if there's enough capacity for the tickets requested
    if (eventData.capacity < ticketsPurchased) {
      return {
        statusCode: 400,
        body: JSON.stringify({ 
          error: "Not enough capacity available",
          availableCapacity: eventData.capacity,
          requestedTickets: ticketsPurchased
        }),
      };
    }

    // 6. Reduce event capacity by tickets purchased
    console.log(`📉 Reducing event capacity by ${ticketsPurchased} tickets...`);
    const updateCapacityQuery = `
      UPDATE events 
      SET capacity = capacity - ? 
      WHERE id = ? AND capacity >= ?
    `;

    const [updateResult] = await connection.execute(updateCapacityQuery, [
      ticketsPurchased,
      eventId,
      ticketsPurchased
    ]);

    if (updateResult.affectedRows === 0) {
      return {
        statusCode: 400,
        body: JSON.stringify({ 
          error: "Could not update capacity. Event may be at full capacity or tickets requested exceed available capacity.",
          availableCapacity: eventData.capacity,
          requestedTickets: ticketsPurchased
        }),
      };
    }

    console.log(`✅ Event capacity reduced. New capacity: ${eventData.capacity - ticketsPurchased}`);

    // 7. Ensure event_assistance table has user_name, user_email and tickets_purchased columns
    console.log("📋 Ensuring event_assistance table structure...");
    const alterTableQuery = `
      ALTER TABLE event_assistance 
      ADD COLUMN IF NOT EXISTS user_name VARCHAR(255),
      ADD COLUMN IF NOT EXISTS user_email VARCHAR(255),
      ADD COLUMN IF NOT EXISTS tickets_purchased INT DEFAULT 1
    `;
    
    try {
      await connection.execute(alterTableQuery);
      console.log("✅ Table structure verified");
    } catch (alterError) {
      // Ignore error if columns already exist (MySQL doesn't support IF NOT EXISTS in ALTER)
      console.log("⚠️ Table structure check:", alterError.message);
    }

    // 8. Register assistance with user details and tickets purchased
    console.log("📋 Registering event assistance...");
    const insertQuery = `
      INSERT INTO event_assistance (event_id, user_id, user_name, user_email, tickets_purchased, attendance_status)
      VALUES (?, ?, ?, ?, ?, ?)
      ON DUPLICATE KEY UPDATE 
        user_name = VALUES(user_name),
        user_email = VALUES(user_email),
        tickets_purchased = tickets_purchased + VALUES(tickets_purchased),
        attendance_status = VALUES(attendance_status),
        updated_at = CURRENT_TIMESTAMP
    `;

    const [result] = await connection.execute(insertQuery, [
      eventId,
      userId,
      userName,
      userEmail,
      ticketsPurchased,
      attendanceStatus || 'REGISTERED'
    ]);

    console.log("✅ Event assistance registered successfully");

    return {
      statusCode: 200,
      body: JSON.stringify({
        message: "Event assistance registered successfully",
        assistanceId: result.insertId || null,
        eventId: eventId,
        userId: userId,
        userName: userName,
        userEmail: userEmail,
        ticketsPurchased: ticketsPurchased,
        status: attendanceStatus || 'REGISTERED'
      }),
    };
  } catch (err) {
    console.error("❌ Error in post-event-assistance:", err);
    console.error("Error details:", {
      message: err.message,
      code: err.code,
      stack: err.stack
    });
    return {
      statusCode: 500,
      body: JSON.stringify({
        error: "Failed to register event assistance",
        message: err.message,
        code: err.code || "UNKNOWN_ERROR",
      }),
    };
  } finally {
    if (connection) {
      console.log("🔌 Closing database connection");
      await connection.end();
    }
    console.log("🏁 Lambda execution finished");
  }
};