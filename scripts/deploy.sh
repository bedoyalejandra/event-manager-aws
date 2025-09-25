#!/bin/bash

# 🚀 Script de Despliegue Automatizado - Event Manager AWS
# Este script automatiza todo el proceso de despliegue manual

set -e  # Salir si cualquier comando falla

# Cargar utilidades comunes
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Configuración por defecto
ENVIRONMENT=${ENVIRONMENT:-dev}
DB_USERNAME=${DB_USERNAME:-event_admin}
AWS_REGION=${AWS_REGION:-us-west-2}

show_banner "EVENT MANAGER AWS DEPLOY" "Script Automatizado"

log_info "Configuración:"
log_info "  - Environment: $ENVIRONMENT"
log_info "  - DB Username: $DB_USERNAME"
log_info "  - AWS Region: $AWS_REGION"

# PASO 0: Verificaciones previas
show_progress 0 9 "Verificaciones Previas"

check_aws_credentials || exit 1

check_project_structure || exit 1

# Verificar si ya existen stacks
log_info "Verificando stacks existentes..."
EXISTING_STACKS=$(aws cloudformation list-stacks \
    --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
    --query 'StackSummaries[?contains(StackName, `event-manager`)].StackName' \
    --output text)

if [[ -n "$EXISTING_STACKS" ]]; then
    log_warning "Se encontraron stacks existentes: $EXISTING_STACKS"
    if ! confirm_action "¿Deseas continuar? Esto podría actualizar los stacks existentes"; then
        log_info "Despliegue cancelado por el usuario."
        exit 0
    fi
fi

# PASO 1: Preparar el entorno
show_progress 1 10 "Preparando el Entorno"

log_info "Configurando variables de entorno..."
export AWS_DEFAULT_REGION=$AWS_CURRENT_REGION
export ENVIRONMENT=$ENVIRONMENT
export DB_USERNAME=$DB_USERNAME

log_success "Variables de entorno configuradas"

# PASO 2: Empaquetar funciones Lambda
show_progress 2 10 "Empaquetando Funciones Lambda"

log_info "Creando archivo ZIP con funciones Lambda..."
if [[ -f "lambda-functions.zip" ]]; then
    log_warning "Eliminando lambda-functions.zip existente..."
    rm lambda-functions.zip
fi

zip -r lambda-functions.zip src/ > /dev/null
LAMBDA_ZIP_SIZE=$(ls -lh lambda-functions.zip | awk '{print $5}')
log_success "Archivo lambda-functions.zip creado (Tamaño: $LAMBDA_ZIP_SIZE)"

# PASO 3: Crear bucket S3 para código Lambda
show_progress 3 10 "Creando Bucket S3 para Código Lambda"

log_info "Desplegando template S3..."
aws cloudformation deploy \
    --template-file infra/templates/s3.yml \
    --stack-name event-manager-s3 \
    --capabilities CAPABILITY_IAM \
    --parameter-overrides Environment=$ENVIRONMENT

log_success "Stack event-manager-s3 desplegado correctamente"

# PASO 4: Obtener nombre del bucket creado
show_progress 4 10 "Obteniendo Información del Bucket S3"

log_info "Obteniendo nombre del bucket Lambda..."
LAMBDA_BUCKET=$(get_stack_output event-manager-s3 LambdaCodeBucketName)

if [[ -z "$LAMBDA_BUCKET" ]]; then
    log_error "No se pudo obtener el nombre del bucket Lambda"
    exit 1
fi

log_success "Bucket Lambda obtenido: $LAMBDA_BUCKET"

# PASO 5: Subir código Lambda al bucket
show_progress 5 10 "Subiendo Código Lambda al Bucket"

log_info "Subiendo lambda-functions.zip al bucket S3..."
aws s3 cp lambda-functions.zip s3://$LAMBDA_BUCKET/lambda-functions.zip

log_info "Verificando que el archivo se subió correctamente..."
aws s3 ls s3://$LAMBDA_BUCKET/lambda-functions.zip

log_success "Código Lambda subido correctamente"

# PASO 6: Subir templates de nested stacks a S3
show_progress 6 10 "Subiendo Templates de Nested Stacks"

log_info "Subiendo templates de nested stacks al bucket S3..."
aws s3 cp infra/templates/ s3://$LAMBDA_BUCKET/templates/ --recursive --exclude "*.md"

log_info "Verificando que los templates se subieron correctamente..."
aws s3 ls s3://$LAMBDA_BUCKET/templates/

log_success "Templates de nested stacks subidos correctamente"

# PASO 7: Validar template principal
show_progress 7 10 "Validando Template Principal"

validate_template infra/master-template.yml || exit 1

# PASO 8: Desplegar infraestructura principal
show_progress 8 10 "Desplegando Infraestructura Principal"

log_warning "Este paso puede tomar 15-20 minutos. Por favor, sé paciente..."
log_info "Desplegando stack principal con todos los servicios..."

aws cloudformation deploy \
    --template-file infra/master-template.yml \
    --stack-name event-manager \
    --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
    --parameter-overrides \
        Environment=$ENVIRONMENT \
        DBUsername=$DB_USERNAME \
        S3LambdaBucket=$LAMBDA_BUCKET \
        LambdaCodeKey=lambda-functions.zip \
        CreateS3Buckets=false \
        ExistingLambdaCodeBucket=$LAMBDA_BUCKET \
        ExistingReportsBucket=event-manager-reports-$ENVIRONMENT-$(aws sts get-caller-identity --query Account --output text) \
        CreateSESResources=false \
        ExistingSESConfigurationSet=event-manager-config-set-$ENVIRONMENT

log_success "Stack principal desplegado correctamente"

# PASO 9: Verificar el despliegue
show_progress 9 10 "Verificando el Despliegue"

log_info "Verificando estado del stack principal..."
aws cloudformation describe-stacks --stack-name event-manager --query 'Stacks[0].StackStatus' --output text

log_info "Obteniendo outputs del stack..."
show_header "OUTPUTS DEL STACK" $YELLOW
aws cloudformation describe-stacks \
    --stack-name event-manager \
    --query 'Stacks[0].Outputs' \
    --output table

log_info "Listando todos los stacks creados..."
show_header "STACKS CREADOS" $YELLOW
list_event_manager_stacks

# PASO 10: Verificar funciones Lambda
show_progress 10 10 "Verificando Funciones Lambda"

log_info "Listando funciones Lambda creadas..."
show_header "FUNCIONES LAMBDA CREADAS" $YELLOW
aws lambda list-functions \
    --query 'Functions[?contains(FunctionName, `event-manager`)].{Name:FunctionName,Runtime:Runtime,LastModified:LastModified}' \
    --output table

# Limpiar archivos temporales
cleanup_temp_files

# RESUMEN FINAL
show_banner "¡DESPLIEGUE COMPLETADO!" "" $GREEN

log_success "El sistema Event Manager AWS ha sido desplegado exitosamente"

show_header "INFORMACIÓN IMPORTANTE" $YELLOW

# Obtener información importante
API_URL=$(get_stack_output event-manager ApiGatewayUrl)
USER_POOL_ID=$(get_stack_output event-manager CognitoUserPoolId)
DB_ENDPOINT=$(get_stack_output event-manager DatabaseEndpoint)

# Valores por defecto si no se encuentran
API_URL=${API_URL:-"No disponible"}
USER_POOL_ID=${USER_POOL_ID:-"No disponible"}
DB_ENDPOINT=${DB_ENDPOINT:-"No disponible"}

log_info "API Gateway URL: $API_URL"
log_info "Cognito User Pool ID: $USER_POOL_ID"
log_info "Database Endpoint: $DB_ENDPOINT"

show_header "PRÓXIMOS PASOS" $YELLOW
log_info "1. Configura usuarios en Cognito User Pool"
log_info "2. Prueba los endpoints del API Gateway"
log_info "3. Revisa los logs en CloudWatch"
log_info "4. Configura el frontend para usar estos endpoints"

show_header "COMANDOS ÚTILES" $YELLOW
echo "# Ver logs de una función Lambda:"
echo "aws logs filter-log-events --log-group-name /aws/lambda/event-manager-CreateEventLambda --start-time \$(date -d '1 hour ago' +%s)000"
echo ""
echo "# Ver credenciales de la base de datos:"
echo "aws secretsmanager get-secret-value --secret-id event-app/db-credentials --query SecretString --output text | jq ."
echo ""
echo "# Eliminar todo (CUIDADO - esto borra todos los datos):"
echo "./cleanup.sh"

log_success "¡Despliegue completado exitosamente en $(date)!"
