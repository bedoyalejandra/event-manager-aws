const mysql = require("mysql2/promise");
const AWS = require("aws-sdk");
const secretsManager = new AWS.SecretsManager();
const sqs = new AWS.SQS();

/**
 * Lambda function triggered by EventBridge Scheduler to send event reminders.
 * Gets all participants of an event and sends reminder messages to SQS queue.
 */
exports.handler = async (event) => {
  let connection;
  try {
    console.log("🔔 Starting Send Event Reminder Lambda");
    console.log("Event received:", JSON.stringify(event, null, 2));

    // Extract event details from EventBridge Scheduler input
    const { eventId, source } = event;

    console.log("📋 Processing reminder for eventId:", eventId);

    // Validate required fields
    if (!eventId) {
      console.error("❌ Missing required field: eventId");
      return {
        statusCode: 400,
        body: JSON.stringify({ 
          error: "Missing required field: eventId" 
        })
      };
    }

    // Get SQS queue URL from environment
    const queueUrl = process.env.EMAIL_QUEUE;
    if (!queueUrl) {
      console.error("❌ EMAIL_QUEUE environment variable not set");
      return {
        statusCode: 500,
        body: JSON.stringify({ error: "Email queue not configured" })
      };
    }

    // 1. Get database credentials from Secrets Manager
    console.log("📡 Fetching credentials from Secrets Manager...");
    const secretArn = process.env.RDS_SECRET_ARN;
    const secretValue = await secretsManager
      .getSecretValue({ SecretId: secretArn })
      .promise();
    const creds = JSON.parse(secretValue.SecretString);
    console.log("✅ Credentials fetched successfully");

    // 2. Connect to database
    console.log("🔌 Attempting database connection...");
    connection = await mysql.createConnection({
      host: process.env.DB_HOST,
      user: creds.username,
      password: creds.password,
      database: process.env.DB_NAME,
      connectTimeout: 10000,
    });
    console.log("✅ Database connection established");

    // 3. Get event details
    console.log("📋 Fetching event details...");
    const [eventRows] = await connection.execute(
      "SELECT id, name, description, start_date, status FROM events WHERE id = ?",
      [eventId]
    );

    if (eventRows.length === 0) {
      console.error("❌ Event not found");
      return {
        statusCode: 404,
        body: JSON.stringify({ error: "Event not found" })
      };
    }

    const eventData = eventRows[0];
    console.log("✅ Event found:", eventData);

    // 4. Get all participants registered for this event with their details
    console.log("👥 Fetching event participants...");
    const participantsQuery = `
      SELECT 
        ea.user_id,
        ea.user_name,
        ea.user_email,
        ea.attendance_status,
        ea.created_at
      FROM event_assistance ea
      WHERE ea.event_id = ? 
        AND ea.attendance_status IN ('REGISTERED', 'CONFIRMED')
      ORDER BY ea.created_at ASC
    `;

    const [participants] = await connection.execute(participantsQuery, [eventId]);
    
    console.log(`✅ Found ${participants.length} participants for event ${eventId}`);

    if (participants.length === 0) {
      console.log("⚠️ No participants found for this event");
      return {
        statusCode: 200,
        body: JSON.stringify({
          message: "No participants to send reminders to",
          eventId: eventId,
          participantCount: 0
        })
      };
    }

    // 5. Send reminder message to SQS for each participant
    console.log("📤 Sending reminder messages to SQS queue...");
    const messagePromises = [];
    const sentMessages = [];

    for (const participant of participants) {
      // Use stored user details from event_assistance table
      const userName = participant.user_name || `User ${participant.user_id}`;
      const userEmail = participant.user_email || `user${participant.user_id}@example.com`;
      
      const emailMessage = {
        emailType: 'event_reminder',
        subject: `🔔 Recordatorio: ${eventData.name} comienza en 5 minutos`,
        eventName: eventData.name,
        eventDate: eventData.start_date,
        eventId: eventId,
        attendeeName: userName,
        attendeeEmail: userEmail,
        message: `Hola ${userName}, tu evento "${eventData.name}" comenzará en 5 minutos. ¡No te lo pierdas!`
      };

      const sqsParams = {
        QueueUrl: queueUrl,
        MessageBody: JSON.stringify(emailMessage),
        MessageAttributes: {
          'EmailType': {
            DataType: 'String',
            StringValue: 'event_reminder'
          },
          'EventId': {
            DataType: 'Number',
            StringValue: String(eventId)
          },
          'UserId': {
            DataType: 'Number',
            StringValue: String(participant.user_id)
          }
        }
      };

      // Send message to SQS
      const messagePromise = sqs.sendMessage(sqsParams).promise()
        .then(result => {
          console.log(`✅ Message sent for user ${participant.user_id}, MessageId: ${result.MessageId}`);
          sentMessages.push({
            userId: participant.user_id,
            messageId: result.MessageId
          });
          return result;
        })
        .catch(error => {
          console.error(`❌ Failed to send message for user ${participant.user_id}:`, error.message);
          throw error;
        });

      messagePromises.push(messagePromise);
    }

    // Wait for all messages to be sent
    await Promise.all(messagePromises);

    console.log(`✅ Successfully sent ${sentMessages.length} reminder messages to SQS`);

    return {
      statusCode: 200,
      body: JSON.stringify({
        message: "Event reminders sent to queue successfully",
        eventId: eventId,
        eventName: eventData.name,
        participantCount: participants.length,
        messagesSent: sentMessages.length,
        queueUrl: queueUrl,
        sentMessages: sentMessages
      })
    };

  } catch (error) {
    console.error("❌ Error sending event reminders:", error);
    console.error("Error details:", {
      message: error.message,
      code: error.code,
      stack: error.stack
    });

    return {
      statusCode: 500,
      body: JSON.stringify({
        error: "Failed to send event reminders",
        message: error.message,
        code: error.code || "UNKNOWN_ERROR"
      })
    };
  } finally {
    if (connection) {
      console.log("🔌 Closing database connection");
      await connection.end();
    }
    console.log("🏁 Lambda execution finished");
  }
};