# ECS Cluster con Fargate y Fargate Spot capacity providers
resource "aws_ecs_cluster" "temporal" {
  name = "temporal-ecs-cluster"
}

resource "aws_ecs_cluster_capacity_providers" "temporal" {
  cluster_name       = aws_ecs_cluster.temporal.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    base              = 0
    weight            = 1
  }
  # Default strategy arriba: podemos dejar FARGATE por defecto
  # y definir por servicio la preferencia por Spot (ver más adelante).
}

# IAM role for ECS Task Execution
resource "aws_iam_role" "ecs_execution_role" {
  name               = "TemporalECSTaskExecutionRole"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
}
data "aws_iam_policy_document" "ecs_task_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}
resource "aws_iam_role_policy_attachment" "ecs_exec_attach" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
# Permisos adicionales para Secrets Manager (attach an inline or AWS managed if exists)
resource "aws_iam_policy" "ecs_exec_secrets_policy" {
  name = "TemporalExecutionRoleSecretsPolicy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = [
        "secretsmanager:GetSecretValue",
        "kms:Decrypt"
      ],
      Resource = "*" # en producción reducir a ARNs de secretos específicos
    }]
  })
}
resource "aws_iam_role_policy_attachment" "ecs_exec_secrets_attach" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = aws_iam_policy.ecs_exec_secrets_policy.arn
}

# IAM role for ECS Task (application role)
resource "aws_iam_role" "ecs_task_role" {
  name               = "TemporalECSTaskRole"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
}
# (Opcionalmente adjuntar políticas si el workflow de Temporal debe acceder a AWS)


# Task Definition para Temporal Frontend
resource "aws_ecs_task_definition" "temporal_frontend" {
  family                   = "temporal-frontend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 1024 # 1 vCPU (aumentado para DataDog)
  memory                   = 2048 # 2 GB RAM (aumentado para DataDog)
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    local.datadog_agent_container,
    {
      name      = "temporal-frontend"
      image     = "temporalio/auto-setup:1.25.0"
      essential = true
      portMappings = [
        { containerPort = 7233, protocol = "tcp" }, # puerto gRPC Frontend
        { containerPort = 8000, protocol = "tcp" }  # puerto Prometheus metrics
      ]
      environment = concat([
        { name = "SERVICES", value = "frontend,history,matching,worker" },
        { name = "DB", value = "mysql8" },
        { name = "DB_PORT", value = "3306" },
        { name = "ENABLE_ES", value = "false" },
        { name = "SKIP_SCHEMA_SETUP", value = "false" },
        { name = "SKIP_DEFAULT_NAMESPACE_CREATION", value = "false" },
        { name = "NUM_HISTORY_SHARDS", value = "4" }
      ], local.temporal_datadog_env)
      secrets = [
        {
          name      = "MYSQL_SEEDS",
          valueFrom = "${aws_secretsmanager_secret.db_creds.arn}:HOST::"
        },
        {
          name      = "MYSQL_USER",
          valueFrom = "${aws_secretsmanager_secret.db_creds.arn}:USERNAME::"
        },
        {
          name      = "MYSQL_PWD",
          valueFrom = "${aws_secretsmanager_secret.db_creds.arn}:PASSWORD::"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs",
        options = {
          awslogs-group         = "/ecs/temporal-frontend"
          awslogs-region        = "us-east-1"
          awslogs-stream-prefix = "ecs"
        }
      }
      # Docker labels para configurar Prometheus scraping explícitamente
      # En ECS Fargate con awsvpc, los contenedores en la misma task comparten la red
      # El agente puede acceder a localhost:8000 donde Temporal expone métricas
      dockerLabels = {
        "com.datadoghq.ad.check_names"  = jsonencode(["openmetrics"])
        "com.datadoghq.ad.init_configs" = jsonencode([{}])
        "com.datadoghq.ad.instances" = jsonencode([{
          prometheus_url = "http://127.0.0.1:8000/metrics"
          namespace      = "temporal"
          # Capturar TODAS las métricas usando wildcard "*"
          # Esto asegura que ninguna métrica sea filtrada
          metrics = ["*"]
          tags    = ["service:temporal-server", "environment:production", "cluster:temporal-ecs-cluster"]
          # Configuración adicional para asegurar que scrapee correctamente
          min_collection_interval             = 15
          collect_counters_with_distributions = true
          # Aumentar el límite de métricas para capturar todas las métricas disponibles
          max_returned_metrics = 5000
          # Habilitar envío de histogramas y buckets
          send_histograms_buckets   = true
          send_distribution_buckets = true
        }])
      }
    }
  ])
}

# Task Definition para Temporal UI
resource "aws_ecs_task_definition" "temporal_ui" {
  family                   = "temporal-ui"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256 # 0.25 vCPU
  memory                   = 512 # 0.5 GB RAM (UI requiere poco)
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "temporal-ui"
      image     = "temporalio/ui:2.30.3"
      essential = true
      portMappings = [
        { containerPort = 8080, protocol = "tcp" }
      ]
      environment = [
        { name = "TEMPORAL_ADDRESS", value = "frontend.temporal:7233" },
        { name = "TEMPORAL_UI_PORT", value = "8080" }
      ]
      logConfiguration = {
        logDriver = "awslogs",
        options = {
          awslogs-group         = "/ecs/temporal-ui"
          awslogs-region        = "us-east-1"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}


# Namespace DNS privado para Temporal services
resource "aws_service_discovery_private_dns_namespace" "temporal_ns" {
  name        = "temporal"
  vpc         = aws_vpc.main.id
  description = "Private DNS namespace for Temporal services"
}

# Service registry for Temporal Frontend
resource "aws_service_discovery_service" "frontend_sd" {
  name = "frontend"
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.temporal_ns.id
    dns_records {
      type = "A"
      ttl  = 30
    }
    routing_policy = "MULTIVALUE"
  }
  health_check_custom_config {
    failure_threshold = 1
  }
}
# (Podrías repetir definiciones similares para history, matching, worker, UI si se desea DNS para cada uno)


resource "aws_ecs_service" "svc_ui" {
  name            = "temporal-ui-svc"
  cluster         = aws_ecs_cluster.temporal.id
  task_definition = aws_ecs_task_definition.temporal_ui.arn
  desired_count   = 1
  # No especificar launch_type cuando se usa capacity_provider_strategy
  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.tasks_sg.id]
    assign_public_ip = false
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.ui_tg.arn
    container_name   = "temporal-ui"
    container_port   = 8080
  }
  depends_on = [aws_lb_listener.http] # aseguramos que ALB esté listo
  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
  }
  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 0
    base              = 0
  }
}

# ========================================
# TASK DEFINITION: WORKER SERVICE
# ========================================

resource "aws_ecs_task_definition" "worker_service" {
  family                   = "temporal-worker"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    local.datadog_agent_container,
    {
      name      = "worker-service"
      image     = "${aws_ecr_repository.worker_service.repository_url}:latest"
      essential = true

      environment = [
        { name = "TEMPORAL_HOST_PORT", value = "frontend.temporal:7233" },
        { name = "TASK_QUEUE", value = "hello-world-queue" },
        { name = "DD_SERVICE", value = "temporal-worker" },
        { name = "DD_ENV", value = "production" },
        { name = "STATSD_ADDRESS", value = "localhost:8125" }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.worker_service.name
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "worker"
        }
      }
  }])

  tags = {
    Name = "temporal-worker"
  }
}

# ========================================
# ECS SERVICE: WORKER SERVICE
# ========================================

resource "aws_ecs_service" "svc_worker" {
  name            = "temporal-worker-svc"
  cluster         = aws_ecs_cluster.temporal.id
  task_definition = aws_ecs_task_definition.worker_service.arn
  desired_count   = 1

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.tasks_sg.id]
    assign_public_ip = false
  }

  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
  }

  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 0
    base              = 1
  }

  depends_on = [aws_ecs_service.svc_frontend]

  tags = {
    Name = "temporal-worker-svc"
  }
}

# ========================================
# TASK DEFINITION: API SERVICE
# ========================================

resource "aws_ecs_task_definition" "api_service" {
  family                   = "temporal-api"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 512  # Aumentado para DataDog
  memory                   = 1024 # Aumentado para DataDog
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    local.datadog_agent_container,
    {
      name      = "api-service"
      image     = "${aws_ecr_repository.api_service.repository_url}:latest"
      essential = true

      environment = [
        { name = "TEMPORAL_HOST_PORT", value = "frontend.temporal:7233" },
        { name = "PORT", value = "8080" },
        { name = "DD_SERVICE", value = "temporal-api" },
        { name = "DD_ENV", value = "production" },
        { name = "STATSD_ADDRESS", value = "localhost:8125" }
      ]

      portMappings = [{
        containerPort = 8080
        protocol      = "tcp"
        name          = "http"
      }]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.api_service.name
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "api"
        }
      }

      # Health check manejado por ALB target group
      # Eliminado health check del contenedor para evitar conflictos
  }])

  tags = {
    Name = "temporal-api"
  }
}

# ========================================
# ECS SERVICE: API SERVICE
# ========================================

resource "aws_ecs_service" "svc_api" {
  name            = "temporal-api-svc"
  cluster         = aws_ecs_cluster.temporal.id
  task_definition = aws_ecs_task_definition.api_service.arn
  desired_count   = 1

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.tasks_sg.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api_tg.arn
    container_name   = "api-service"
    container_port   = 8080
  }

  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
  }

  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 0
    base              = 1
  }

  depends_on = [aws_lb_listener.api_http, aws_ecs_service.svc_frontend]

  tags = {
    Name = "temporal-api-svc"
  }
}
