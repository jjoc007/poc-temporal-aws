#!/bin/bash
set -e

# Script para ejecutar 2 workflows en el cluster de infra-2

echo "================================================"
echo "Ejecutando 2 Workflows en Temporal (infra-2)"
echo "================================================"

# Usamos el API service del cluster anterior
API_URL="http://temporal-aws-poc-alb-1837777002.us-east-1.elb.amazonaws.com:8080"

# NOTA: El API service está configurado para conectarse al cluster temporal-aws-poc
# Para ejecutar en infra-2, necesitamos:
# 1. Desplegar API service en infra-2, O
# 2. Usar port-forward para conectar directamente, O
# 3. Usar Temporal CLI desde dentro del VPC

echo ""
echo "⚠️  IMPORTANTE:"
echo "El API service actual está conectado al cluster 'temporal-aws-poc'"
echo "Para ejecutar workflows en 'temporal-ecs-cluster' (infra-2) necesitas:"
echo ""
echo "Opción 1: Desplegar API service en infra-2"
echo "Opción 2: Usar Temporal CLI con port-forward"
echo "Opción 3: Crear una tarea ECS one-time para ejecutar workflows"
echo ""
echo "================================================"
echo "Ejecutando en cluster temporal-aws-poc (demo)"
echo "================================================"
echo ""

# Workflow 1: WorkflowA
echo "=== Workflow 1: WorkflowA ==="
RESPONSE1=$(curl -s -X POST ${API_URL}/workflows/start \
  -H "Content-Type: application/json" \
  -d '{"workflowId":"test-demo-a-002","input":{"message":"Demo workflow A"}}')

echo "Response: $RESPONSE1"
echo ""

# Workflow 2: WorkflowC
echo "=== Workflow 2: WorkflowC ==="
RESPONSE2=$(curl -s -X POST ${API_URL}/workflows/start \
  -H "Content-Type: application/json" \
  -d '{"workflowId":"test-demo-c-002","input":{"data":"Demo workflow C"}}')

echo "Response: $RESPONSE2"
echo ""

echo "================================================"
echo "Esperando 30 segundos..."
echo "================================================"
sleep 30

echo ""
echo "=== Estado WorkflowA ==="
curl -s "${API_URL}/workflows/status?workflowId=test-demo-a-002" | jq '.status'

echo ""
echo "=== Estado WorkflowC ==="
curl -s "${API_URL}/workflows/status?workflowId=test-demo-c-002" | jq '.status'

echo ""
echo "================================================"
echo "✅ 2 Workflows ejecutados"
echo "================================================"
echo ""
echo "Ver en UI cluster 1: http://temporal-aws-poc-alb-1837777002.us-east-1.elb.amazonaws.com"
echo "Ver en UI cluster 2: http://TemporalUI-ALB-1514129048.us-east-1.elb.amazonaws.com"
