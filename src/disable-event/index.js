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

      // 3. Actualizar eventos inactivos
      console.log("📋 Disabling inactive events...");
      const query = `
        UPDATE events
        SET status = 'INACTIVE'
        WHERE status = 'ACTIVE' AND (
        start_date < NOW() OR capacity <= 0
      );
    `;

      await connection.query(query);
      console.log("✅ Inactive events disabled successfully");

      return {
        statusCode: 200,
        body: JSON.stringify({
          message: "Eventos inactivos actualizados exitosamente",
          updatedEvents: result.affectedRows,
        }),
      };
    } catch (err) {
    console.error("❌ Error desactivando eventos:", err);
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
    console.log("🏁 Lambda execution finished");
  }
};