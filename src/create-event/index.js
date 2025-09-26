const mysql = require("mysql2/promise");
const AWS = require("aws-sdk");
const secretsManager = new AWS.SecretsManager();

exports.handler = async (event) => {
  let connection;
  try {
    // 1. Obtener credenciales de Secrets Manager
    const secretArn = process.env.RDS_SECRET_ARN;
    const secretValue = await secretsManager
      .getSecretValue({ SecretId: secretArn })
      .promise();
    const creds = JSON.parse(secretValue.SecretString);

    // 2. Conexión a la DB
    connection = await mysql.createConnection({
      host: process.env.DB_HOST,
      user: creds.username,
      password: creds.password,
      database: process.env.DB_NAME,
    });

    // 3. Parsear body desde API Gateway
    const body = JSON.parse(event.body);
    const { name, description, start_date, duration, capacity } = body;

    if (!name || !start_date || !capacity) {
      return {
        statusCode: 400,
        body: JSON.stringify({ error: "Campos obligatorios faltantes" }),
      };
    }

    // 4. Insertar en la tabla
    const query = `
      INSERT INTO events (name, description, start_date, duration, capacity, status)
      VALUES (?, ?, ?, ?, ?, 'ACTIVE');
    `;

    await connection.execute(query, [
      name,
      description || "",
      start_date,
      duration || 0,
      capacity,
    ]);

    return {
      statusCode: 201,
      body: JSON.stringify({ message: "Evento creado exitosamente" }),
    };
  } catch (err) {
    console.error("Error creando evento:", err);
    return {
      statusCode: 500,
      body: JSON.stringify({ error: err.message }),
    };
  } finally {
    if (connection) await connection.end();
  }
};
