#!/bin/bash

# 🗄️ Script para Inicializar Base de Datos - Event Manager AWS
# Este script ejecuta la función InitDB manualmente si es necesario

set -e

# Cargar utilidades comunes
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Configuración
ENVIRONMENT=${ENVIRONMENT:-dev}

show_banner "INIT DATABASE" "Event Manager AWS"

log_info "Configuración:"
log_info "  - Environment: $ENVIRONMENT"

# Verificar que AWS CLI esté configurado
check_aws_credentials || exit 1

# Obtener el nombre de la función desde el stack
log_info "Obteniendo información de la función InitDB..."
INIT_LAMBDA_NAME=$(aws cloudformation describe-stacks \
    --stack-name event-manager-initdb \
    --query 'Stacks[0].Outputs[?OutputKey==`InitDBLambdaName`].OutputValue' \
    --output text 2>/dev/null || echo "")

if [[ -z "$INIT_LAMBDA_NAME" ]]; then
    log_error "No se pudo encontrar el stack event-manager-initdb"
    log_info "¿Has ejecutado el deploy script completo?"
    log_info "Ejecuta: ./scripts/deploy.sh"
    exit 1
fi

log_success "Función encontrada: $INIT_LAMBDA_NAME"

# Ejecutar la función
log_info "Ejecutando función InitDB para crear/verificar tablas..."

aws lambda invoke \
    --function-name "$INIT_LAMBDA_NAME" \
    --log-type Tail \
    --payload '{}' \
    /tmp/init-db-response.json

# Verificar respuesta
if [[ -f "/tmp/init-db-response.json" ]]; then
    INIT_RESULT=$(cat /tmp/init-db-response.json)
    
    show_header "RESPUESTA DE LA FUNCIÓN" $YELLOW
    echo "$INIT_RESULT" | jq . 2>/dev/null || echo "$INIT_RESULT"
    
    if echo "$INIT_RESULT" | grep -q '"statusCode":200'; then
        log_success "✅ Base de datos inicializada correctamente"
        
        # Mostrar logs de la función
        log_info "Mostrando logs recientes de la función..."
        aws logs filter-log-events \
            --log-group-name "/aws/lambda/$INIT_LAMBDA_NAME" \
            --start-time $(date -d '10 minutes ago' +%s)000 \
            --query 'events[].message' \
            --output text | tail -20
    else
        log_error "❌ Error al inicializar la base de datos"
        exit 1
    fi
else
    log_error "No se pudo obtener respuesta de la función InitDB"
    exit 1
fi

log_success "¡Inicialización de base de datos completada!"

# Limpiar archivos temporales
rm -f /tmp/init-db-response.json
