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

# PASO 2: Instalar dependencias y empaquetar funciones Lambda
show_progress 2 10 "Instalando Dependencias y Empaquetando Funciones Lambda"

log_info "Instalando dependencias de Node.js..."
cd src/
if [[ ! -f "package.json" ]]; then
    log_error "No se encontró package.json en el directorio src/"
    exit 1
fi

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

# PASO 3: Crear bucket S3 para código Lambda
show_progress 3 10 "Creando Bucket S3 para Código Lambda"

# Verificar si los buckets ya existen
LAMBDA_BUCKET_NAME="event-manager-lambda-code-$ENVIRONMENT-$(aws sts get-caller-identity --query Account --output text)"
REPORTS_BUCKET_NAME="event-manager-reports-$ENVIRONMENT-$(aws sts get-caller-identity --query Account --output text)"

log_info "Verificando si los buckets S3 ya existen..."
if aws s3api head-bucket --bucket "$LAMBDA_BUCKET_NAME" 2>/dev/null; then
    log_warning "Bucket Lambda ya existe: $LAMBDA_BUCKET_NAME"
    USE_EXISTING_BUCKETS="true"
else
    log_info "Bucket Lambda no existe, se creará: $LAMBDA_BUCKET_NAME"
    USE_EXISTING_BUCKETS="false"
fi

log_info "Desplegando template S3..."
if [[ "$USE_EXISTING_BUCKETS" == "true" ]]; then
    log_info "Usando buckets existentes..."
    aws cloudformation deploy \
        --template-file infra/templates/s3.yml \
        --stack-name event-manager-s3 \
        --capabilities CAPABILITY_IAM \
        --parameter-overrides \
            Environment=$ENVIRONMENT \
            CreateS3Buckets=false \
            ExistingLambdaCodeBucket=$LAMBDA_BUCKET_NAME \
            ExistingReportsBucket=$REPORTS_BUCKET_NAME
else
    log_info "Creando nuevos buckets..."
    aws cloudformation deploy \
        --template-file infra/templates/s3.yml \
        --stack-name event-manager-s3 \
        --capabilities CAPABILITY_IAM \
        --parameter-overrides Environment=$ENVIRONMENT
fi

log_success "Stack event-manager-s3 desplegado correctamente"

# PASO 4: Obtener nombre del bucket creado
show_progress 4 10 "Obteniendo Información del Bucket S3"

log_info "Obteniendo nombre del bucket Lambda..."
LAMBDA_BUCKET=$(get_stack_output event-manager-s3 LambdaCodeBucketName)

if [[ -z "$LAMBDA_BUCKET" ]]; then
    log_warning "No se pudo obtener el nombre del bucket desde el stack, usando el nombre determinado anteriormente"
    LAMBDA_BUCKET=$LAMBDA_BUCKET_NAME
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

# PASO 8: Creando Base de Datos RDS
show_progress 8 10 "Creando Base de Datos MySQL"

# Función para mostrar progreso mientras espera RDS
show_rds_wait_progress() {
    local db_id=$1
    local dots=""
    local count=0
    
    while true; do
        # Verificar estado de la base de datos
        local status=$(aws rds describe-db-instances --db-instance-identifier "$db_id" --query 'DBInstances[0].DBInstanceStatus' --output text 2>/dev/null || echo "unknown")
        
        if [[ "$status" == "available" ]]; then
            echo -e "\n${GREEN}✅ Base de datos disponible${NC}"
            break
        elif [[ "$status" == "failed" || "$status" == "unknown" ]]; then
            echo -e "\n${RED}❌ Error en la creación de la base de datos. Estado: $status${NC}"
            exit 1
        fi
        
        # Mostrar progreso visual
        dots+="."
        if [[ ${#dots} -gt 3 ]]; then
            dots=""
        fi
        
        printf "\r${BLUE}⏳ Esperando que RDS esté disponible$dots (Estado: $status)${NC}"
        sleep 10
        ((count++))
        
        # Mostrar mensaje cada minuto
        if [[ $((count % 6)) -eq 0 ]]; then
            echo -e "\n${YELLOW}⏰ Tiempo transcurrido: $((count / 6)) minuto(s)${NC}"
        fi
    done
}

log_info "Verificando si la base de datos ya existe..."
if aws rds describe-db-instances --db-instance-identifier event-manager-db-$ENVIRONMENT >/dev/null 2>&1; then
    log_warning "Base de datos ya existe: event-manager-db-$ENVIRONMENT"
    DB_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier event-manager-db-$ENVIRONMENT --query 'DBInstances[0].Endpoint.Address' --output text)
    log_success "Usando base de datos existente: $DB_ENDPOINT"
else
    log_info "Creando security group para RDS..."
    if ! aws ec2 describe-security-groups --group-names event-manager-rds-sg >/dev/null 2>&1; then
        SG_ID=$(aws ec2 create-security-group \
            --group-name event-manager-rds-sg \
            --description "Security group for Event Manager RDS MySQL" \
            --query 'GroupId' --output text)
        
        log_info "Agregando regla de acceso MySQL al security group..."
        aws ec2 authorize-security-group-ingress \
            --group-id $SG_ID \
            --protocol tcp \
            --port 3306 \
            --cidr 0.0.0.0/0
    else
        SG_ID=$(aws ec2 describe-security-groups --group-names event-manager-rds-sg --query 'SecurityGroups[0].GroupId' --output text)
    fi

    log_info "Creando instancia RDS MySQL..."
    RDS_CREATE_RESULT=$(aws rds create-db-instance \
        --db-instance-identifier event-manager-db-$ENVIRONMENT \
        --db-instance-class db.t3.micro \
        --engine mysql \
        --engine-version 8.0.43 \
        --master-username $DB_USERNAME \
        --master-user-password EventManager123! \
        --allocated-storage 20 \
        --db-name EventManagerDB \
        --vpc-security-group-ids $SG_ID \
        --publicly-accessible \
        --no-multi-az \
        --storage-type gp2 \
        --backup-retention-period 0 \
        --tags Key=Name,Value=event-manager-db-$ENVIRONMENT Key=Environment,Value=$ENVIRONMENT 2>/dev/null)
    
    if [[ $? -eq 0 ]]; then
        log_success "✅ Solicitud de creación de RDS enviada exitosamente"
    else
        log_error "❌ Error al crear la instancia RDS"
        exit 1
    fi

    log_info "Esperando que la base de datos esté disponible (esto puede tomar 5-10 minutos)..."
    show_rds_wait_progress "event-manager-db-$ENVIRONMENT"
    
    DB_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier event-manager-db-$ENVIRONMENT --query 'DBInstances[0].Endpoint.Address' --output text)
    log_success "Base de datos creada exitosamente: $DB_ENDPOINT"
fi

log_info "Creando secret en Secrets Manager para credenciales de la base de datos..."
SECRET_NAME="event-app/db-credentials-$ENVIRONMENT-$AWS_ACCOUNT_ID"

# Verificar si el secret ya existe
if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" >/dev/null 2>&1; then
    log_warning "Secret ya existe, actualizando credenciales..."
    aws secretsmanager update-secret \
        --secret-id "$SECRET_NAME" \
        --secret-string "{\"username\":\"$DB_USERNAME\",\"password\":\"EventManager123!\"}"
else
    log_info "Creando nuevo secret con credenciales de la base de datos..."
    aws secretsmanager create-secret \
        --name "$SECRET_NAME" \
        --description "Credenciales para base de datos Event Manager" \
        --secret-string "{\"username\":\"$DB_USERNAME\",\"password\":\"EventManager123!\"}" \
        --tags Key=Environment,Value=$ENVIRONMENT Key=Name,Value=event-manager-db-secret
fi

SECRET_ARN=$(aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --query 'ARN' --output text)
log_success "Secret creado/actualizado exitosamente: $SECRET_ARN"

# Validar que tenemos los valores necesarios antes de continuar
if [[ -z "$DB_ENDPOINT" ]] || [[ -z "$SECRET_ARN" ]]; then
    log_error "❌ Error: No se pudieron obtener DB_ENDPOINT o SECRET_ARN"
    log_error "DB_ENDPOINT: ${DB_ENDPOINT:-'VACÍO'}"
    log_error "SECRET_ARN: ${SECRET_ARN:-'VACÍO'}"
    exit 1
fi

log_success "✅ Valores RDS validados:"
log_info "  DB Endpoint: $DB_ENDPOINT"
log_info "  Secret ARN: $SECRET_ARN"

# PASO 8.5: Desplegando InitDB Stack para crear tablas
show_progress "8.5" 11 "Creando InitDB Lambda Function"

log_info "Desplegando InitDB stack para crear las tablas..."
aws cloudformation deploy \
    --template-file infra/templates/initdb.yml \
    --stack-name event-manager-initdb \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides \
        RDSSecretArn=$SECRET_ARN \
        RDSClusterEndpoint=$DB_ENDPOINT \
        LambdaCodeBucket=$LAMBDA_BUCKET \
        LambdaCodeKey=lambda-functions.zip \
        Environment=$ENVIRONMENT

log_success "InitDB stack desplegado correctamente"

# PASO 8.6: Ejecutar InitDB Lambda para crear tablas
show_progress "8.6" 11 "Inicializando Base de Datos"

# Obtener el nombre de la función desde el stack
INIT_LAMBDA_NAME=$(aws cloudformation describe-stacks \
    --stack-name event-manager-initdb \
    --query 'Stacks[0].Outputs[?OutputKey==`InitDBLambdaName`].OutputValue' \
    --output text)

log_info "Ejecutando función InitDB para crear las tablas..."
log_info "Nombre de función: $INIT_LAMBDA_NAME"

INIT_RESPONSE=$(aws lambda invoke \
    --function-name "$INIT_LAMBDA_NAME" \
    --log-type Tail \
    --payload '{}' \
    /tmp/init-db-response.json 2>/dev/null || echo "FAILED")

if [[ "$INIT_RESPONSE" == "FAILED" ]]; then
    log_error "Error al ejecutar la función InitDB"
    # Mostrar logs para debugging
    log_info "Verificando si la función existe..."
    aws lambda get-function --function-name "$INIT_LAMBDA_NAME" || {
        log_error "La función no existe. Verificando el stack InitDB..."
        aws cloudformation describe-stacks --stack-name event-manager-initdb
    }
    exit 1
fi

# Verificar respuesta
if [[ -f "/tmp/init-db-response.json" ]]; then
    INIT_RESULT=$(cat /tmp/init-db-response.json)
    echo "$INIT_RESULT" | grep -q '"statusCode":200' && {
        log_success "✅ Base de datos inicializada correctamente - tablas creadas"
    } || {
        log_error "❌ Error al inicializar la base de datos:"
        echo "$INIT_RESULT" | jq . || echo "$INIT_RESULT"
        exit 1
    }
else
    log_error "No se pudo obtener respuesta de la función InitDB"
    exit 1
fi

# PASO 9: Desplegando stack principal
show_progress 9 11 "Desplegando Infraestructura Principal"

log_warning "Este paso puede tomar 15-20 minutos. Por favor, sé paciente..."
log_info "Desplegando stack principal con todos los servicios..."
log_info "Usando endpoint de base de datos: $DB_ENDPOINT"

aws cloudformation deploy \
    --template-file infra/master-template.yml \
    --stack-name event-manager \
    --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
    --parameter-overrides \
        Environment=$ENVIRONMENT \
        DBUsername=$DB_USERNAME \
        S3LambdaBucket=$LAMBDA_BUCKET_NAME \
        LambdaCodeKey=lambda-functions.zip \
        CreateS3Buckets=false \
        ExistingLambdaCodeBucket=$LAMBDA_BUCKET_NAME \
        ExistingReportsBucket=$REPORTS_BUCKET_NAME \
        CreateSESResources=false \
        ExistingSESConfigurationSet=event-manager-config-set-$ENVIRONMENT \
        DBEndpoint=$DB_ENDPOINT \
        RDSSecretArn=$SECRET_ARN

# PASO 10: Verificar el despliegue
show_progress 10 11 "Verificando el Despliegue"

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

# PASO 11: Verificar funciones Lambda
show_progress 11 11 "Verificando Funciones Lambda"

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
# Valores por defecto si no se encuentran
API_URL=${API_URL:-"No disponible"}
USER_POOL_ID=${USER_POOL_ID:-"No disponible"}
DB_ENDPOINT=${DB_ENDPOINT:-"No disponible"}

# Obtener Client ID de Cognito
log_info "Obteniendo Client ID de Cognito..."
CLIENT_ID=$(aws cognito-idp list-user-pool-clients --user-pool-id "$USER_POOL_ID" --query 'UserPoolClients[0].ClientId' --output text 2>/dev/null || echo "No disponible")

echo -e "\n${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    🚀 INFORMACIÓN DEL DESPLIEGUE                ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
log_success "🌐 API Gateway URL: $API_URL"
log_success "🔑 Cognito User Pool ID: $USER_POOL_ID"
log_success "🔑 Cognito Client ID: $CLIENT_ID"
log_success "🗄️ Database Endpoint: ${DB_ENDPOINT:-"No disponible"}"
echo ""

log_success "¡Despliegue completado exitosamente en $(date)!"
