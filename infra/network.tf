# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "temporal-vpc" }
}

# Subnets (2 públicas, 2 privadas en diferentes AZs)
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 4, count.index) # subdivide /16
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags                    = { Name = "temporal-public-${count.index}" }
}

resource "aws_subnet" "private" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 4, count.index + 4)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false
  tags                    = { Name = "temporal-private-${count.index}" }
}

# Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "temporal-igw" }
}

# Public route table (routes 0.0.0.0/0 -> IGW)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = { Name = "temporal-public-rt" }
}
resource "aws_route_table_association" "public_assoc" {
  count          = length(aws_subnet.public[*].id)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# NAT Gateway (en una subnet pública)
resource "aws_eip" "nat_ip" {
  domain = "vpc"
}
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_ip.id
  subnet_id     = aws_subnet.public[0].id
  tags          = { Name = "temporal-nat" }
}

# Private route table (0.0.0.0/0 -> NAT)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "temporal-private-rt" }
}
resource "aws_route_table_association" "private_assoc" {
  count          = length(aws_subnet.private[*].id)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_ecs_service" "svc_frontend" {
  name            = "temporal-frontend-svc"
  cluster         = aws_ecs_cluster.temporal.id
  task_definition = aws_ecs_task_definition.temporal_frontend.arn
  desired_count   = 1
  # No especificar launch_type cuando se usa capacity_provider_strategy
  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.tasks_sg.id]
    assign_public_ip = false
  }
  service_registries {
    registry_arn = aws_service_discovery_service.frontend_sd.arn
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
}


# Application Load Balancer (internet-facing)
resource "aws_lb" "temporal_ui" {
  name               = "TemporalUI-ALB"
  load_balancer_type = "application"
  subnets            = aws_subnet.public[*].id # ALB en subnets públicas
  security_groups    = [aws_security_group.alb_sg.id]
  idle_timeout       = 60
}

# Target Group para la UI (HTTP sobre puerto 8080)
resource "aws_lb_target_group" "ui_tg" {
  name        = "tg-temporal-ui"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id
  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 5
    matcher             = "200-399"
  }
}

# Target Group para API Service
resource "aws_lb_target_group" "api_tg" {
  name        = "tg-temporal-api"
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id
  health_check {
    path                = "/health"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 5
    matcher             = "200-299"
  }
}


# Listener HTTP simple en el ALB (puerto 80) - UI
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.temporal_ui.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ui_tg.arn
  }
}

# Listener HTTP para API Service (puerto 8080)
resource "aws_lb_listener" "api_http" {
  load_balancer_arn = aws_lb.temporal_ui.arn
  port              = 8080
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api_tg.arn
  }
}

# Nota: Configuración SSL/HTTPS comentada - requiere dominio propio y zona Route53
# Para habilitar SSL:
# 1. Descomentar recursos: aws_acm_certificate, aws_route53_record, aws_lb_listener https
# 2. Agregar: data "aws_route53_zone" "primary" { name = "midominio.com" }
# 3. Cambiar domain_name al dominio real
