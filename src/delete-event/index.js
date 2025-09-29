const mysql = require("mysql2/promise");
const AWS = require("aws-sdk");
const secretsManager = new AWS.SecretsManager();

exports.handler = async (event) => {
  let connection; // 👈 no volver a redeclarar
  try {
    console.log("🚀 Starting Lambda execution");
    console.log("Environment variables:", {
      DB_HOST: process.env.DB_HOST,
      DB_NAME: process.env.DB_NAME,
      RDS_SECRET_ARN: process.env.RDS_SECRET_ARN ? "✅ Present" : "❌ Missing",
    });

    // 1) Credenciales
    console.log("📡 Fetching credentials from Secrets Manager...");
    const secretArn = process.env.RDS_SECRET_ARN;
    const secretValue = await secretsManager.getSecretValue({ SecretId: secretArn }).promise();
    const creds = JSON.parse(secretValue.SecretString);
    console.log("✅ Credentials fetched successfully");

    // 2) Conexión
    console.log("🔌 Attempting database connection...");
    console.log("Connection config:", {
      user: creds.username,
      database: process.env.DB_NAME,
      password: "***hidden***",
    });

    connection = await mysql.createConnection({
      host: process.env.DB_HOST,
      user: creds.username,
      password: creds.password,
      database: process.env.DB_NAME,
      connectTimeout: 10000,
    });
    console.log("✅ Database connection established");

    // 3) Validar ID desde el path
    const eventId =
      event.pathParameters?.id ||
      (event.rawPath?.match?.(/\/events\/(\d+)(\/)?$/)?.[1]); 

    if (!eventId) {
      return {
        statusCode: 400,
        body: JSON.stringify({ error: "El parámetro 'id' es obligatorio en la URL (/events/{id})" }),
      };
    }

    // 4) Ejecutar DELETE
    console.log("🗑️ Deleting event from database...", { eventId });
    const [result] = await connection.execute(
      "DELETE FROM events WHERE id = ?",
      [eventId]
    );

    if (result.affectedRows === 0) {
      return { statusCode: 404, body: JSON.stringify({ error: "Evento no encontrado o ya eliminado" }) };
    }

    console.log("✅ Event deleted, affectedRows:", result.affectedRows);

    
    return {
      statusCode: 200,
      body: JSON.stringify({ message: "Evento eliminado exitosamente", id: Number(eventId) }),
    };

  } catch (err) {
    console.error("❌ Error eliminando evento:", err);
    console.error("Error details:", {
      message: err.message, code: err.code, errno: err.errno, sqlState: err.sqlState, stack: err.stack
    });
    return {
      statusCode: 500,
      body: JSON.stringify({ error: err.message, code: err.code || "UNKNOWN_ERROR" }),
    };
  } finally {
    if (connection) {
      console.log("🔌 Closing database connection");
      await connection.end();
    }
    console.log("✅ Lambda execution completed");
  }
};