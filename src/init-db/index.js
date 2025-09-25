const mysql = require("mysql2/promise");
const AWS = require("aws-sdk");
const secretsManager = new AWS.SecretsManager();

exports.handler = async () => {
  let connection;
  try {
    const secretArn = process.env.RDS_SECRET_ARN;
    const secretValue = await secretsManager
      .getSecretValue({ SecretId: secretArn })
      .promise();
    const creds = JSON.parse(secretValue.SecretString);

    connection = await mysql.createConnection({
      host: creds.host,
      user: creds.username,
      password: creds.password,
      database: process.env.DB_NAME,
    });

    const ddl = `
      CREATE TABLE IF NOT EXISTS events (
        id INT AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        description TEXT,
        start_date DATETIME NOT NULL,
        duration INT,
        capacity INT NOT NULL,
        status VARCHAR(20) DEFAULT 'ACTIVE'
      );
      CREATE INDEX IF NOT EXISTS idx_status ON events(status);
      CREATE INDEX IF NOT EXISTS idx_start_date ON events(start_date);
    `;

    await connection.query(ddl);
    console.log("Tabla 'events' creada/verificada exitosamente.");

    return { statusCode: 200, body: "Tabla creada/verificada" };
  } catch (err) {
    console.error("Error creando tabla:", err);
    return { statusCode: 500, body: JSON.stringify({ message: err.message, stack: err.stack }) };
  } finally {
    if (connection) await connection.end();
  }
};
