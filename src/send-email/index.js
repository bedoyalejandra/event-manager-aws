const AWS = require("aws-sdk");
const ses = new AWS.SES();
const {
  generateEventReminderHTML,
  generateEventReminderText,
  generateAttendanceConfirmationHTML,
  generateAttendanceConfirmationText,
  generateReportGeneratedHTML,
  generateReportGeneratedText
} = require('./email-templates');

// Constante para el correo destino
const RECIPIENT_EMAIL = 'alejandrabedoya00@gmail.com';

// Tipos de email soportados
const EMAIL_TYPES = {
  EVENT_REMINDER: 'event_reminder',
  ATTENDANCE_CONFIRMATION: 'attendance_confirmation',
  REPORT_GENERATED: 'report_generated'
};

exports.handler = async (event) => {
  try {
    console.log("📧 Starting Send Email Lambda");
    console.log("Event received:", JSON.stringify(event, null, 2));

    // Parsear el mensaje desde SQS o invocación directa
    let emailData;
    
    if (event.Records && event.Records.length > 0) {
      // Invocado desde SQS
      console.log("📬 Processing message from SQS");
      const sqsMessage = event.Records[0];
      emailData = JSON.parse(sqsMessage.body);
    } else if (event.body) {
      // Invocado desde API Gateway
      console.log("🌐 Processing message from API Gateway");
      emailData = typeof event.body === 'string' ? JSON.parse(event.body) : event.body;
    } else {
      // Invocación directa
      console.log("🔧 Processing direct invocation");
      emailData = event;
    }

    const { 
      emailType, 
      subject, 
      message, 
      eventName, 
      eventDate, 
      eventId,
      attendeeName,
      attendeeEmail,
      reportUrl,
      reportType,
      generatedDate
    } = emailData;

    // Validar datos requeridos
    if (!emailType) {
      console.error("❌ Missing required field: emailType");
      return {
        statusCode: 400,
        body: JSON.stringify({ 
          error: "emailType is required (event_reminder, attendance_confirmation, or report_generated)",
          received: emailData
        })
      };
    }

    console.log(`📋 Processing email type: ${emailType}`);

    // Generar contenido según el tipo de email
    let htmlBody, textBody, emailSubject;

    switch (emailType) {
      case EMAIL_TYPES.EVENT_REMINDER:
        emailSubject = subject || `🔔 Recordatorio: ${eventName}`;
        htmlBody = generateEventReminderHTML(eventName, eventDate, eventId, message);
        textBody = generateEventReminderText(eventName, eventDate, eventId, message);
        break;

      case EMAIL_TYPES.ATTENDANCE_CONFIRMATION:
        emailSubject = subject || `✅ Confirmación de Asistencia - ${eventName}`;
        htmlBody = generateAttendanceConfirmationHTML(eventName, eventDate, eventId, attendeeName, message);
        textBody = generateAttendanceConfirmationText(eventName, eventDate, eventId, attendeeName, message);
        break;

      case EMAIL_TYPES.REPORT_GENERATED:
        emailSubject = subject || `📊 Reporte Generado - ${reportType || 'Event Manager'}`;
        htmlBody = generateReportGeneratedHTML(reportType, reportUrl, generatedDate, eventName, message);
        textBody = generateReportGeneratedText(reportType, reportUrl, generatedDate, eventName, message);
        break;

      default:
        console.error(`❌ Invalid email type: ${emailType}`);
        return {
          statusCode: 400,
          body: JSON.stringify({ 
            error: `Invalid emailType. Must be one of: ${Object.values(EMAIL_TYPES).join(', ')}`,
            received: emailType
          })
        };
    }

    // Configurar parámetros de SES
    const sesParams = {
      Source: RECIPIENT_EMAIL, // Email verificado en SES (mismo que destino para desarrollo)
      Destination: {
        ToAddresses: [attendeeEmail || RECIPIENT_EMAIL] // Usar email del asistente si está disponible
      },
      Message: {
        Subject: {
          Data: emailSubject,
          Charset: 'UTF-8'
        },
        Body: {
          Html: {
            Data: htmlBody,
            Charset: 'UTF-8'
          },
          Text: {
            Data: textBody,
            Charset: 'UTF-8'
          }
        }
      }
    };

    console.log("📤 Sending email via SES...");
    console.log("Email parameters:", {
      to: attendeeEmail || RECIPIENT_EMAIL,
      subject: emailSubject,
      type: emailType,
      hasHtml: true,
      hasText: true
    });

    // Enviar email
    const result = await ses.sendEmail(sesParams).promise();
    
    console.log("✅ Email sent successfully");
    console.log("SES MessageId:", result.MessageId);

    return {
      statusCode: 200,
      body: JSON.stringify({ 
        message: "Email sent successfully",
        messageId: result.MessageId,
        recipient: attendeeEmail || RECIPIENT_EMAIL,
        subject: emailSubject,
        emailType: emailType
      })
    };

  } catch (error) {
    console.error("❌ Error sending email:", error);
    console.error("Error details:", {
      message: error.message,
      code: error.code,
      stack: error.stack
    });

    return {
      statusCode: 500,
      body: JSON.stringify({ 
        error: "Failed to send email",
        message: error.message,
        code: error.code || "UNKNOWN_ERROR"
      })
    };
  }
};