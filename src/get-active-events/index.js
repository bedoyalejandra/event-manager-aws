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

    // 3. Consultar eventos activos
    console.log("📋 Querying active events...");
    const [rows] = await connection.execute(
      "SELECT * FROM events WHERE status = 'ACTIVE' ORDER BY start_date ASC"
    );
    console.log(`✅ Retrieved ${rows.length} active events`);

    // Mostrar los resultados obtenidos
    console.log("📋 Active events data:", JSON.stringify(rows, null, 2));

    return {
      statusCode: 200,
      body: JSON.stringify({
        message: `Se encontraron ${rows.length} eventos activos.`,
        function: "get-active-events",
        events: rows
      }),
    };
  } catch (error) {
    console.error("❌ Error al obtener los eventos activos:", error);
    return {
      statusCode: 500,
      body: JSON.stringify({
        message: "Error al obtener los eventos activos",
        error: error.message,
      }),
    };
}   finally {
    if (connection) {
      console.log("🔌 Closing database connection");
      await connection.end();
    }
    console.log("✅ Lambda execution completed");
}
};