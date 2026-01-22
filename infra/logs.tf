# CloudWatch Log Groups para ECS Services

resource "aws_cloudwatch_log_group" "temporal_frontend" {
  name              = "/ecs/temporal-frontend"
  retention_in_days = 7
  tags              = { Name = "temporal-frontend-logs" }
}

resource "aws_cloudwatch_log_group" "temporal_ui" {
  name              = "/ecs/temporal-ui"
  retention_in_days = 7
  tags              = { Name = "temporal-ui-logs" }
}

resource "aws_cloudwatch_log_group" "worker_service" {
  name              = "/ecs/worker-service"
  retention_in_days = 7
  tags              = { Name = "worker-service-logs" }
}

resource "aws_cloudwatch_log_group" "api_service" {
  name              = "/ecs/api-service"
  retention_in_days = 7
  tags              = { Name = "api-service-logs" }
}
