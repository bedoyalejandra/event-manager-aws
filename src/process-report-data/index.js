// process-report-data/index.js
const AWS = require('aws-sdk');
const mysql = require('mysql2/promise');

const secretsManager = new AWS.SecretsManager();

/**
 * SQS -> Lambda (event.Records)
 * Inserta cada mensaje en la tabla `report`:
 *   - tickets_sold (INT)
 *   - event_name (VARCHAR)
 *   - created_at (VARCHAR o DATETIME según tu schema)
 */
exports.handler = async (event) => {
  console.log("🔔 ProcessReportDataLambda-dev - Records:", event.Records?.length || 0);

  const failures = [];

  let connection;
  try {
    // 1. Secret
    const secretArn = process.env.RDS_SECRET_ARN;
    if (!secretArn) throw new Error('RDS_SECRET_ARN no configurado');

    const secretValue = await secretsManager.getSecretValue({ SecretId: secretArn }).promise();
    const creds = JSON.parse(secretValue.SecretString);

    // 2. Conexión
    connection = await mysql.createConnection({
      host: process.env.DB_HOST,
      user: creds.username,
      password: creds.password,
      database: process.env.DB_NAME,
      connectTimeout: 10000,
    });
    console.log("✅ Conexión a BD establecida");

    // 3. Procesar mensajes
    for (const record of event.Records || []) {
      try {
        const body = JSON.parse(record.body);
        console.log("📥 Mensaje:", body);

        // Normalización/validación
        const tickets_sold = Number(body.tickets_sold);
        const event_name = String(body.event_name || '').trim();
        const created_at = String(body.created_at || '').trim();

        if (!Number.isFinite(tickets_sold) || !event_name || !created_at) {
          throw new Error('Payload inválido: se esperan tickets_sold (numérico), event_name, created_at');
        }

        // Inserción (ajusta nombres/columnas según tu esquema)
        const sql = `
          INSERT INTO report (tickets_sold, event_name, created_at)
          VALUES (?, ?, ?)
        `;
        const params = [tickets_sold, event_name, created_at];

        const [result] = await connection.execute(sql, params);
        console.log(`📝 Insert OK (insertId=${result.insertId}) para MessageId=${record.messageId}`);
      } catch (msgErr) {
        console.error(`❌ Error en mensaje ${record.messageId}:`, msgErr);
        // SQS Partial Batch Failure para reintentar solo este mensaje
        failures.push({ itemIdentifier: record.messageId });
      }
    }
  } catch (err) {
    console.error("🚨 Error general en ProcessReportDataLambda:", err);
    // Si falla la inicialización (p.ej., DB), marca TODOS como fallo para reintento
    for (const r of event.Records || []) {
      failures.push({ itemIdentifier: r.messageId });
    }
  } finally {
    if (connection) {
      await connection.end().catch(() => {});
      console.log("🔌 Conexión a BD cerrada");
    }
  }

  // Respuesta para SQS (Partial Batch Response)
  return { batchItemFailures: failures };
};
