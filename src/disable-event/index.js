const mysql = require("mysql2/promise");
const AWS = require("aws-sdk");
const secretsManager = new AWS.SecretsManager();

exports.handler = async (event) => {
  let connection;
  try {
    console.log("🚀 Starting Lambda execution");
    console.log("Event received:", JSON.stringify(event, null, 2));
    console.log("Environment variables:", {
      DB_HOST: process.env.DB_HOST,
      DB_NAME: process.env.DB_NAME,
      RDS_SECRET_ARN: process.env.RDS_SECRET_ARN ? "✅ Present" : "❌ Missing",
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

    // 3. Determine event ID and source
    let eventId;
    let source = "unknown";
    let query;
    let params = [];

    // Check if triggered by EventBridge Scheduler (specific event)
    if (event.source === "eventbridge-scheduler" || event.eventId) {
      eventId = event.eventId;
      source = "eventbridge-scheduler";
      console.log(
        "📅 Triggered by EventBridge Scheduler - Disabling specific event"
      );

      query = `
        UPDATE events
        SET status = 'INACTIVE'
        WHERE id = ? AND status = 'ACTIVE';
      `;
      params = [eventId];
    }
    // Check if triggered by API Gateway (specific event via path parameter)
    else if (event.pathParameters?.id || event.rawPath) {
      eventId =
        event.pathParameters?.id ||
        event.rawPath?.match?.(/\/events\/(\d+)\/disable$/)?.[1];
      source = "api-gateway";
      console.log("🌐 Triggered by API Gateway - Disabling specific event");

      if (!eventId) {
        return {
          statusCode: 400,
          body: JSON.stringify({
            error:
              "El parámetro 'id' es obligatorio en la URL (/events/{id}/disable)",
            source: source,
          }),
        };
      }

      query = `
        UPDATE events
        SET status = 'INACTIVE'
        WHERE id = ? AND status = 'ACTIVE';
      `;
      params = [eventId];
    }
    // Bulk disable (no specific ID - disable all expired events)
    else {
      source = "bulk-operation";
      console.log("📋 Bulk operation - Disabling all expired events");

      query = `
        UPDATE events
        SET status = 'INACTIVE'
        WHERE status = 'ACTIVE' AND start_date < NOW();
      `;
    }

    console.log(`🎯 Disabling event(s) (source: ${source})`);
    const [result] = await connection.execute(query, params);
    console.log(
      "✅ Events disabled successfully, affectedRows:",
      result.affectedRows
    );

    if (eventId && result.affectedRows === 0) {
      return {
        statusCode: 404,
        body: JSON.stringify({
          error: "Evento no encontrado o ya está inactivo",
          eventId: Number(eventId),
        }),
      };
    }

    return {
      statusCode: 200,
      body: JSON.stringify({
        message: eventId
          ? "Evento desactivado exitosamente"
          : "Eventos desactivados exitosamente",
        eventId: eventId ? Number(eventId) : undefined,
        affectedRows: result.affectedRows,
        source: source,
        timestamp: new Date().toISOString(),
      }),
    };
  } catch (err) {
    console.error("❌ Error desactivando eventos:", err);
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
    console.log("🏁 Lambda execution finished");
  }
};
