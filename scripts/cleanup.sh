#!/bin/bash

# 🗑️ Script de Limpieza - Event Manager AWS
# Este script elimina todos los recursos creados por el despliegue

set -e  # Salir si cualquier comando falla

# Cargar utilidades comunes
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

show_banner "⚠️ ADVERTENCIA ⚠️" "Este script eliminará TODOS los recursos del Event Manager\nincluyendo bases de datos, buckets S3 y todos los datos.\n\n¡ESTA ACCIÓN NO SE PUEDE DESHACER!" $RED

check_aws_credentials || exit 1

# Listar stacks existentes
log_info "Buscando stacks relacionados con event-manager..."
EXISTING_STACKS=$(aws cloudformation list-stacks \
    --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE CREATE_FAILED UPDATE_FAILED ROLLBACK_COMPLETE \
    --query 'StackSummaries[?contains(StackName, `event-manager`)].{Name:StackName,Status:StackStatus}' \
    --output table)

if [[ -z "$EXISTING_STACKS" || "$EXISTING_STACKS" == *"None"* ]]; then
    log_warning "No se encontraron stacks de event-manager para eliminar."
    exit 0
fi

echo -e "\n${YELLOW}=== STACKS ENCONTRADOS ===${NC}"
echo "$EXISTING_STACKS"

# Confirmación del usuario
echo -e "\n${RED}¿Estás ABSOLUTAMENTE SEGURO de que quieres eliminar todos estos recursos?${NC}"
echo -e "${YELLOW}Escribe 'DELETE' (en mayúsculas) para confirmar:${NC}"
read -r confirmation

if [[ "$confirmation" != "DELETE" ]]; then
    log_info "Operación cancelada por el usuario."
    exit 0
fi

echo -e "\n${YELLOW}Segunda confirmación requerida.${NC}"
echo -e "${RED}¿Confirmas que quieres ELIMINAR PERMANENTEMENTE todos los datos? (yes/no):${NC}"
read -r final_confirmation

if [[ "$final_confirmation" != "yes" ]]; then
    log_info "Operación cancelada por el usuario."
    exit 0
fi

log_warning "Iniciando proceso de eliminación..."

# Función para esperar a que un stack se elimine
wait_for_stack_deletion() {
    local stack_name=$1
    log_info "Esperando a que se elimine el stack: $stack_name"
    
    while true; do
        local status=$(aws cloudformation describe-stacks \
            --stack-name "$stack_name" \
            --query 'Stacks[0].StackStatus' \
            --output text 2>/dev/null || echo "DELETE_COMPLETE")
        
        if [[ "$status" == "DELETE_COMPLETE" ]]; then
            log_success "Stack $stack_name eliminado correctamente"
            break
        elif [[ "$status" == "DELETE_FAILED" ]]; then
            log_error "Error al eliminar el stack $stack_name"
            aws cloudformation describe-stack-events \
                --stack-name "$stack_name" \
                --query 'StackEvents[?ResourceStatus==`DELETE_FAILED`]' \
                --output table
            break
        else
            log_info "Estado actual del stack $stack_name: $status"
            sleep 30
        fi
    done
}

# Paso 1: Eliminar stack principal (event-manager)
log_info "Eliminando stack principal: event-manager"
if aws cloudformation describe-stacks --stack-name event-manager > /dev/null 2>&1; then
    log_warning "Eliminando stack event-manager (esto puede tomar 10-15 minutos)..."
    aws cloudformation delete-stack --stack-name event-manager
    wait_for_stack_deletion event-manager
else
    log_info "Stack event-manager no existe o ya fue eliminado"
fi

# Paso 2: Vaciar buckets S3 antes de eliminar el stack S3
log_info "Verificando buckets S3 para vaciar..."
if aws cloudformation describe-stacks --stack-name event-manager-s3 > /dev/null 2>&1; then
    # Obtener nombres de buckets
    LAMBDA_BUCKET=$(aws cloudformation describe-stacks \
        --stack-name event-manager-s3 \
        --query 'Stacks[0].Outputs[?OutputKey==`LambdaCodeBucketName`].OutputValue' \
        --output text 2>/dev/null || echo "")
    
    REPORTS_BUCKET=$(aws cloudformation describe-stacks \
        --stack-name event-manager-s3 \
        --query 'Stacks[0].Outputs[?OutputKey==`ReportsBucketName`].OutputValue' \
        --output text 2>/dev/null || echo "")
    
    # Vaciar bucket de código Lambda
    if [[ -n "$LAMBDA_BUCKET" && "$LAMBDA_BUCKET" != "None" ]]; then
        log_info "Vaciando bucket Lambda: $LAMBDA_BUCKET"
        aws s3 rm s3://$LAMBDA_BUCKET --recursive || log_warning "No se pudo vaciar el bucket Lambda"
    fi
    
    # Vaciar bucket de reportes
    if [[ -n "$REPORTS_BUCKET" && "$REPORTS_BUCKET" != "None" ]]; then
        log_info "Vaciando bucket de reportes: $REPORTS_BUCKET"
        aws s3 rm s3://$REPORTS_BUCKET --recursive || log_warning "No se pudo vaciar el bucket de reportes"
    fi
fi

# Paso 3: Eliminar stack S3 (event-manager-s3)
log_info "Eliminando stack S3: event-manager-s3"
if aws cloudformation describe-stacks --stack-name event-manager-s3 > /dev/null 2>&1; then
    log_warning "Eliminando stack event-manager-s3..."
    aws cloudformation delete-stack --stack-name event-manager-s3
    wait_for_stack_deletion event-manager-s3
else
    log_info "Stack event-manager-s3 no existe o ya fue eliminado"
fi

# Paso 4: Verificar que todos los stacks fueron eliminados
log_info "Verificando que todos los stacks fueron eliminados..."
REMAINING_STACKS=$(aws cloudformation list-stacks \
    --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE CREATE_FAILED UPDATE_FAILED ROLLBACK_COMPLETE \
    --query 'StackSummaries[?contains(StackName, `event-manager`)].StackName' \
    --output text)

if [[ -n "$REMAINING_STACKS" && "$REMAINING_STACKS" != "None" ]]; then
    log_warning "Algunos stacks aún existen: $REMAINING_STACKS"
    log_info "Esto puede ser normal si están en proceso de eliminación."
else
    log_success "Todos los stacks de event-manager han sido eliminados"
fi

# Paso 5: Limpiar archivos locales temporales
log_info "Limpiando archivos temporales locales..."
rm -f lambda-functions.zip response.json

# Paso 6: Verificar recursos huérfanos (opcional)
log_info "Verificando posibles recursos huérfanos..."

# Verificar funciones Lambda huérfanas
ORPHAN_LAMBDAS=$(aws lambda list-functions \
    --query 'Functions[?contains(FunctionName, `event-manager`)].FunctionName' \
    --output text 2>/dev/null || echo "")

if [[ -n "$ORPHAN_LAMBDAS" && "$ORPHAN_LAMBDAS" != "None" ]]; then
    log_warning "Se encontraron funciones Lambda huérfanas: $ORPHAN_LAMBDAS"
    log_info "Puedes eliminarlas manualmente si es necesario."
fi

# Verificar buckets S3 huérfanos
ORPHAN_BUCKETS=$(aws s3api list-buckets \
    --query 'Buckets[?contains(Name, `event-manager`)].Name' \
    --output text 2>/dev/null || echo "")

if [[ -n "$ORPHAN_BUCKETS" && "$ORPHAN_BUCKETS" != "None" ]]; then
    log_warning "Se encontraron buckets S3 huérfanos: $ORPHAN_BUCKETS"
    log_info "Puedes eliminarlos manualmente si es necesario."
fi

# RESUMEN FINAL
echo -e "\n${GREEN}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                   ¡LIMPIEZA COMPLETADA!                     ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

log_success "Todos los recursos del Event Manager AWS han sido eliminados"
log_info "Fecha de eliminación: $(date)"

echo -e "\n${YELLOW}=== RESUMEN DE ELIMINACIÓN ===${NC}"
log_info "✅ Stack event-manager eliminado"
log_info "✅ Stack event-manager-s3 eliminado"
log_info "✅ Buckets S3 vaciados"
log_info "✅ Archivos temporales eliminados"

if [[ -n "$ORPHAN_LAMBDAS" && "$ORPHAN_LAMBDAS" != "None" ]] || [[ -n "$ORPHAN_BUCKETS" && "$ORPHAN_BUCKETS" != "None" ]]; then
    echo -e "\n${YELLOW}=== RECURSOS QUE REQUIEREN ATENCIÓN MANUAL ===${NC}"
    [[ -n "$ORPHAN_LAMBDAS" && "$ORPHAN_LAMBDAS" != "None" ]] && log_warning "Funciones Lambda: $ORPHAN_LAMBDAS"
    [[ -n "$ORPHAN_BUCKETS" && "$ORPHAN_BUCKETS" != "None" ]] && log_warning "Buckets S3: $ORPHAN_BUCKETS"
fi

echo -e "\n${BLUE}Para volver a desplegar el sistema, ejecuta:${NC}"
echo "./deploy.sh"

log_success "¡Limpieza completada exitosamente!"
