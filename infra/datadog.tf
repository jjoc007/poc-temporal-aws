# DataDog Configuration para ECS y Temporal

# Secret para API Key de DataDog
resource "aws_secretsmanager_secret" "datadog_api_key" {
  name                    = "datadog-api-key"
  description             = "DataDog API Key para monitoreo"
  recovery_window_in_days = 7
  tags                    = { Name = "datadog-api-key" }
}

resource "aws_secretsmanager_secret_version" "datadog_api_key" {
  secret_id     = aws_secretsmanager_secret.datadog_api_key.id
  secret_string = "TOKEN"
}

# CloudWatch Log Group para DataDog
resource "aws_cloudwatch_log_group" "datadog_agent" {
  name              = "/ecs/datadog-agent"
  retention_in_days = 7
  tags              = { Name = "datadog-agent-logs" }
}

# Locals para configuración de DataDog
locals {
  datadog_agent_container = {
    name      = "datadog-agent"
    image     = "public.ecr.aws/datadog/agent:latest"
    essential = false
    cpu       = 50
    memory    = 256

    portMappings = [
      { containerPort = 8125, protocol = "udp" }, # StatsD
      { containerPort = 8126, protocol = "tcp" }  # APM
    ]

    environment = [
      { name = "DD_SITE", value = "us5.datadoghq.com" },
      { name = "ECS_FARGATE", value = "true" },
      { name = "DD_APM_ENABLED", value = "true" },
      { name = "DD_LOGS_ENABLED", value = "true" },
      { name = "DD_LOGS_CONFIG_CONTAINER_COLLECT_ALL", value = "true" },
      # StatsD - Configuración para recibir métricas
      # IMPORTANTE: En ECS Fargate, los contenedores en la misma task comparten la red
      # Por lo tanto, el agente puede recibir métricas StatsD desde otros contenedores
      { name = "DD_DOGSTATSD_NON_LOCAL_TRAFFIC", value = "true" },
      { name = "DD_DOGSTATSD_PORT", value = "8125" },
      { name = "DD_DOGSTATSD_ORIGIN_DETECTION", value = "true" },
      # Escuchar en todas las interfaces para recibir métricas de otros contenedores
      { name = "DD_DOGSTATSD_SOCKET", value = "0.0.0.0:8125" },
      # Proceso y métricas
      { name = "DD_PROCESS_AGENT_ENABLED", value = "true" },
      { name = "DD_CONTAINER_EXCLUDE", value = "name:datadog-agent" },
      # Tags globales
      { name = "DD_TAGS", value = "cluster:temporal-ecs-cluster,environment:production,application:temporal" },
      # Habilitar Autodiscovery solo para Docker labels (no para inferencia ECS)
      { name = "DD_AUTODISCOVERY_ENABLED", value = "true" },
      { name = "DD_EXTRA_CONFIG_PROVIDERS", value = "docker" },
      # Excluir inferencia automática de ECS que causa problemas de DNS
      { name = "DD_AC_EXCLUDE", value = "name:datadog-agent" },
      # Habilitar logs más detallados para troubleshooting
      { name = "DD_LOG_LEVEL", value = "debug" },
      { name = "DD_CHECK_RUNNERS", value = "4" }
    ]

    secrets = [
      {
        name      = "DD_API_KEY"
        valueFrom = aws_secretsmanager_secret.datadog_api_key.arn
      }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.datadog_agent.name
        "awslogs-region"        = "us-east-1"
        "awslogs-stream-prefix" = "datadog"
      }
    }
  }

  # Variables de entorno para métricas de Temporal
  temporal_datadog_env = [
    # StatsD para métricas en tiempo real - Configuración completa
    # En ECS Fargate con awsvpc, los contenedores en la misma task comparten la red
    # Temporal debe enviar métricas a localhost:8125 donde el agente está escuchando
    { name = "STATSD_ADDRESS", value = "127.0.0.1:8125" },
    { name = "STATSD_ENABLED", value = "true" },
    { name = "STATSD_HOST", value = "127.0.0.1" },
    { name = "STATSD_PORT", value = "8125" },

    # Prometheus para métricas detalladas
    { name = "PROMETHEUS_ENDPOINT", value = "0.0.0.0:8000" },
    { name = "PROMETHEUS_LISTEN_ADDRESS", value = "0.0.0.0:8000" },

    # DataDog tagging
    { name = "DD_SERVICE", value = "temporal-server" },
    { name = "DD_ENV", value = "production" },
    { name = "DD_VERSION", value = "1.25.0" },

    # Habilitar métricas de workflows y activities
    { name = "TEMPORAL_EMIT_METRICS", value = "true" },
    { name = "TEMPORAL_METRICS_PREFIX", value = "temporal" },

    # Configuración adicional de métricas
    { name = "METRICS_PREFIX", value = "temporal" },
    { name = "ENABLE_METRICS", value = "true" },

    # Tags adicionales para métricas
    { name = "DD_TAGS", value = "cluster:temporal-ecs-cluster,environment:production,application:temporal" }
  ]
}
