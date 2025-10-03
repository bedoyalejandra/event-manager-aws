#!/bin/bash

# 📦 Script para Subir Código Lambda - Event Manager AWS
# Este script empaqueta y sube únicamente el código de las funciones Lambda

set -e  # Salir si cualquier comando falla

# Cargar utilidades comunes
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Configuración por defecto
ENVIRONMENT=${ENVIRONMENT:-dev}
AWS_REGION=${AWS_REGION:-us-west-2}

show_banner "UPLOAD LAMBDA CODE" "Event Manager AWS"

log_info "Configuración:"
log_info "  - Environment: $ENVIRONMENT"
log_info "  - AWS Region: $AWS_REGION"

# Verificaciones previas
log_info "Verificando credenciales AWS..."
check_aws_credentials || exit 1

log_info "Verificando estructura del proyecto..."
check_project_structure || exit 1

# PASO 1: Instalar dependencias y empaquetar funciones Lambda
show_progress 1 4 "Instalando Dependencias y Empaquetando Funciones Lambda"

log_info "Navegando al directorio src/..."
cd src/

if [[ ! -f "package.json" ]]; then
    log_error "No se encontró package.json en el directorio src/"
    exit 1
fi

log_info "Instalando dependencias de Node.js..."
npm install
log_success "Dependencias instaladas correctamente"

log_info "Creando archivo ZIP con funciones Lambda..."
if [[ -f "lambda-functions.zip" ]]; then
    log_warning "Eliminando lambda-functions.zip existente..."
    rm lambda-functions.zip
fi

zip -r lambda-functions.zip . -x "*.zip" "package-lock.json" > /dev/null
LAMBDA_ZIP_SIZE=$(ls -lh lambda-functions.zip | awk '{print $5}')
log_success "Archivo lambda-functions.zip creado (Tamaño: $LAMBDA_ZIP_SIZE)"

# Verificar que las dependencias están incluidas en el ZIP
log_info "Verificando que las dependencias están incluidas..."
if unzip -l lambda-functions.zip | grep -q "node_modules/mysql2"; then
    log_success "✅ Dependencias mysql2 incluidas en el ZIP"
else
    log_error "❌ Dependencias mysql2 NO encontradas en el ZIP"
    exit 1
fi

# Mover el archivo ZIP al directorio raíz del proyecto
mv lambda-functions.zip ../
cd ..

log_info "Limpiando node_modules temporales..."
rm -rf src/node_modules
log_success "Limpieza completada"

# PASO 2: Obtener información del bucket S3
show_progress 2 4 "Obteniendo Información del Bucket S3"

# Intentar obtener el nombre del bucket desde el stack
log_info "Buscando bucket S3 desde el stack event-manager-s3..."
LAMBDA_BUCKET=$(get_stack_output event-manager-s3 LambdaCodeBucketName 2>/dev/null || echo "")

# Si no se encuentra el stack, construir el nombre del bucket
if [[ -z "$LAMBDA_BUCKET" ]]; then
    log_warning "No se pudo obtener el bucket desde el stack, construyendo nombre..."
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    LAMBDA_BUCKET="event-manager-lambda-code-$ENVIRONMENT-$ACCOUNT_ID"
    log_info "Bucket construido: $LAMBDA_BUCKET"
fi

# Verificar que el bucket existe
log_info "Verificando que el bucket existe..."
if ! aws s3api head-bucket --bucket "$LAMBDA_BUCKET" 2>/dev/null; then
    log_error "El bucket S3 no existe: $LAMBDA_BUCKET"
    log_error "Por favor, ejecuta el script de despliegue completo primero o crea el bucket manualmente"
    exit 1
fi

log_success "Bucket encontrado: $LAMBDA_BUCKET"

# PASO 3: Subir código Lambda al bucket
show_progress 3 4 "Subiendo Código Lambda al Bucket"

log_info "Subiendo lambda-functions.zip al bucket S3..."
aws s3 cp lambda-functions.zip s3://$LAMBDA_BUCKET/lambda-functions.zip

log_info "Verificando que el archivo se subió correctamente..."
FILE_INFO=$(aws s3 ls s3://$LAMBDA_BUCKET/lambda-functions.zip)
log_success "Archivo verificado en S3:"
echo "  $FILE_INFO"

# Obtener URL del objeto
OBJECT_URL="s3://$LAMBDA_BUCKET/lambda-functions.zip"
log_success "URL del objeto: $OBJECT_URL"

# Limpiar archivo ZIP local
log_info "Limpiando archivo ZIP local..."
rm lambda-functions.zip
log_success "Limpieza completada"

# PASO 4: Verificar y actualizar parámetros del stack si es necesario
show_progress 4 5 "Verificando Parámetros del Stack"

log_info "Verificando parámetros RDS en el stack principal..."
CURRENT_DB_ENDPOINT=$(aws cloudformation describe-stacks --stack-name event-manager --query 'Stacks[0].Parameters[?ParameterKey==`DBEndpoint`].ParameterValue' --output text 2>/dev/null || echo "")
CURRENT_SECRET_ARN=$(aws cloudformation describe-stacks --stack-name event-manager --query 'Stacks[0].Parameters[?ParameterKey==`RDSSecretArn`].ParameterValue' --output text 2>/dev/null || echo "")

# Si los parámetros están vacíos, obtener los valores reales y actualizar el stack
if [[ -z "$CURRENT_DB_ENDPOINT" ]] || [[ -z "$CURRENT_SECRET_ARN" ]]; then
    log_warning "Parámetros RDS vacíos detectados. Actualizando stack..."
    
    # Obtener valores reales
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    DB_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier event-manager-db-$ENVIRONMENT --query 'DBInstances[0].Endpoint.Address' --output text 2>/dev/null || echo "")
    SECRET_ARN=$(aws secretsmanager describe-secret --secret-id "event-app/db-credentials-$ENVIRONMENT-$ACCOUNT_ID" --query 'ARN' --output text 2>/dev/null || echo "")
    
    if [[ -n "$DB_ENDPOINT" ]] && [[ -n "$SECRET_ARN" ]]; then
        log_info "Actualizando stack con parámetros RDS..."
        log_info "  DB Endpoint: $DB_ENDPOINT"
        log_info "  Secret ARN: $SECRET_ARN"
        
        aws cloudformation update-stack \
            --stack-name event-manager \
            --use-previous-template \
            --parameters \
                ParameterKey=S3LambdaBucket,UsePreviousValue=true \
                ParameterKey=CreateS3Buckets,UsePreviousValue=true \
                ParameterKey=ExistingLambdaCodeBucket,UsePreviousValue=true \
                ParameterKey=ExistingSESConfigurationSet,UsePreviousValue=true \
                ParameterKey=LambdaCodeKey,UsePreviousValue=true \
                ParameterKey=Environment,UsePreviousValue=true \
                ParameterKey=ExistingReportsBucket,UsePreviousValue=true \
                ParameterKey=DBUsername,UsePreviousValue=true \
                ParameterKey=CreateSESResources,UsePreviousValue=true \
                ParameterKey=DBEndpoint,ParameterValue=$DB_ENDPOINT \
                ParameterKey=RDSSecretArn,ParameterValue=$SECRET_ARN \
            --capabilities CAPABILITY_NAMED_IAM >/dev/null 2>&1
        
        log_info "Esperando que el stack se actualice..."
        aws cloudformation wait stack-update-complete --stack-name event-manager
        log_success "✅ Stack actualizado con parámetros RDS"
    else
        log_warning "⚠️ No se pudieron obtener los valores RDS. Continuando sin actualizar..."
    fi
else
    log_success "✅ Parámetros RDS ya están configurados correctamente"
fi

# PASO 5: Actualizar todas las funciones Lambda
show_progress 5 5 "Actualizando Funciones Lambda"

# Lista de todas las funciones Lambda
LAMBDA_FUNCTIONS=(
    "CreateEventLambda-${ENVIRONMENT}"
    "DeleteEventLambda-${ENVIRONMENT}"
    "UpdateEventLambda-${ENVIRONMENT}"
    "DisableEventLambda-${ENVIRONMENT}"
    "GetActiveEventsLambda-${ENVIRONMENT}"
    "GenerateReportLambda-${ENVIRONMENT}"
    "GetReportLambda-${ENVIRONMENT}"
    "ProcessReportDataLambda-${ENVIRONMENT}"
    "SendEmailLambda-${ENVIRONMENT}"
    "SendEventReminderLambda-${ENVIRONMENT}"
    "PostEventAssistanceLambda-${ENVIRONMENT}"
    "InitDBLambda-${ENVIRONMENT}"
)

log_info "Actualizando ${#LAMBDA_FUNCTIONS[@]} funciones Lambda..."
echo ""

UPDATED_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0

for FUNCTION_NAME in "${LAMBDA_FUNCTIONS[@]}"; do
    # Verificar si la función existe
    if aws lambda get-function --function-name "$FUNCTION_NAME" >/dev/null 2>&1; then
        log_info "Actualizando función: $FUNCTION_NAME"
        
        if aws lambda update-function-code \
            --function-name "$FUNCTION_NAME" \
            --s3-bucket "$LAMBDA_BUCKET" \
            --s3-key lambda-functions.zip \
            --output json >/dev/null 2>&1; then
            
            log_success "  ✅ $FUNCTION_NAME actualizada"
            ((UPDATED_COUNT++))
        else
            log_error "  ❌ Error actualizando $FUNCTION_NAME"
            ((FAILED_COUNT++))
        fi
    else
        log_warning "  ⏭️  $FUNCTION_NAME no existe (omitida)"
        ((SKIPPED_COUNT++))
    fi
done

echo ""
log_info "Resumen de actualización:"
log_success "  ✅ Actualizadas: $UPDATED_COUNT"
if [[ $FAILED_COUNT -gt 0 ]]; then
    log_error "  ❌ Fallidas: $FAILED_COUNT"
fi
if [[ $SKIPPED_COUNT -gt 0 ]]; then
    log_warning "  ⏭️  Omitidas: $SKIPPED_COUNT"
fi

# Resumen final
echo ""
show_banner "UPLOAD COMPLETADO" "✅ Éxito"
echo ""
log_success "Código Lambda subido y funciones actualizadas"
log_info "Bucket: $LAMBDA_BUCKET"
log_info "Archivo: lambda-functions.zip"
log_info "Tamaño: $LAMBDA_ZIP_SIZE"
log_info "Funciones actualizadas: $UPDATED_COUNT de ${#LAMBDA_FUNCTIONS[@]}"
echo ""
if [[ $FAILED_COUNT -gt 0 ]]; then
    log_warning "Algunas funciones no se pudieron actualizar. Verifica los logs arriba."
    log_info "Puedes actualizar manualmente con:"
    echo "  aws lambda update-function-code --function-name <FUNCTION_NAME> --s3-bucket $LAMBDA_BUCKET --s3-key lambda-functions.zip"
    echo ""
fi
