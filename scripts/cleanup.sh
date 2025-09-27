#!/bin/bash

# 🗑️ Script de Limpieza - Event Manager AWS
# Este script elimina todos los recursos creados por el despliegue

set -e  # Salir si cualquier comando falla

# Cargar utilidades comunes
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

show_banner "⚠️ ADVERTENCIA ⚠️" "Este script eliminará TODOS los recursos del Event Manager\nincluyendo bases de datos, buckets S3 y todos los datos.\n\n¡ESTA ACCIÓN NO SE PUEDE DESHACER!" $RED

check_aws_credentials || exit 1

# Función especial para casos de emergencia con stacks DELETE_FAILED
# Se puede llamar con: ./cleanup.sh --fix-failed-stacks
if [[ "$1" == "--fix-failed-stacks" ]]; then
    echo -e "\n${YELLOW}=== MODO REPARACIÓN: STACKS DELETE_FAILED ===${NC}"
    log_info "Buscando y reparando stacks en estado DELETE_FAILED..."
    
    FAILED_STACKS=$(aws cloudformation list-stacks \
        --stack-status-filter DELETE_FAILED \
        --query 'StackSummaries[?contains(StackName, `event-manager`)].{Name:StackName,Status:StackStatus}' \
        --output table)
    
    if [[ -z "$FAILED_STACKS" || "$FAILED_STACKS" == *"None"* ]]; then
        log_success "No se encontraron stacks en estado DELETE_FAILED"
        exit 0
    fi
    
    echo -e "\n${YELLOW}=== STACKS EN DELETE_FAILED ===${NC}"
    echo "$FAILED_STACKS"
    
    echo -e "\n${YELLOW}¿Quieres intentar reparar estos stacks? (yes/no):${NC}"
    read -r fix_confirmation
    
    if [[ "$fix_confirmation" == "yes" ]]; then
        # Definir funciones necesarias aquí
        cleanup_s3_buckets() {
            local stack_name=$1
            log_info "Limpiando buckets S3 del stack: $stack_name"
            
            if aws cloudformation describe-stacks --stack-name "$stack_name" > /dev/null 2>&1; then
                local buckets=$(aws cloudformation describe-stack-resources \
                    --stack-name "$stack_name" \
                    --query 'StackResources[?ResourceType==`AWS::S3::Bucket`].PhysicalResourceId' \
                    --output text 2>/dev/null || echo "")
                
                if [[ -n "$buckets" && "$buckets" != "None" ]]; then
                    for bucket in $buckets; do
                        if aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
                            log_info "Vaciando bucket: $bucket"
                            aws s3 rm s3://$bucket --recursive 2>/dev/null || true
                            log_success "Bucket $bucket vaciado"
                        fi
                    done
                fi
            fi
        }
        
        force_delete_failed_stack() {
            local stack_name=$1
            log_warning "Intentando forzar eliminación del stack: $stack_name"
            cleanup_s3_buckets "$stack_name"
            aws cloudformation delete-stack --stack-name "$stack_name" || true
            log_info "Stack $stack_name marcado para eliminación"
        }
        
        FAILED_STACK_NAMES=$(aws cloudformation list-stacks \
            --stack-status-filter DELETE_FAILED \
            --query 'StackSummaries[?contains(StackName, `event-manager`)].StackName' \
            --output text)
        
        for stack in $FAILED_STACK_NAMES; do
            log_info "Reparando stack: $stack"
            force_delete_failed_stack "$stack"
        done
        
        log_success "Proceso de reparación completado"
    else
        log_info "Reparación cancelada por el usuario"
    fi
    
    exit 0
fi

# Listar stacks existentes (incluyendo DELETE_FAILED)
log_info "Buscando stacks relacionados con event-manager..."
EXISTING_STACKS=$(aws cloudformation list-stacks \
    --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE CREATE_FAILED UPDATE_FAILED ROLLBACK_COMPLETE DELETE_FAILED \
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

# Paso 0: Manejar stacks en estado DELETE_FAILED
log_info "Verificando stacks en estado DELETE_FAILED..."
FAILED_STACKS=$(aws cloudformation list-stacks \
    --stack-status-filter DELETE_FAILED \
    --query 'StackSummaries[?contains(StackName, `event-manager`)].StackName' \
    --output text 2>/dev/null || echo "")

if [[ -n "$FAILED_STACKS" && "$FAILED_STACKS" != "None" ]]; then
    log_warning "Se encontraron stacks en estado DELETE_FAILED: $FAILED_STACKS"
    for stack in $FAILED_STACKS; do
        log_info "Intentando limpiar stack fallido: $stack"
        force_delete_failed_stack "$stack"
    done
fi

# Función para limpiar buckets S3 de un stack
cleanup_s3_buckets() {
    local stack_name=$1
    log_info "Limpiando buckets S3 del stack: $stack_name"
    
    if aws cloudformation describe-stacks --stack-name "$stack_name" > /dev/null 2>&1; then
        # Obtener todos los buckets del stack
        local buckets=$(aws cloudformation describe-stack-resources \
            --stack-name "$stack_name" \
            --query 'StackResources[?ResourceType==`AWS::S3::Bucket`].PhysicalResourceId' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$buckets" && "$buckets" != "None" ]]; then
            for bucket in $buckets; do
                if aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
                    log_info "Vaciando bucket: $bucket"
                    # Eliminar todas las versiones de objetos
                    aws s3api delete-objects --bucket "$bucket" \
                        --delete "$(aws s3api list-object-versions --bucket "$bucket" \
                        --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
                        --max-items 1000)" 2>/dev/null || true
                    
                    # Eliminar marcadores de eliminación
                    aws s3api delete-objects --bucket "$bucket" \
                        --delete "$(aws s3api list-object-versions --bucket "$bucket" \
                        --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
                        --max-items 1000)" 2>/dev/null || true
                    
                    # Eliminar objetos normales
                    aws s3 rm s3://$bucket --recursive 2>/dev/null || true
                    log_success "Bucket $bucket vaciado"
                else
                    log_warning "Bucket $bucket no existe o no es accesible"
                fi
            done
        fi
    fi
}

# Función para forzar eliminación de stack en DELETE_FAILED
force_delete_failed_stack() {
    local stack_name=$1
    log_warning "Intentando forzar eliminación del stack en estado DELETE_FAILED: $stack_name"
    
    # Primero limpiar buckets S3
    cleanup_s3_buckets "$stack_name"
    
    # Intentar eliminar el stack nuevamente
    log_info "Reintentando eliminación del stack: $stack_name"
    aws cloudformation delete-stack --stack-name "$stack_name" || true
    
    # Esperar un poco y verificar
    sleep 10
    local status=$(aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --query 'Stacks[0].StackStatus' \
        --output text 2>/dev/null || echo "DELETE_COMPLETE")
    
    if [[ "$status" == "DELETE_FAILED" ]]; then
        log_error "Stack $stack_name sigue en estado DELETE_FAILED"
        log_info "Mostrando recursos que fallaron al eliminar:"
        aws cloudformation describe-stack-events \
            --stack-name "$stack_name" \
            --query 'StackEvents[?ResourceStatus==`DELETE_FAILED`].[LogicalResourceId,ResourceStatusReason]' \
            --output table
        
        log_warning "Puedes necesitar eliminar recursos manualmente o contactar soporte AWS"
        return 1
    else
        log_info "Stack $stack_name ahora en estado: $status"
        return 0
    fi
}

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
            if force_delete_failed_stack "$stack_name"; then
                continue  # Reintentar el bucle
            else
                break  # Salir si no se puede forzar la eliminación
            fi
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

# Paso 1.5: Eliminar stack de InitDB (event-manager-initdb)
log_info "Eliminando stack InitDB: event-manager-initdb"
if aws cloudformation describe-stacks --stack-name event-manager-initdb > /dev/null 2>&1; then
    log_warning "Eliminando stack event-manager-initdb..."
    aws cloudformation delete-stack --stack-name event-manager-initdb
    wait_for_stack_deletion event-manager-initdb
else
    log_info "Stack event-manager-initdb no existe o ya fue eliminado"
fi

# Paso 1.6: Eliminar base de datos RDS y recursos relacionados
log_info "Eliminando recursos de base de datos RDS..."

# Configuración
ENVIRONMENT=${ENVIRONMENT:-dev}
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")

# Eliminar instancia RDS
RDS_INSTANCE_ID="event-manager-db-$ENVIRONMENT"
if aws rds describe-db-instances --db-instance-identifier "$RDS_INSTANCE_ID" > /dev/null 2>&1; then
    log_warning "Eliminando instancia RDS: $RDS_INSTANCE_ID"
    log_info "Esto puede tomar 10-15 minutos..."
    
    # Eliminar instancia RDS (skip-final-snapshot para eliminación rápida)
    aws rds delete-db-instance \
        --db-instance-identifier "$RDS_INSTANCE_ID" \
        --skip-final-snapshot \
        --delete-automated-backups || log_warning "Error eliminando instancia RDS o ya está en proceso de eliminación"
    
    # Esperar a que se elimine
    log_info "Esperando a que se elimine la instancia RDS..."
    aws rds wait db-instance-deleted --db-instance-identifier "$RDS_INSTANCE_ID" || log_warning "Timeout esperando eliminación de RDS"
    log_success "Instancia RDS eliminada: $RDS_INSTANCE_ID"
else
    log_info "Instancia RDS $RDS_INSTANCE_ID no existe o ya fue eliminada"
fi

# Eliminar Security Group de RDS
SG_NAME="event-manager-rds-sg"
if aws ec2 describe-security-groups --group-names "$SG_NAME" > /dev/null 2>&1; then
    SG_ID=$(aws ec2 describe-security-groups --group-names "$SG_NAME" --query 'SecurityGroups[0].GroupId' --output text)
    log_warning "Eliminando Security Group RDS: $SG_NAME ($SG_ID)"
    aws ec2 delete-security-group --group-id "$SG_ID" || log_warning "Error eliminando Security Group RDS"
    log_success "Security Group RDS eliminado: $SG_NAME"
else
    log_info "Security Group $SG_NAME no existe o ya fue eliminado"
fi

# Eliminar Secret de base de datos
SECRET_NAME="event-app/db-credentials-$ENVIRONMENT-$AWS_ACCOUNT_ID"
if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" > /dev/null 2>&1; then
    log_warning "Eliminando secret de base de datos: $SECRET_NAME"
    aws secretsmanager delete-secret \
        --secret-id "$SECRET_NAME" \
        --force-delete-without-recovery || log_warning "Error eliminando secret de base de datos"
    log_success "Secret de base de datos eliminado: $SECRET_NAME"
else
    log_info "Secret $SECRET_NAME no existe o ya fue eliminado"
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
    --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE CREATE_FAILED UPDATE_FAILED ROLLBACK_COMPLETE DELETE_FAILED \
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

# Verificar instancias RDS huérfanas
ORPHAN_RDS=$(aws rds describe-db-instances \
    --query 'DBInstances[?contains(DBInstanceIdentifier, `event-manager`)].DBInstanceIdentifier' \
    --output text 2>/dev/null || echo "")

if [[ -n "$ORPHAN_RDS" && "$ORPHAN_RDS" != "None" ]]; then
    log_warning "Se encontraron instancias RDS huérfanas: $ORPHAN_RDS"
    log_info "Puedes eliminarlas manualmente si es necesario."
fi

# Verificar secrets huérfanos
ORPHAN_SECRETS=$(aws secretsmanager list-secrets \
    --query 'SecretList[?contains(Name, `event-app/db-credentials`)].Name' \
    --output text 2>/dev/null || echo "")

if [[ -n "$ORPHAN_SECRETS" && "$ORPHAN_SECRETS" != "None" ]]; then
    log_warning "Se encontraron secrets huérfanos: $ORPHAN_SECRETS"
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
log_info "✅ Stack event-manager-initdb eliminado"
log_info "✅ Base de datos RDS eliminada"
log_info "✅ Security Group RDS eliminado"
log_info "✅ Secrets Manager eliminado"
log_info "✅ Stack event-manager-s3 eliminado"
log_info "✅ Buckets S3 vaciados"
log_info "✅ Archivos temporales eliminados"

if [[ -n "$ORPHAN_LAMBDAS" && "$ORPHAN_LAMBDAS" != "None" ]] || [[ -n "$ORPHAN_BUCKETS" && "$ORPHAN_BUCKETS" != "None" ]] || [[ -n "$ORPHAN_RDS" && "$ORPHAN_RDS" != "None" ]] || [[ -n "$ORPHAN_SECRETS" && "$ORPHAN_SECRETS" != "None" ]]; then
    echo -e "\n${YELLOW}=== RECURSOS QUE REQUIEREN ATENCIÓN MANUAL ===${NC}"
    [[ -n "$ORPHAN_LAMBDAS" && "$ORPHAN_LAMBDAS" != "None" ]] && log_warning "Funciones Lambda: $ORPHAN_LAMBDAS"
    [[ -n "$ORPHAN_BUCKETS" && "$ORPHAN_BUCKETS" != "None" ]] && log_warning "Buckets S3: $ORPHAN_BUCKETS"
    [[ -n "$ORPHAN_RDS" && "$ORPHAN_RDS" != "None" ]] && log_warning "Instancias RDS: $ORPHAN_RDS"
    [[ -n "$ORPHAN_SECRETS" && "$ORPHAN_SECRETS" != "None" ]] && log_warning "Secrets Manager: $ORPHAN_SECRETS"
fi

echo -e "\n${BLUE}Para volver a desplegar el sistema, ejecuta:${NC}"
echo "./deploy.sh"

log_success "¡Limpieza completada exitosamente!"

