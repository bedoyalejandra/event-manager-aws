// ============================================================================
// EMAIL TEMPLATES
// ============================================================================

/**
 * Genera el HTML para un email de recordatorio de evento
 */
function generateEventReminderHTML(eventName, eventDate, eventId, customMessage) {
  const formattedDate = eventDate ? new Date(eventDate).toLocaleString('es-ES', {
    weekday: 'long',
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit'
  }) : 'Fecha por confirmar';

  return `
    <!DOCTYPE html>
    <html>
      <head>
        <style>
          body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; margin: 0; padding: 0; }
          .container { max-width: 600px; margin: 0 auto; padding: 20px; }
          .header { background-color: #FF9800; color: white; padding: 30px 20px; text-align: center; border-radius: 5px 5px 0 0; }
          .header h1 { margin: 0; font-size: 28px; }
          .header .icon { font-size: 48px; margin-bottom: 10px; }
          .content { background-color: #f9f9f9; padding: 30px 20px; border: 1px solid #ddd; }
          .event-details { background-color: white; padding: 20px; margin: 20px 0; border-left: 4px solid #FF9800; border-radius: 4px; }
          .event-details h3 { margin-top: 0; color: #FF9800; }
          .detail-row { margin: 10px 0; }
          .detail-row strong { color: #555; }
          .footer { text-align: center; margin-top: 20px; padding: 20px; font-size: 12px; color: #777; background-color: #f0f0f0; border-radius: 0 0 5px 5px; }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="header">
            <div class="icon">🔔</div>
            <h1>Recordatorio de Evento</h1>
          </div>
          <div class="content">
            <p style="font-size: 16px;">¡Hola!</p>
            <p>${customMessage || 'Te recordamos que tienes un evento próximo:'}</p>
            
            <div class="event-details">
              <h3>📅 Detalles del Evento</h3>
              <div class="detail-row">
                <strong>Evento:</strong> ${eventName || 'Sin nombre'}
              </div>
              <div class="detail-row">
                <strong>Fecha y Hora:</strong> ${formattedDate}
              </div>
              ${eventId ? `<div class="detail-row"><strong>ID del Evento:</strong> ${eventId}</div>` : ''}
            </div>
            
            <p style="margin-top: 20px;">No olvides prepararte para el evento. ¡Te esperamos!</p>
          </div>
          <div class="footer">
            <p>Este es un correo automático del sistema Event Manager.</p>
            <p>Por favor no responder a este correo.</p>
          </div>
        </div>
      </body>
    </html>
  `;
}

/**
 * Genera el texto plano para un email de recordatorio de evento
 */
function generateEventReminderText(eventName, eventDate, eventId, customMessage) {
  const formattedDate = eventDate ? new Date(eventDate).toLocaleString('es-ES') : 'Fecha por confirmar';
  
  return `
🔔 RECORDATORIO DE EVENTO

¡Hola!

${customMessage || 'Te recordamos que tienes un evento próximo:'}

📅 DETALLES DEL EVENTO
- Evento: ${eventName || 'Sin nombre'}
- Fecha y Hora: ${formattedDate}
${eventId ? `- ID del Evento: ${eventId}` : ''}

No olvides prepararte para el evento. ¡Te esperamos!

---
Este es un correo automático del sistema Event Manager.
Por favor no responder a este correo.
  `.trim();
}

/**
 * Genera el HTML para un email de confirmación de asistencia
 */
function generateAttendanceConfirmationHTML(eventName, eventDate, eventId, attendeeName, customMessage) {
  const formattedDate = eventDate ? new Date(eventDate).toLocaleString('es-ES', {
    weekday: 'long',
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit'
  }) : 'Fecha por confirmar';

  return `
    <!DOCTYPE html>
    <html>
      <head>
        <style>
          body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; margin: 0; padding: 0; }
          .container { max-width: 600px; margin: 0 auto; padding: 20px; }
          .header { background-color: #4CAF50; color: white; padding: 30px 20px; text-align: center; border-radius: 5px 5px 0 0; }
          .header h1 { margin: 0; font-size: 28px; }
          .header .icon { font-size: 48px; margin-bottom: 10px; }
          .content { background-color: #f9f9f9; padding: 30px 20px; border: 1px solid #ddd; }
          .confirmation-box { background-color: #E8F5E9; padding: 20px; margin: 20px 0; border-left: 4px solid #4CAF50; border-radius: 4px; text-align: center; }
          .confirmation-box h2 { margin: 0; color: #4CAF50; font-size: 24px; }
          .event-details { background-color: white; padding: 20px; margin: 20px 0; border-radius: 4px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
          .event-details h3 { margin-top: 0; color: #4CAF50; }
          .detail-row { margin: 10px 0; }
          .detail-row strong { color: #555; }
          .footer { text-align: center; margin-top: 20px; padding: 20px; font-size: 12px; color: #777; background-color: #f0f0f0; border-radius: 0 0 5px 5px; }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="header">
            <div class="icon">✅</div>
            <h1>Confirmación de Asistencia</h1>
          </div>
          <div class="content">
            <p style="font-size: 16px;">¡Hola ${attendeeName || 'Asistente'}!</p>
            
            <div class="confirmation-box">
              <h2>¡Tu asistencia ha sido confirmada!</h2>
            </div>
            
            <p>${customMessage || 'Gracias por confirmar tu asistencia. Aquí están los detalles del evento:'}</p>
            
            <div class="event-details">
              <h3>📅 Detalles del Evento</h3>
              <div class="detail-row">
                <strong>Evento:</strong> ${eventName || 'Sin nombre'}
              </div>
              <div class="detail-row">
                <strong>Fecha y Hora:</strong> ${formattedDate}
              </div>
              ${eventId ? `<div class="detail-row"><strong>ID del Evento:</strong> ${eventId}</div>` : ''}
            </div>
            
            <p style="margin-top: 20px;">Te enviaremos un recordatorio antes del evento. ¡Nos vemos pronto!</p>
          </div>
          <div class="footer">
            <p>Este es un correo automático del sistema Event Manager.</p>
            <p>Por favor no responder a este correo.</p>
          </div>
        </div>
      </body>
    </html>
  `;
}

/**
 * Genera el texto plano para un email de confirmación de asistencia
 */
function generateAttendanceConfirmationText(eventName, eventDate, eventId, attendeeName, customMessage) {
  const formattedDate = eventDate ? new Date(eventDate).toLocaleString('es-ES') : 'Fecha por confirmar';
  
  return `
✅ CONFIRMACIÓN DE ASISTENCIA

¡Hola ${attendeeName || 'Asistente'}!

¡Tu asistencia ha sido confirmada!

${customMessage || 'Gracias por confirmar tu asistencia. Aquí están los detalles del evento:'}

📅 DETALLES DEL EVENTO
- Evento: ${eventName || 'Sin nombre'}
- Fecha y Hora: ${formattedDate}
${eventId ? `- ID del Evento: ${eventId}` : ''}

Te enviaremos un recordatorio antes del evento. ¡Nos vemos pronto!

---
Este es un correo automático del sistema Event Manager.
Por favor no responder a este correo.
  `.trim();
}

/**
 * Genera el HTML para un email de reporte generado
 */
function generateReportGeneratedHTML(reportType, reportUrl, generatedDate, eventName, customMessage) {
  const formattedDate = generatedDate ? new Date(generatedDate).toLocaleString('es-ES', {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit'
  }) : new Date().toLocaleString('es-ES');

  return `
    <!DOCTYPE html>
    <html>
      <head>
        <style>
          body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; margin: 0; padding: 0; }
          .container { max-width: 600px; margin: 0 auto; padding: 20px; }
          .header { background-color: #2196F3; color: white; padding: 30px 20px; text-align: center; border-radius: 5px 5px 0 0; }
          .header h1 { margin: 0; font-size: 28px; }
          .header .icon { font-size: 48px; margin-bottom: 10px; }
          .content { background-color: #f9f9f9; padding: 30px 20px; border: 1px solid #ddd; }
          .report-box { background-color: white; padding: 20px; margin: 20px 0; border-radius: 4px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
          .report-box h3 { margin-top: 0; color: #2196F3; }
          .detail-row { margin: 10px 0; }
          .detail-row strong { color: #555; }
          .download-button { display: inline-block; background-color: #2196F3; color: white; padding: 12px 30px; text-decoration: none; border-radius: 5px; margin: 20px 0; font-weight: bold; }
          .download-button:hover { background-color: #1976D2; }
          .footer { text-align: center; margin-top: 20px; padding: 20px; font-size: 12px; color: #777; background-color: #f0f0f0; border-radius: 0 0 5px 5px; }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="header">
            <div class="icon">📊</div>
            <h1>Reporte Generado</h1>
          </div>
          <div class="content">
            <p style="font-size: 16px;">¡Hola!</p>
            <p>${customMessage || 'Tu reporte ha sido generado exitosamente y está listo para descargar.'}</p>
            
            <div class="report-box">
              <h3>📄 Información del Reporte</h3>
              <div class="detail-row">
                <strong>Tipo de Reporte:</strong> ${reportType || 'Reporte General'}
              </div>
              ${eventName ? `<div class="detail-row"><strong>Evento:</strong> ${eventName}</div>` : ''}
              <div class="detail-row">
                <strong>Fecha de Generación:</strong> ${formattedDate}
              </div>
            </div>
            
            ${reportUrl ? `
              <div style="text-align: center;">
                <a href="${reportUrl}" class="download-button">📥 Descargar Reporte</a>
              </div>
              <p style="font-size: 12px; color: #777; text-align: center;">
                El enlace de descarga estará disponible por 7 días.
              </p>
            ` : '<p style="color: #f44336;">El enlace de descarga no está disponible en este momento.</p>'}
          </div>
          <div class="footer">
            <p>Este es un correo automático del sistema Event Manager.</p>
            <p>Por favor no responder a este correo.</p>
          </div>
        </div>
      </body>
    </html>
  `;
}

/**
 * Genera el texto plano para un email de reporte generado
 */
function generateReportGeneratedText(reportType, reportUrl, generatedDate, eventName, customMessage) {
  const formattedDate = generatedDate ? new Date(generatedDate).toLocaleString('es-ES') : new Date().toLocaleString('es-ES');
  
  return `
📊 REPORTE GENERADO

¡Hola!

${customMessage || 'Tu reporte ha sido generado exitosamente y está listo para descargar.'}

📄 INFORMACIÓN DEL REPORTE
- Tipo de Reporte: ${reportType || 'Reporte General'}
${eventName ? `- Evento: ${eventName}` : ''}
- Fecha de Generación: ${formattedDate}

${reportUrl ? `
📥 DESCARGAR REPORTE
${reportUrl}

El enlace de descarga estará disponible por 7 días.
` : 'El enlace de descarga no está disponible en este momento.'}

---
Este es un correo automático del sistema Event Manager.
Por favor no responder a este correo.
  `.trim();
}

module.exports = {
  generateEventReminderHTML,
  generateEventReminderText,
  generateAttendanceConfirmationHTML,
  generateAttendanceConfirmationText,
  generateReportGeneratedHTML,
  generateReportGeneratedText
};
