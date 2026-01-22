#!/bin/bash
set -e

# Script para construir y subir imágenes Docker a ECR
# Uso: ./build-and-push-images.sh [api|worker|all]

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuración
REGION="${AWS_REGION:-us-east-1}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")

if [ -z "$AWS_ACCOUNT_ID" ]; then
    echo -e "${RED}Error: No se pudo obtener el AWS Account ID. Verifica que AWS CLI esté configurado.${NC}"
    exit 1
fi

# Repositorios ECR
API_REPO="temporal-api-service"
WORKER_REPO="temporal-worker-service"

# URLs completas de ECR
API_ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${API_REPO}"
WORKER_ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${WORKER_REPO}"

# Directorios base
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
API_DIR="${PROJECT_ROOT}/services/api"
WORKER_DIR="${PROJECT_ROOT}/services/worker"

# Función para imprimir mensajes
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Función para autenticar con ECR
authenticate_ecr() {
    log_info "Autenticando con ECR..."
    aws ecr get-login-password --region ${REGION} | \
        docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com

    if [ $? -eq 0 ]; then
        log_info "✅ Autenticación exitosa con ECR"
    else
        log_error "❌ Error al autenticar con ECR"
        exit 1
    fi
}

# Función para verificar que el repositorio existe
check_repo_exists() {
    local repo_name=$1
    log_info "Verificando que el repositorio ${repo_name} existe..."

    if aws ecr describe-repositories --repository-names ${repo_name} --region ${REGION} &>/dev/null; then
        log_info "✅ Repositorio ${repo_name} existe"
        return 0
    else
        log_error "❌ Repositorio ${repo_name} no existe. Ejecuta 'terraform apply' primero."
        return 1
    fi
}

# Función para construir y subir imagen API
build_and_push_api() {
    log_info "=========================================="
    log_info "Construyendo imagen API Service"
    log_info "=========================================="

    if [ ! -d "${API_DIR}" ]; then
        log_error "Directorio ${API_DIR} no existe"
        return 1
    fi

    if [ ! -f "${API_DIR}/Dockerfile" ]; then
        log_error "Dockerfile no encontrado en ${API_DIR}"
        return 1
    fi

    # Verificar repositorio
    if ! check_repo_exists ${API_REPO}; then
        return 1
    fi

    cd "${API_DIR}"

    # Construir imagen
    log_info "Construyendo imagen Docker..."
    docker build -t ${API_REPO}:latest \
                 -t ${API_ECR_URI}:latest \
                 -t ${API_ECR_URI}:$(date +%Y%m%d-%H%M%S) \
                 .

    if [ $? -ne 0 ]; then
        log_error "❌ Error al construir la imagen API"
        return 1
    fi

    log_info "✅ Imagen construida exitosamente"

    # Subir imagen
    log_info "Subiendo imagen a ECR..."
    docker push ${API_ECR_URI}:latest

    if [ $? -eq 0 ]; then
        log_info "✅ Imagen API subida exitosamente a ${API_ECR_URI}:latest"

        # También subir la versión con timestamp
        docker push ${API_ECR_URI}:$(docker images ${API_REPO}:latest --format "{{.CreatedAt}}" | awk '{print $1}' | tr -d '-' | head -c 8)-$(date +%H%M%S) 2>/dev/null || true
    else
        log_error "❌ Error al subir la imagen API"
        return 1
    fi
}

# Función para construir y subir imagen Worker
build_and_push_worker() {
    log_info "=========================================="
    log_info "Construyendo imagen Worker Service"
    log_info "=========================================="

    if [ ! -d "${WORKER_DIR}" ]; then
        log_error "Directorio ${WORKER_DIR} no existe"
        return 1
    fi

    if [ ! -f "${WORKER_DIR}/Dockerfile" ]; then
        log_error "Dockerfile no encontrado en ${WORKER_DIR}"
        return 1
    fi

    # Verificar repositorio
    if ! check_repo_exists ${WORKER_REPO}; then
        return 1
    fi

    cd "${WORKER_DIR}"

    # Construir imagen
    log_info "Construyendo imagen Docker..."
    docker build -t ${WORKER_REPO}:latest \
                 -t ${WORKER_ECR_URI}:latest \
                 -t ${WORKER_ECR_URI}:$(date +%Y%m%d-%H%M%S) \
                 .

    if [ $? -ne 0 ]; then
        log_error "❌ Error al construir la imagen Worker"
        return 1
    fi

    log_info "✅ Imagen construida exitosamente"

    # Subir imagen
    log_info "Subiendo imagen a ECR..."
    docker push ${WORKER_ECR_URI}:latest

    if [ $? -eq 0 ]; then
        log_info "✅ Imagen Worker subida exitosamente a ${WORKER_ECR_URI}:latest"
    else
        log_error "❌ Error al subir la imagen Worker"
        return 1
    fi
}

# Función principal
main() {
    local service="${1:-all}"

    echo ""
    log_info "=========================================="
    log_info "Build and Push Images to ECR"
    log_info "=========================================="
    echo ""
    log_info "AWS Account ID: ${AWS_ACCOUNT_ID}"
    log_info "Region: ${REGION}"
    log_info "Service: ${service}"
    echo ""

    # Autenticar con ECR
    authenticate_ecr

    # Procesar según el servicio solicitado
    case "${service}" in
        api)
            build_and_push_api
            ;;
        worker)
            build_and_push_worker
            ;;
        all)
            build_and_push_api
            echo ""
            build_and_push_worker
            ;;
        *)
            log_error "Servicio desconocido: ${service}"
            echo ""
            echo "Uso: $0 [api|worker|all]"
            echo ""
            echo "  api     - Construir y subir solo API Service"
            echo "  worker  - Construir y subir solo Worker Service"
            echo "  all     - Construir y subir ambos servicios (default)"
            exit 1
            ;;
    esac

    echo ""
    log_info "=========================================="
    log_info "✅ Proceso completado"
    log_info "=========================================="
    echo ""

    # Mostrar URLs de las imágenes
    if [ "${service}" == "api" ] || [ "${service}" == "all" ]; then
        log_info "Imagen API disponible en: ${API_ECR_URI}:latest"
    fi

    if [ "${service}" == "worker" ] || [ "${service}" == "all" ]; then
        log_info "Imagen Worker disponible en: ${WORKER_ECR_URI}:latest"
    fi

    echo ""
    log_info "Para actualizar los servicios ECS, ejecuta:"
    log_info "  terraform apply -target=aws_ecs_service.svc_api"
    log_info "  terraform apply -target=aws_ecs_service.svc_worker"
    echo ""
}

# Ejecutar función principal
main "$@"
