// post-report/index.js
const AWS = require('aws-sdk');
const sqs = new AWS.SQS();

/**
 * Lambda expuesta via API Gateway (POST) para recibir el cuerpo JSON:
 * {
 *   "tickets_sold": "140",
 *   "event_name": "sakira",
 *   "created_at": "junio"
 * }
 */
exports.handler = async (event) => {
  try {
    console.log("🔔 PostReportLambda-dev - Event:", JSON.stringify(event));

    // Si viene de API Gateway, el body es string
    const payload = typeof event.body === 'string' ? JSON.parse(event.body) : (event.body || event);

    const { tickets_sold, event_name, created_at } = payload || {};

    // Validación mínima
    const errors = [];
    if (tickets_sold == null || tickets_sold === '') errors.push('tickets_sold');
    if (!event_name) errors.push('event_name');
    if (!created_at) errors.push('created_at');

    if (errors.length) {
      console.error("❌ Campos faltantes:", errors);
      return {
        statusCode: 400,
        body: JSON.stringify({ error: `Faltan campos: ${errors.join(', ')}` }),
      };
    }

    const queueUrl = process.env.REPORT_QUEUE_URL;
    if (!queueUrl) {
      console.error("❌ REPORT_QUEUE_URL no configurada");
      return {
        statusCode: 500,
        body: JSON.stringify({ error: "Cola SQS (REPORT_QUEUE_URL) no configurada" }),
      };
    }

    // Construir el mensaje a SQS
    const messageBody = {
      tickets_sold: String(tickets_sold),
      event_name,
      created_at,
      source: 'PostReportLambda',
      received_at: new Date().toISOString(),
    };

    const params = {
      QueueUrl: queueUrl,
      MessageBody: JSON.stringify(messageBody),
      MessageAttributes: {
        EventType: { DataType: 'String', StringValue: 'report' },
        Env: { DataType: 'String', StringValue: process.env.ENVIRONMENT || 'dev' },
      },
      // Opcional: FIFO/GroupId si tu cola fuera FIFO
      // MessageGroupId: 'report-group-1',
    };

    console.log("📤 Enviando a SQS:", params);
    const res = await sqs.sendMessage(params).promise();
    console.log("✅ Enviado a SQS. MessageId:", res.MessageId);

    return {
      statusCode: 200,
      body: JSON.stringify({
        message: 'Mensaje enviado a SQS',
        messageId: res.MessageId,
        queueUrl,
        data: messageBody,
      }),
    };
  } catch (err) {
    console.error("❌ Error PostReportLambda:", err);
    return {
      statusCode: 500,
      body: JSON.stringify({ error: 'Fallo enviando a SQS', details: err.message }),
    };
  }
};