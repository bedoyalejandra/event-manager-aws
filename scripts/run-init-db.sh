#!/bin/bash

# 🗄️ Script para Ejecutar InitDB - Event Manager AWS
# Este script ejecuta la función Lambda InitDB para crear/actualizar el modelo de base de datos
#
# USO:
#   ./scripts/run-init-db.sh [environment]
#
# PROPÓSITO:
#   - Crear tablas de base de datos si no existen
#   - Actualizar estructura de tablas (ALTER TABLE con IF NOT EXISTS)
#   - Crear/actualizar índices para optimización
#   - Verificar conectividad de base de datos
#
# CASOS DE USO:
#   1. Primera vez: Crea todas las tablas e índices
#   2. Actualización: Ejecuta cambios de esquema sin perder datos
#   3. Verificación: Prueba conectividad y estado de la base de datos

set -e  # Salir si cualquier comando falla

# Cargar utilidades comunes
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Configuración por defecto
ENVIRONMENT=${1:-${ENVIRONMENT:-dev}}
AWS_REGION=${AWS_REGION:-us-west-2}

show_banner "RUN INIT DB" "Database Structure Update"

log_info "Configuración:"
log_info "  - Environment: $ENVIRONMENT"
log_info "  - AWS Region: $AWS_REGION"
echo ""

log_warning "⚠️  IMPORTANTE: Este script ejecutará cambios en la base de datos"
log_info "Este script realizará las siguientes operaciones:"
echo "  ✓ Crear tablas si no existen (CREATE TABLE IF NOT EXISTS)"
echo "  ✓ Crear índices si no existen (CREATE INDEX IF NOT EXISTS)"
echo "  ✓ Verificar conectividad de base de datos"
echo "  ✓ NO eliminará datos existentes"
echo ""

# Confirmación del usuario
if ! confirm_action "¿Deseas continuar con la actualización de la base de datos?"; then
    log_info "Operación cancelada por el usuario"
    exit 0
fi

echo ""

# Verificaciones previas
log_info "Verificando credenciales AWS..."
check_aws_credentials || exit 1

# PASO 1: Obtener nombre de la función Lambda
show_progress 1 3 "Obteniendo Información de la Función Lambda"

FUNCTION_NAME="InitDBLambda-${ENVIRONMENT}"

log_info "Verificando que la función Lambda existe..."
if ! aws lambda get-function --function-name "$FUNCTION_NAME" >/dev/null 2>&1; then
    log_error "La función Lambda no existe: $FUNCTION_NAME"
    log_error "Por favor, despliega el stack principal primero"
    echo ""
    log_info "Para desplegar el stack completo (incluye InitDB), ejecuta:"
    echo "  ./scripts/deploy.sh"
    echo ""
    log_info "Nota: InitDB ahora se despliega automáticamente como parte del stack principal"
    exit 1
fi

log_success "Función Lambda encontrada: $FUNCTION_NAME"

# Obtener información de la función
FUNCTION_INFO=$(aws lambda get-function --function-name "$FUNCTION_NAME" --query 'Configuration.[Runtime,MemorySize,Timeout,LastModified]' --output text)
log_info "Detalles de la función:"
echo "  Runtime: $(echo $FUNCTION_INFO | awk '{print $1}')"
echo "  Memory: $(echo $FUNCTION_INFO | awk '{print $2}') MB"
echo "  Timeout: $(echo $FUNCTION_INFO | awk '{print $3}') segundos"
echo "  Última modificación: $(echo $FUNCTION_INFO | awk '{print $4}')"

# PASO 2: Ejecutar la función Lambda
show_progress 2 3 "Ejecutando Función InitDB"

log_info "Invocando función Lambda para inicializar/actualizar base de datos..."
echo ""

# Crear archivo temporal para la respuesta
RESPONSE_FILE=$(mktemp)

# Ejecutar la función y capturar la respuesta
log_info "Ejecutando: aws lambda invoke --function-name $FUNCTION_NAME"
if aws lambda invoke \
    --function-name "$FUNCTION_NAME" \
    --log-type Tail \
    --query 'LogResult' \
    --output text \
    "$RESPONSE_FILE" | base64 --decode; then
    
    echo ""
    log_success "Función ejecutada correctamente"
else
    echo ""
    log_error "Error al ejecutar la función Lambda"
    rm -f "$RESPONSE_FILE"
    exit 1
fi

# PASO 3: Mostrar resultados
show_progress 3 3 "Procesando Resultados"

echo ""
log_info "Respuesta de la función:"
echo "─────────────────────────────────────────"
cat "$RESPONSE_FILE" | jq '.' 2>/dev/null || cat "$RESPONSE_FILE"
echo "─────────────────────────────────────────"

# Verificar el código de estado
STATUS_CODE=$(cat "$RESPONSE_FILE" | jq -r '.statusCode' 2>/dev/null || echo "unknown")

if [[ "$STATUS_CODE" == "200" ]]; then
    log_success "✅ Base de datos inicializada/actualizada correctamente"
    
    # Extraer información de la respuesta
    BODY=$(cat "$RESPONSE_FILE" | jq -r '.body' 2>/dev/null)
    if [[ -n "$BODY" && "$BODY" != "null" ]]; then
        echo ""
        log_info "Detalles de la operación:"
        echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
    fi
else
    log_error "❌ Error al inicializar la base de datos"
    log_error "Código de estado: $STATUS_CODE"
    
    # Mostrar mensaje de error si está disponible
    ERROR_MSG=$(cat "$RESPONSE_FILE" | jq -r '.body' 2>/dev/null)
    if [[ -n "$ERROR_MSG" && "$ERROR_MSG" != "null" ]]; then
        echo ""
        log_error "Mensaje de error:"
        echo "$ERROR_MSG" | jq '.' 2>/dev/null || echo "$ERROR_MSG"
    fi
fi

# Limpiar archivo temporal
rm -f "$RESPONSE_FILE"

# PASO 4: Obtener información de la base de datos
echo ""
log_info "Obteniendo información de la base de datos..."

# Obtener endpoint de la base de datos
DB_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name event-manager \
    --query 'Stacks[0].Outputs[?OutputKey==`DBEndpoint`].OutputValue' \
    --output text 2>/dev/null || echo "")

if [[ -n "$DB_ENDPOINT" ]]; then
    log_success "Database Endpoint: $DB_ENDPOINT"
fi

# Obtener ARN del secreto
SECRET_ARN=$(aws cloudformation describe-stacks \
    --stack-name event-manager \
    --query 'Stacks[0].Outputs[?OutputKey==`DBSecretArn`].OutputValue' \
    --output text 2>/dev/null || echo "")

if [[ -n "$SECRET_ARN" ]]; then
    log_success "Secret ARN: $SECRET_ARN"
fi

echo ""
log_info "═══════════════════════════════════════════════════════════"
log_info "  COMANDOS ÚTILES PARA VERIFICAR LA BASE DE DATOS"
log_info "═══════════════════════════════════════════════════════════"
echo ""
echo "1️⃣  Obtener credenciales de la base de datos:"
echo "   aws secretsmanager get-secret-value --secret-id $SECRET_ARN --query SecretString --output text | jq ."
echo ""
echo "2️⃣  Conectarse a MySQL (requiere mysql client):"
echo "   mysql -h $DB_ENDPOINT -u <USERNAME> -p EventManagerDB"
echo ""
echo "3️⃣  Comandos SQL útiles:"
echo "   SHOW TABLES;                                    # Listar todas las tablas"
echo "   DESCRIBE events;                                # Ver estructura de tabla events"
echo "   SHOW INDEX FROM events;                         # Ver índices de tabla events"
echo "   SELECT COUNT(*) FROM events;                    # Contar eventos"
echo "   SELECT * FROM events ORDER BY created_at DESC LIMIT 5;  # Ver últimos eventos"
echo ""
echo "4️⃣  Ejecutar este script nuevamente para actualizar estructura:"
echo "   ./scripts/run-init-db.sh $ENVIRONMENT"
echo ""

# Resumen final
if [[ "$STATUS_CODE" == "200" ]]; then
    show_banner "INIT DB COMPLETADO" "✅ Éxito"
    echo ""
    log_success "✅ Modelo de base de datos actualizado correctamente"
    echo ""
    log_info "📋 Tablas creadas/actualizadas:"
    echo "   • report           - Reportes de eventos"
    echo "   • events           - Eventos del sistema"
    echo "   • event_assistance - Asistencia a eventos"
    echo ""
    log_info "🚀 Índices creados para optimización:"
    echo "   • idx_status       - Búsqueda por estado de evento"
    echo "   • idx_start_date   - Ordenamiento por fecha"
    echo "   • idx_created_at   - Ordenamiento por creación"
    echo "   • idx_assistance_* - Optimización de consultas de asistencia"
    echo ""
    log_info "💡 La estructura de base de datos está lista para usar"
    echo ""
    exit 0
else
    show_banner "INIT DB FALLÓ" "❌ Error"
    echo ""
    log_error "❌ No se pudo actualizar el modelo de base de datos"
    log_info "Revisa los logs arriba para más detalles"
    echo ""
    log_info "Posibles causas:"
    echo "  • Credenciales de base de datos incorrectas"
    echo "  • Base de datos no accesible desde Lambda"
    echo "  • Security group bloqueando conexión"
    echo "  • Timeout de conexión"
    echo ""
    log_info "Para debugging, revisa los logs de CloudWatch:"
    echo "  aws logs tail /aws/lambda/InitDBLambda-$ENVIRONMENT --follow"
    echo ""
    exit 1
fi
