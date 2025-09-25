#!/bin/bash

# 🛠️ Utilidades Comunes - Event Manager AWS
# Funciones reutilizables para todos los scripts

# Colores para output
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export CYAN='\033[0;36m'
export PURPLE='\033[0;35m'
export WHITE='\033[1;37m'
export NC='\033[0m' # No Color

# Función para logging con diferentes niveles
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    if [[ "${DEBUG}" == "true" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $1"
    fi
}

# Función para mostrar progreso
show_progress() {
    local step=$1
    local total=$2
    local description=$3
    echo -e "\n${BLUE}=== PASO $step/$total: $description ===${NC}\n"
}

# Función para mostrar headers
show_header() {
    local title=$1
    local color=${2:-$BLUE}
    echo -e "\n${color}=== $title ===${NC}"
}

# Función para mostrar banners
show_banner() {
    local title=$1
    local subtitle=$2
    local color=${3:-$GREEN}
    
    echo -e "${color}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    printf "║%*s║\n" 62 ""
    printf "║%*s%s%*s║\n" $(((62-${#title})/2)) "" "$title" $(((62-${#title}+1)/2)) ""
    if [[ -n "$subtitle" ]]; then
        printf "║%*s%s%*s║\n" $(((62-${#subtitle})/2)) "" "$subtitle" $(((62-${#subtitle}+1)/2)) ""
    fi
    printf "║%*s║\n" 62 ""
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Función para verificar credenciales AWS
check_aws_credentials() {
    log_info "Verificando credenciales AWS..."
    
    if ! aws sts get-caller-identity > /dev/null 2>&1; then
        log_error "No se pudieron obtener las credenciales AWS."
        log_error "Por favor, configura 'aws configure' primero."
        return 1
    fi
    
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local current_user=$(aws sts get-caller-identity --query Arn --output text)
    local current_region=$(aws configure get region)
    
    log_success "Credenciales AWS válidas:"
    log_info "  - Account ID: $account_id"
    log_info "  - User: $current_user"
    log_info "  - Region: $current_region"
    
    # Exportar variables para uso en otros scripts
    export AWS_ACCOUNT_ID=$account_id
    export AWS_USER_ARN=$current_user
    export AWS_CURRENT_REGION=$current_region
    
    return 0
}

# Función para verificar estructura del proyecto
check_project_structure() {
    log_info "Verificando estructura del proyecto..."
    
    local required_files=(
        "infra/master-template.yml"
        "src"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -e "$file" ]]; then
            log_error "No se encontró: $file"
            log_error "Asegúrate de estar en el directorio correcto del proyecto."
            return 1
        fi
    done
    
    log_success "Estructura del proyecto verificada"
    return 0
}

# Función para esperar confirmación del usuario
confirm_action() {
    local message=$1
    local default_response=${2:-"n"}
    
    if [[ "$default_response" == "y" ]]; then
        local prompt="$message (Y/n): "
    else
        local prompt="$message (y/N): "
    fi
    
    read -p "$(echo -e "${YELLOW}$prompt${NC}")" -n 1 -r
    echo
    
    if [[ "$default_response" == "y" ]]; then
        [[ $REPLY =~ ^[Nn]$ ]] && return 1 || return 0
    else
        [[ $REPLY =~ ^[Yy]$ ]] && return 0 || return 1
    fi
}

# Función para esperar a que un stack se complete
wait_for_stack_operation() {
    local stack_name=$1
    local operation=${2:-"CREATE"}  # CREATE, UPDATE, DELETE
    local timeout=${3:-1800}  # 30 minutos por defecto
    
    log_info "Esperando a que se complete la operación $operation en el stack: $stack_name"
    
    local start_time=$(date +%s)
    local spinner_chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    local spinner_index=0
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -gt $timeout ]]; then
            log_error "Timeout esperando la operación $operation en el stack $stack_name"
            return 1
        fi
        
        local status=$(aws cloudformation describe-stacks \
            --stack-name "$stack_name" \
            --query 'Stacks[0].StackStatus' \
            --output text 2>/dev/null || echo "NOT_FOUND")
        
        case "$operation" in
            "CREATE")
                if [[ "$status" == "CREATE_COMPLETE" ]]; then
                    log_success "Stack $stack_name creado correctamente"
                    return 0
                elif [[ "$status" == "CREATE_FAILED" || "$status" == "ROLLBACK_COMPLETE" ]]; then
                    log_error "Error al crear el stack $stack_name (Estado: $status)"
                    return 1
                fi
                ;;
            "UPDATE")
                if [[ "$status" == "UPDATE_COMPLETE" ]]; then
                    log_success "Stack $stack_name actualizado correctamente"
                    return 0
                elif [[ "$status" == "UPDATE_FAILED" || "$status" == "UPDATE_ROLLBACK_COMPLETE" ]]; then
                    log_error "Error al actualizar el stack $stack_name (Estado: $status)"
                    return 1
                fi
                ;;
            "DELETE")
                if [[ "$status" == "NOT_FOUND" ]]; then
                    log_success "Stack $stack_name eliminado correctamente"
                    return 0
                elif [[ "$status" == "DELETE_FAILED" ]]; then
                    log_error "Error al eliminar el stack $stack_name"
                    return 1
                fi
                ;;
        esac
        
        # Mostrar spinner
        local spinner_char=${spinner_chars:$spinner_index:1}
        printf "\r${BLUE}[INFO]${NC} Estado actual: $status $spinner_char (${elapsed}s)"
        spinner_index=$(( (spinner_index + 1) % ${#spinner_chars} ))
        
        sleep 5
    done
}

# Función para obtener outputs de un stack
get_stack_output() {
    local stack_name=$1
    local output_key=$2
    
    aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --query "Stacks[0].Outputs[?OutputKey=='$output_key'].OutputValue" \
        --output text 2>/dev/null || echo ""
}

# Función para listar stacks relacionados con event-manager
list_event_manager_stacks() {
    local status_filter=${1:-"CREATE_COMPLETE UPDATE_COMPLETE"}
    
    aws cloudformation list-stacks \
        --stack-status-filter $status_filter \
        --query 'StackSummaries[?contains(StackName, `event-manager`)].{Name:StackName,Status:StackStatus,Created:CreationTime}' \
        --output table
}

# Función para validar template de CloudFormation
validate_template() {
    local template_file=$1
    
    log_info "Validando template: $template_file"
    
    if [[ ! -f "$template_file" ]]; then
        log_error "Template no encontrado: $template_file"
        return 1
    fi
    
    if aws cloudformation validate-template --template-body file://$template_file > /dev/null 2>&1; then
        log_success "Template válido: $template_file"
        return 0
    else
        log_error "Template inválido: $template_file"
        aws cloudformation validate-template --template-body file://$template_file
        return 1
    fi
}

# Función para limpiar archivos temporales
cleanup_temp_files() {
    local files=("lambda-functions.zip" "response.json" "temp-*.json" "*.tmp")
    
    log_info "Limpiando archivos temporales..."
    
    for pattern in "${files[@]}"; do
        if ls $pattern 1> /dev/null 2>&1; then
            rm -f $pattern
            log_debug "Eliminado: $pattern"
        fi
    done
    
    log_success "Archivos temporales limpiados"
}

# Función para mostrar tiempo transcurrido
show_elapsed_time() {
    local start_time=$1
    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))
    
    local hours=$((elapsed / 3600))
    local minutes=$(((elapsed % 3600) / 60))
    local seconds=$((elapsed % 60))
    
    if [[ $hours -gt 0 ]]; then
        log_info "Tiempo transcurrido: ${hours}h ${minutes}m ${seconds}s"
    elif [[ $minutes -gt 0 ]]; then
        log_info "Tiempo transcurrido: ${minutes}m ${seconds}s"
    else
        log_info "Tiempo transcurrido: ${seconds}s"
    fi
}

# Función para verificar si un comando existe
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Función para verificar dependencias
check_dependencies() {
    local dependencies=("aws" "jq" "zip")
    local missing_deps=()
    
    log_info "Verificando dependencias..."
    
    for dep in "${dependencies[@]}"; do
        if ! command_exists "$dep"; then
            missing_deps+=("$dep")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Dependencias faltantes: ${missing_deps[*]}"
        log_error "Por favor, instala las dependencias faltantes antes de continuar."
        return 1
    fi
    
    log_success "Todas las dependencias están disponibles"
    return 0
}

# Función para crear backup de configuración
backup_config() {
    local backup_dir="backups/$(date +%Y%m%d_%H%M%S)"
    
    log_info "Creando backup de configuración..."
    
    mkdir -p "$backup_dir"
    
    # Backup de parámetros
    if [[ -d "infra/parameters" ]]; then
        cp -r infra/parameters "$backup_dir/"
    fi
    
    # Backup de variables de entorno
    if [[ -f ".env" ]]; then
        cp .env "$backup_dir/"
    fi
    
    log_success "Backup creado en: $backup_dir"
    echo "$backup_dir"
}

# Función para mostrar ayuda
show_help() {
    local script_name=$1
    
    echo -e "${WHITE}Uso: $script_name [opciones]${NC}"
    echo ""
    echo -e "${WHITE}Variables de entorno disponibles:${NC}"
    echo "  ENVIRONMENT     - Entorno de despliegue (dev/prod) [default: dev]"
    echo "  DB_USERNAME     - Usuario de base de datos [default: event_admin]"
    echo "  AWS_REGION      - Región de AWS [default: región configurada]"
    echo "  DEBUG           - Mostrar mensajes de debug (true/false) [default: false]"
    echo ""
    echo -e "${WHITE}Ejemplos:${NC}"
    echo "  $script_name"
    echo "  ENVIRONMENT=prod $script_name"
    echo "  DEBUG=true $script_name"
}

# Mensaje de inicialización
log_debug "Utilidades cargadas correctamente"
