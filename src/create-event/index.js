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
    console.log("Event received:", JSON.stringify(event, null, 2));
    
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
    
    const { name, description, start_date, duration, capacity } = bodyData;
    console.log("✅ Parsed event data:", bodyData);

    if (!name || !start_date || !capacity) {
      return {
        statusCode: 400,
        body: JSON.stringify({ error: "Campos obligatorios faltantes" }),
      };
    }

    // 4. Insertar en la tabla
    console.log("💾 Inserting event into database...");
    const query = `
      INSERT INTO events (name, description, start_date, duration, capacity, status)
      VALUES (?, ?, ?, ?, ?, 'ACTIVE');
    `;

    const [result] = await connection.execute(query, [
      name,
      description || "",
      start_date,
      duration || 0,
      capacity,
    ]);
    
    console.log("✅ Event inserted successfully, ID:", result.insertId);

    return {
      statusCode: 201,
      body: JSON.stringify({ 
        message: "Evento creado exitosamente",
        eventId: result.insertId,
        event: { name, description, start_date, duration, capacity }
      }),
    };
  } catch (err) {
    console.error("❌ Error creando evento:", err);
    console.error("Error details:", {
      message: err.message,
      code: err.code,
      errno: err.errno,
      sqlState: err.sqlState,
      stack: err.stack
    });
    return {
      statusCode: 500,
      body: JSON.stringify({ 
        error: err.message,
        code: err.code || "UNKNOWN_ERROR"
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
