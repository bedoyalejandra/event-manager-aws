#!/bin/bash

# 🗄️ Script para Ejecutar InitDB - Event Manager AWS
# Este script ejecuta la función Lambda InitDB para crear/actualizar el modelo de base de datos

set -e  # Salir si cualquier comando falla

# Cargar utilidades comunes
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Configuración por defecto
ENVIRONMENT=${ENVIRONMENT:-dev}
AWS_REGION=${AWS_REGION:-us-west-2}

show_banner "RUN INIT DB" "Event Manager AWS"

log_info "Configuración:"
log_info "  - Environment: $ENVIRONMENT"
log_info "  - AWS Region: $AWS_REGION"

# Verificaciones previas
log_info "Verificando credenciales AWS..."
check_aws_credentials || exit 1

# PASO 1: Obtener nombre de la función Lambda
show_progress 1 3 "Obteniendo Información de la Función Lambda"

FUNCTION_NAME="InitDBLambda-${ENVIRONMENT}"

log_info "Verificando que la función Lambda existe..."
if ! aws lambda get-function --function-name "$FUNCTION_NAME" >/dev/null 2>&1; then
    log_error "La función Lambda no existe: $FUNCTION_NAME"
    log_error "Por favor, despliega el stack InitDB primero"
    echo ""
    log_info "Para desplegar InitDB, ejecuta:"
    echo "  aws cloudformation deploy --template-file infra/templates/initdb.yml --stack-name event-manager-initdb-$ENVIRONMENT --capabilities CAPABILITY_NAMED_IAM --parameter-overrides Environment=$ENVIRONMENT"
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

# PASO 4: Verificar tablas creadas (opcional)
echo ""
log_info "Para verificar las tablas creadas, puedes conectarte a la base de datos:"
echo ""
echo "  # Obtener credenciales de Secrets Manager"
echo "  aws secretsmanager get-secret-value --secret-id event-manager-rds-secret-$ENVIRONMENT"
echo ""
echo "  # Conectarse a MySQL"
echo "  mysql -h <DB_ENDPOINT> -u <USERNAME> -p EventManagerDB"
echo ""
echo "  # Listar tablas"
echo "  SHOW TABLES;"
echo ""

# Resumen final
if [[ "$STATUS_CODE" == "200" ]]; then
    show_banner "INIT DB COMPLETADO" "✅ Éxito"
    echo ""
    log_success "Modelo de base de datos actualizado correctamente"
    log_info "Tablas creadas/actualizadas:"
    echo "  - users"
    echo "  - events"
    echo "  - event_assistance"
    echo "  - report"
    echo ""
    log_info "Índices creados para optimizar consultas"
    echo ""
    exit 0
else
    show_banner "INIT DB FALLÓ" "❌ Error"
    echo ""
    log_error "No se pudo actualizar el modelo de base de datos"
    log_info "Revisa los logs arriba para más detalles"
    echo ""
    exit 1
fi
