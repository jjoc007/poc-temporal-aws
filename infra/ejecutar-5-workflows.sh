#!/bin/bash
set -e

# Script para ejecutar 5 workflows y validar métricas en Datadog

echo "================================================"
echo "Ejecutando 5 Workflows para Validar Métricas"
echo "================================================"
echo ""

# Obtener URL del ALB
ALB_DNS=$(terraform output -json 2>/dev/null | jq -r '.alb_dns_name.value' || echo "TemporalUI-ALB-1514129048.us-east-1.elb.amazonaws.com")
API_URL="http://${ALB_DNS}:8080"

echo "API URL: ${API_URL}"
echo ""

# Verificar que el API service esté disponible
echo "=== Verificando API Service ==="
if ! curl -s -f "${API_URL}/health" > /dev/null; then
    echo "❌ Error: API Service no está disponible en ${API_URL}"
    echo "Verificando estado del servicio..."
    aws ecs describe-services \
        --cluster temporal-ecs-cluster \
        --services temporal-api-svc \
        --region us-east-1 \
        --query 'services[0].[serviceName,runningCount,desiredCount,status]' \
        --output table
    exit 1
fi

echo "✅ API Service disponible"
echo ""

# Función para ejecutar un workflow
execute_workflow() {
    local workflow_num=$1
    local workflow_id="test-datadog-metrics-$(date +%s)-${workflow_num}"

    echo "=== Workflow ${workflow_num}: ${workflow_id} ==="

    # Iniciar workflow
    RESPONSE=$(curl -s -X POST "${API_URL}/workflows/start" \
        -H "Content-Type: application/json" \
        -d "{
            \"workflowId\": \"${workflow_id}\",
            \"input\": {
                \"message\": \"Workflow ${workflow_num} para validar métricas Datadog\",
                \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
            }
        }")

    if echo "$RESPONSE" | jq -e '.workflowId' > /dev/null 2>&1; then
        WF_ID=$(echo "$RESPONSE" | jq -r '.workflowId')
        RUN_ID=$(echo "$RESPONSE" | jq -r '.runId')
        echo "✅ Workflow iniciado:"
        echo "   Workflow ID: ${WF_ID}"
        echo "   Run ID: ${RUN_ID}"
        echo "$WF_ID" >> /tmp/workflow_ids.txt
    else
        echo "❌ Error iniciando workflow:"
        echo "$RESPONSE" | jq '.' 2>/dev/null || echo "$RESPONSE"
        return 1
    fi

    echo ""
    return 0
}

# Limpiar archivo temporal
rm -f /tmp/workflow_ids.txt

# Ejecutar 5 workflows con un pequeño delay entre cada uno
echo "=== Iniciando 5 Workflows ==="
echo ""

for i in {1..5}; do
    execute_workflow $i
    # Pequeño delay entre workflows para evitar saturación
    if [ $i -lt 5 ]; then
        sleep 2
    fi
done

echo "================================================"
echo "Esperando 30 segundos para que los workflows se ejecuten..."
echo "================================================"
sleep 30

echo ""
echo "=== Verificando Estado de los Workflows ==="
echo ""

# Verificar estado de cada workflow
SUCCESS_COUNT=0
FAILED_COUNT=0

while IFS= read -r workflow_id; do
    if [ -z "$workflow_id" ]; then
        continue
    fi

    echo "--- Verificando: ${workflow_id} ---"
    STATUS_RESPONSE=$(curl -s "${API_URL}/workflows/status?workflowId=${workflow_id}")

    if echo "$STATUS_RESPONSE" | jq -e '.status' > /dev/null 2>&1; then
        STATUS=$(echo "$STATUS_RESPONSE" | jq -r '.status')
        echo "   Estado: ${STATUS}"

        STATUS_LOWER=$(echo "$STATUS" | tr '[:upper:]' '[:lower:]')
        if [ "$STATUS_LOWER" = "completed" ]; then
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            echo "   ✅ Completado exitosamente"
        elif [ "$STATUS_LOWER" = "running" ]; then
            echo "   ⏳ Aún ejecutándose"
        else
            FAILED_COUNT=$((FAILED_COUNT + 1))
            ERROR=$(echo "$STATUS_RESPONSE" | jq -r '.error // "N/A"')
            echo "   ❌ Estado: ${STATUS}"
            if [ "$ERROR" != "null" ] && [ "$ERROR" != "N/A" ]; then
                echo "   Error: ${ERROR}"
            fi
        fi
    else
        echo "   ⚠️  No se pudo obtener el estado"
        echo "   Response: ${STATUS_RESPONSE}"
    fi
    echo ""
done < /tmp/workflow_ids.txt

echo "================================================"
echo "Resumen de Ejecución"
echo "================================================"
echo "Total workflows ejecutados: 5"
echo "Completados exitosamente: ${SUCCESS_COUNT}"
echo "Fallidos o en ejecución: ${FAILED_COUNT}"
echo ""

echo "================================================"
echo "Métricas en Datadog"
echo "================================================"
echo ""
echo "Las métricas deberían estar disponibles en Datadog en los próximos minutos:"
echo ""
echo "1. Métricas de Temporal:"
echo "   - temporal.workflow.*"
echo "   - temporal.activity.*"
echo "   - temporal.task_queue.*"
echo ""
echo "2. Métricas de ECS:"
echo "   - ecs.fargate.*"
echo "   - aws.ecs.*"
echo ""
echo "3. Métricas de aplicación:"
echo "   - Buscar por tags:"
echo "     - service:temporal-frontend"
echo "     - service:temporal-worker"
echo "     - service:api-service"
echo "     - environment:production"
echo ""
echo "URLs útiles:"
echo "  - Temporal UI: http://${ALB_DNS}"
echo "  - API Service: ${API_URL}"
echo ""
echo "================================================"
echo "✅ Validación completada"
echo "================================================"
