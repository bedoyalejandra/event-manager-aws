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
      password: "***hidden***"
    });

    connection = await mysql.createConnection({
      host: process.env.DB_HOST,
      user: creds.username,
      password: creds.password,
      database: process.env.DB_NAME,
      connectTimeout: 10000,
    });
    console.log("✅ Database connection established");

    // 3) Validar y obtener ID desde path o query
    // Soporta: REST (event.queryStringParameters) y HTTP API (event.rawQueryString)
    const qs = event.queryStringParameters || {};
    const rawQS = event.rawQueryString || "";

    // id por query: ?id=2
    const qsId =
      qs.id ??
      (rawQS ? new URLSearchParams(rawQS).get("id") : undefined);

    // id por path: /events/2
    const pathId =
      event.pathParameters?.id ??
      (event.rawPath?.match?.(/\/events\/(\d+)(\/)?$/)?.[1]);

    // elige query primero (porque tu URL viene como ?id=2), si no hay, usa path
    const idStr = (qsId ?? pathId ?? "").toString().trim();

    // valida que sea entero positivo
    const eventId = Number(idStr);
    if (!Number.isInteger(eventId) || eventId <= 0) {
      return {
        statusCode: 400,
        body: JSON.stringify({
          error: "El parámetro 'id' es obligatorio y debe ser un entero > 0 (en /events/{id} o ?id=)",
        }),
      };
    }
    
    // 3.1) Validar body (PUT actualiza campos, así que sí exigimos body)
    if (!event.body) {
      return { statusCode: 400, body: JSON.stringify({ error: "Request body is required" }) };
    }

    let bodyData;
    try {
      bodyData = typeof event.body === "string" ? JSON.parse(event.body) : event.body;
    } catch (e) {
      console.error("❌ Error parsing JSON body:", e);
      return { statusCode: 400, body: JSON.stringify({ error: "Invalid JSON format in request body" }) };
    }

    
    const { name, description, start_date, duration, capacity, status } = bodyData;
    console.log("✅ Parsed event data:", bodyData);

    if (!name || !start_date || !capacity || !status) {
      return { statusCode: 400, body: JSON.stringify({ error: "Campos obligatorios faltantes" }) };
    }



    
    // 4) UPDATE
    console.log("💾 Actualizando evento en base de datos...", { eventId });

    const query = `
      UPDATE events
      SET
        name = ?,
        description = ?,
        start_date = ?,
        duration = ?,
        capacity = ?,
        status = ?
      WHERE id = ?;
    `;
    
    const params = [
      name,
      description || "",
      start_date,
      duration ?? 0,
      capacity,
      status,
      eventId, 
    ];

    const [result] = await connection.execute(query, params);


    if (result.affectedRows === 0) {
      return { statusCode: 404, body: JSON.stringify({ error: "Evento no encontrado" }) };
    }

    console.log("✅ Event updated, affectedRows:", result.affectedRows);

    return {
      statusCode: 200,
      body: JSON.stringify({
        message: "Evento actualizado exitosamente",
        id: eventId,
        event: { name, description, start_date, duration: duration ?? 0, capacity, status },
      }),
    };

  } catch (err) {
    console.error("❌ Error actualizando evento:", err);
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