const mysql = require("mysql2/promise");
const AWS = require("aws-sdk");
const secretsManager = new AWS.SecretsManager();

/**
 * Lambda function triggered by EventBridge when a new event is created.
 * Automatically creates an associated task for the event.
 */
exports.handler = async (event) => {
  let connection;
  try {
    console.log("🚀 CreateTask Lambda triggered by EventBridge");
    console.log("EventBridge event:", JSON.stringify(event, null, 2));

    // Extract event details from EventBridge event
    const eventDetail = event.detail;
    const { eventId, name, description, start_date, capacity } = eventDetail;

    if (!eventId || !name) {
      console.error("❌ Missing required fields in EventBridge event");
      return {
        statusCode: 400,
        body: JSON.stringify({ error: "Missing required event data" }),
      };
    }

    console.log("📋 Creating task for event:", { eventId, name });

    // 1. Get database credentials from Secrets Manager
    console.log("📡 Fetching credentials from Secrets Manager...");
    const secretArn = process.env.RDS_SECRET_ARN;
    const secretValue = await secretsManager
      .getSecretValue({ SecretId: secretArn })
      .promise();
    const creds = JSON.parse(secretValue.SecretString);
    console.log("✅ Credentials fetched successfully");

    // 2. Connect to database
    console.log("🔌 Attempting database connection...");
    connection = await mysql.createConnection({
      host: process.env.DB_HOST,
      user: creds.username,
      password: creds.password,
      database: process.env.DB_NAME,
      connectTimeout: 10000,
    });
    console.log("✅ Database connection established");

    // 3. Create tasks table if it doesn't exist
    const createTableQuery = `
      CREATE TABLE IF NOT EXISTS tasks (
        id INT AUTO_INCREMENT PRIMARY KEY,
        event_id INT NOT NULL,
        title VARCHAR(255) NOT NULL,
        description TEXT,
        status VARCHAR(50) DEFAULT 'PENDING',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE,
        INDEX idx_event_id (event_id),
        INDEX idx_status (status)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    `;
    await connection.execute(createTableQuery);
    console.log("✅ Tasks table verified/created");

    // 4. Insert task for the event
    const taskTitle = `Preparación para: ${name}`;
    const taskDescription = description 
      ? `Tarea automática para el evento: ${description}` 
      : `Tarea automática para el evento: ${name}`;

    const insertQuery = `
      INSERT INTO tasks (event_id, title, description, status)
      VALUES (?, ?, ?, 'PENDING');
    `;

    const [result] = await connection.execute(insertQuery, [
      eventId,
      taskTitle,
      taskDescription,
    ]);

    console.log("✅ Task created successfully, ID:", result.insertId);

    return {
      statusCode: 201,
      body: JSON.stringify({
        message: "Tarea creada exitosamente",
        taskId: result.insertId,
        eventId: eventId,
        task: {
          title: taskTitle,
          description: taskDescription,
          status: "PENDING",
        },
      }),
    };
  } catch (err) {
    console.error("❌ Error creating task:", err);
    console.error("Error details:", {
      message: err.message,
      code: err.code,
      errno: err.errno,
      sqlState: err.sqlState,
      stack: err.stack,
    });
    return {
      statusCode: 500,
      body: JSON.stringify({
        error: err.message,
        code: err.code || "UNKNOWN_ERROR",
      }),
    };
  } finally {
    if (connection) {
      console.log("🔌 Closing database connection");
      await connection.end();
    }
    console.log("✅ Lambda execution completed");
  }
};
