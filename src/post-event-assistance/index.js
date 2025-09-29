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
    
    const { eventId, ticketsPurchased } = bodyData;
    console.log("✅ Parsed event data:", bodyData);

    if (!eventId || !ticketsPurchased) {
      return {
        statusCode: 400,
        body: JSON.stringify({ error: "Campos obligatorios faltantes" }),
      };
    }

    // 4. Actualizar asistencia a eventos
    console.log("📋 Updating event attendance...");
    const query = `
      UPDATE events
      SET capacity = capacity - ?
      WHERE id = ? AND capacity >= ?;
    `;

    // Extraer los datos del cuerpo de la solicitud
    if (!eventId || !ticketsPurchased) {
      return {
        statusCode: 400,
        body: JSON.stringify({
        error: "Faltan campos obligatorios: eventId y ticketsPurchased",
    }),
  };
}

    // Ejecutar la consulta con los valores proporcionados
    const [result] = await connection.execute(query, [
      ticketsPurchased, // Cantidad de entradas compradas
      eventId,          // ID del evento
      ticketsPurchased, // Validar que la capacidad sea suficiente
    ]);

    // Verificar si se actualizó alguna fila
    if (result.affectedRows === 0) {
      return {
        statusCode: 400,
        body: JSON.stringify({
        message: "No se pudo actualizar el evento. Verifica que el evento exista y tenga capacidad suficiente.",
      }),
    };
  }
    console.log("✅ Event attendance updated successfully");

      return {
        statusCode: 200,
        body: JSON.stringify({
          message: "Capacidad del evento actualizada exitosamente",
          eventId: eventId,
          ticketsPurchased: ticketsPurchased,
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