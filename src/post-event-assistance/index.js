const mysql = require("mysql2/promise");
const AWS = require("aws-sdk");
const secretsManager = new AWS.SecretsManager();

exports.handler = async (event) => {
  let connection;
  try {
    console.log("🚀 Starting Lambda execution");
    console.log("Environment variables:", {
      DB_HOST: process.env.DB_HOST,
      DB_NAME: process.env.DB_NAME,
      RDS_SECRET_ARN: process.env.RDS_SECRET_ARN ? "✅ Present" : "❌ Missing"
    });

    // 1. Obtener credenciales de Secrets Manager
    console.log("📡 Fetching credentials from Secrets Manager...");
    const secretArn = process.env.RDS_SECRET_ARN;
    const secretValue = await secretsManager
      .getSecretValue({ SecretId: secretArn })
      .promise();
    const creds = JSON.parse(secretValue.SecretString);
    console.log("✅ Credentials fetched successfully");

    // 2. Conexión a la DB
    console.log("🔌 Attempting database connection...");
    console.log("Connection config:", {
      user: creds.username,
      database: process.env.DB_NAME,
      password: "***hidden***"
    });
        
    const connection = await mysql.createConnection({
      host: process.env.DB_HOST,
      user: creds.username,
      password: creds.password,
      database: process.env.DB_NAME,
      connectTimeout: 10000,
    });
    console.log("✅ Database connection established");

    // 3. Parsear body desde API Gateway
    console.log("📋 Parsing request body...");
    console.log("Assistance received:", JSON.stringify(event, null, 2));
    
    if (!event.body) {
      return {
        statusCode: 400,
        body: JSON.stringify({ error: "Request body is required" }),
      };
    }
    
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
    
    // Extract eventId from path parameters
    const eventId = event.pathParameters?.id;
    const { userId, attendanceStatus } = bodyData;
    console.log("✅ Parsed event data:", { eventId, ...bodyData });

    if (!eventId || !userId) {
      return {
        statusCode: 400,
        body: JSON.stringify({ error: "Missing required fields: eventId (from path), userId (from body)" }),
      };
    }

    // 4. Verify user exists
    console.log("🔍 Checking if user exists...");
    const [userRows] = await connection.execute(
      "SELECT id FROM users WHERE id = ?",
      [userId]
    );

    if (userRows.length === 0) {
      return {
        statusCode: 404,
        body: JSON.stringify({ error: "User not found. Please ensure user is registered in the system." }),
      };
    }

    // 5. Verify event exists and has capacity
    console.log("🔍 Checking event availability...");
    const [eventRows] = await connection.execute(
      "SELECT id, capacity, status FROM events WHERE id = ?",
      [eventId]
    );

    if (eventRows.length === 0) {
      return {
        statusCode: 404,
        body: JSON.stringify({ error: "Event not found" }),
      };
    }

    const eventData = eventRows[0];
    if (eventData.status !== 'ACTIVE') {
      return {
        statusCode: 400,
        body: JSON.stringify({ error: "Event is not active" }),
      };
    }

    // 6. Check current registrations
    const [countRows] = await connection.execute(
      "SELECT COUNT(*) as registrations FROM event_assistance WHERE event_id = ? AND attendance_status != 'CANCELLED'",
      [eventId]
    );

    if (countRows[0].registrations >= eventData.capacity) {
      return {
        statusCode: 400,
        body: JSON.stringify({ error: "Event is at full capacity" }),
      };
    }

    // 7. Register assistance
    console.log("📋 Registering event assistance...");
    const insertQuery = `
      INSERT INTO event_assistance (event_id, user_id, attendance_status)
      VALUES (?, ?, ?)
      ON DUPLICATE KEY UPDATE 
        attendance_status = VALUES(attendance_status),
        updated_at = CURRENT_TIMESTAMP
    `;

    const [result] = await connection.execute(insertQuery, [
      eventId,
      userId,
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
        status: attendanceStatus || 'REGISTERED'
      }),
    };
    } catch (err) {
    console.error("❌ Error actualizando asistencia a eventos:", err);
    return {
      statusCode: 500,
      body: JSON.stringify({
      message: "Ocurrió un error interno al intentar actualizar la capacidad del evento. Por favor, inténtalo de nuevo más tarde.",
      error: err.message,
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