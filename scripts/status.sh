#!/bin/bash

# 📊 Script de Estado - Event Manager AWS
# Este script muestra el estado actual de todos los recursos desplegados

set -e  # Salir si cualquier comando falla

# Cargar utilidades comunes
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

show_banner "EVENT MANAGER AWS STATUS" "Estado Actual del Sistema" $BLUE

# Verificar credenciales AWS
check_aws_credentials || exit 1

# Función para mostrar estado de un stack
show_stack_status() {
    local stack_name=$1
    local display_name=$2
    
    log_info "Verificando stack: $display_name"
    
    local status=$(aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --query 'Stacks[0].StackStatus' \
        --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "$status" == "NOT_FOUND" ]]; then
        echo "  ❌ Stack no encontrado: $stack_name"
    elif [[ "$status" == "CREATE_COMPLETE" || "$status" == "UPDATE_COMPLETE" ]]; then
        echo "  ✅ Stack activo: $stack_name ($status)"
    elif [[ "$status" == *"FAILED"* ]]; then
        echo "  ❌ Stack con errores: $stack_name ($status)"
    elif [[ "$status" == *"IN_PROGRESS"* ]]; then
        echo "  🔄 Stack en progreso: $stack_name ($status)"
    else
        echo "  ⚠️  Stack en estado: $stack_name ($status)"
    fi
}

# Verificar stacks principales
show_header "STACKS DE CLOUDFORMATION" $YELLOW

show_stack_status "event-manager" "Stack Principal"
show_stack_status "event-manager-s3" "Buckets S3"

# Mostrar todos los stacks relacionados
echo ""
log_info "Todos los stacks relacionados con event-manager:"
list_event_manager_stacks "CREATE_COMPLETE UPDATE_COMPLETE CREATE_FAILED UPDATE_FAILED CREATE_IN_PROGRESS UPDATE_IN_PROGRESS"

# Verificar funciones Lambda
show_header "FUNCIONES LAMBDA" $YELLOW

LAMBDA_FUNCTIONS=$(aws lambda list-functions \
    --query 'Functions[?contains(FunctionName, `event-manager`)].FunctionName' \
    --output text 2>/dev/null || echo "")

if [[ -n "$LAMBDA_FUNCTIONS" && "$LAMBDA_FUNCTIONS" != "None" ]]; then
    log_success "Funciones Lambda encontradas:"
    aws lambda list-functions \
        --query 'Functions[?contains(FunctionName, `event-manager`)].{Name:FunctionName,Runtime:Runtime,State:State,LastModified:LastModified}' \
        --output table
else
    log_warning "No se encontraron funciones Lambda de event-manager"
fi

# Verificar buckets S3
show_header "BUCKETS S3" $YELLOW

S3_BUCKETS=$(aws s3api list-buckets \
    --query 'Buckets[?contains(Name, `event-manager`)].Name' \
    --output text 2>/dev/null || echo "")

if [[ -n "$S3_BUCKETS" && "$S3_BUCKETS" != "None" ]]; then
    log_success "Buckets S3 encontrados:"
    for bucket in $S3_BUCKETS; do
        local size=$(aws s3 ls s3://$bucket --recursive --summarize 2>/dev/null | grep "Total Size" | awk '{print $3 " " $4}' || echo "0 Bytes")
        echo "  📦 $bucket ($size)"
    done
else
    log_warning "No se encontraron buckets S3 de event-manager"
fi

# Verificar base de datos RDS
show_header "BASE DE DATOS RDS" $YELLOW

RDS_CLUSTERS=$(aws rds describe-db-clusters \
    --query 'DBClusters[?contains(DBClusterIdentifier, `event-manager`)].{Name:DBClusterIdentifier,Status:Status,Engine:Engine,EngineVersion:EngineVersion}' \
    --output table 2>/dev/null || echo "")

if [[ -n "$RDS_CLUSTERS" && "$RDS_CLUSTERS" != *"None"* ]]; then
    log_success "Clusters RDS encontrados:"
    echo "$RDS_CLUSTERS"
else
    log_warning "No se encontraron clusters RDS de event-manager"
fi

# Verificar API Gateway
show_header "API GATEWAY" $YELLOW

API_GATEWAYS=$(aws apigateway get-rest-apis \
    --query 'items[?contains(name, `event-manager`)].{Name:name,Id:id,CreatedDate:createdDate}' \
    --output table 2>/dev/null || echo "")

if [[ -n "$API_GATEWAYS" && "$API_GATEWAYS" != *"None"* ]]; then
    log_success "APIs Gateway encontradas:"
    echo "$API_GATEWAYS"
else
    log_warning "No se encontraron APIs Gateway de event-manager"
fi

# Verificar Cognito User Pools
show_header "COGNITO USER POOLS" $YELLOW

USER_POOLS=$(aws cognito-idp list-user-pools --max-items 50 \
    --query 'UserPools[?contains(Name, `event-manager`)].{Name:Name,Id:Id,CreationDate:CreationDate}' \
    --output table 2>/dev/null || echo "")

if [[ -n "$USER_POOLS" && "$USER_POOLS" != *"None"* ]]; then
    log_success "User Pools encontrados:"
    echo "$USER_POOLS"
else
    log_warning "No se encontraron User Pools de event-manager"
fi

# Mostrar outputs importantes si el stack principal existe
if aws cloudformation describe-stacks --stack-name event-manager > /dev/null 2>&1; then
    show_header "INFORMACIÓN IMPORTANTE" $YELLOW
    
    API_URL=$(get_stack_output event-manager ApiGatewayUrl)
    USER_POOL_ID=$(get_stack_output event-manager CognitoUserPoolId)
    DB_ENDPOINT=$(get_stack_output event-manager DatabaseEndpoint)
    
    log_info "API Gateway URL: ${API_URL:-'No disponible'}"
    log_info "Cognito User Pool ID: ${USER_POOL_ID:-'No disponible'}"
    log_info "Database Endpoint: ${DB_ENDPOINT:-'No disponible'}"
    
    # Mostrar todos los outputs
    echo ""
    log_info "Todos los outputs del stack principal:"
    aws cloudformation describe-stacks \
        --stack-name event-manager \
        --query 'Stacks[0].Outputs' \
        --output table
fi

# Verificar colas SQS
show_header "COLAS SQS" $YELLOW

SQS_QUEUES=$(aws sqs list-queues \
    --query 'QueueUrls[?contains(@, `event-manager`)]' \
    --output text 2>/dev/null || echo "")

if [[ -n "$SQS_QUEUES" && "$SQS_QUEUES" != "None" ]]; then
    log_success "Colas SQS encontradas:"
    for queue in $SQS_QUEUES; do
        local queue_name=$(basename "$queue")
        echo "  📬 $queue_name"
    done
else
    log_warning "No se encontraron colas SQS de event-manager"
fi

# Verificar Step Functions
show_header "STEP FUNCTIONS" $YELLOW

STEP_FUNCTIONS=$(aws stepfunctions list-state-machines \
    --query 'stateMachines[?contains(name, `event-manager`)].{Name:name,Status:status,CreationDate:creationDate}' \
    --output table 2>/dev/null || echo "")

if [[ -n "$STEP_FUNCTIONS" && "$STEP_FUNCTIONS" != *"None"* ]]; then
    log_success "State Machines encontradas:"
    echo "$STEP_FUNCTIONS"
else
    log_warning "No se encontraron State Machines de event-manager"
fi

# Resumen final
show_header "RESUMEN" $GREEN

# Contar recursos
STACK_COUNT=$(aws cloudformation list-stacks \
    --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
    --query 'length(StackSummaries[?contains(StackName, `event-manager`)])' \
    --output text 2>/dev/null || echo "0")

LAMBDA_COUNT=$(aws lambda list-functions \
    --query 'length(Functions[?contains(FunctionName, `event-manager`)])' \
    --output text 2>/dev/null || echo "0")

S3_COUNT=$(aws s3api list-buckets \
    --query 'length(Buckets[?contains(Name, `event-manager`)])' \
    --output text 2>/dev/null || echo "0")

log_info "📊 Recursos encontrados:"
log_info "  - Stacks CloudFormation: $STACK_COUNT"
log_info "  - Funciones Lambda: $LAMBDA_COUNT"
log_info "  - Buckets S3: $S3_COUNT"

if [[ "$STACK_COUNT" -gt 0 ]]; then
    log_success "✅ El sistema Event Manager está desplegado"
    
    echo ""
    show_header "COMANDOS ÚTILES" $CYAN
    echo "# Ver logs de una función Lambda:"
    echo "aws logs filter-log-events --log-group-name /aws/lambda/event-manager-CreateEventLambda --start-time \$(date -d '1 hour ago' +%s)000"
    echo ""
    echo "# Actualizar el sistema:"
    echo "./deploy.sh"
    echo ""
    echo "# Eliminar todo el sistema:"
    echo "./cleanup.sh"
else
    log_warning "⚠️  El sistema Event Manager no está desplegado"
    
    echo ""
    show_header "PRÓXIMOS PASOS" $CYAN
    echo "# Para desplegar el sistema:"
    echo "./deploy.sh"
fi

log_success "Estado verificado en $(date)"
