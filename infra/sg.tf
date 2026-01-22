# SG para tareas ECS (Temporal Server y UI)
resource "aws_security_group" "tasks_sg" {
  name        = "temporal-tasks-sg"
  description = "Allow internal Temporal traffic and ALB to UI"
  vpc_id      = aws_vpc.main.id

  # Inbound: permitir tráfico desde sí mismo (comunicación entre containers Temporal)
  ingress {
    description = "Temporal internode communication"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    self        = true
  }
  # Inbound: permitir ALB acceder a UI (puerto 8080)
  ingress {
    description     = "ALB to Temporal UI"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }
  # Outbound: por defecto AWS permite todo egress
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "temporal-tasks-sg" }
}

# SG para base de datos MySQL
resource "aws_security_group" "rds_sg" {
  name        = "temporal-rds-sg"
  description = "Security group para RDS MySQL de Temporal"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "MySQL desde VPC"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "temporal-rds-sg" }

  lifecycle {
    ignore_changes = [ingress, egress] # Evitar recreación
  }
}

# SG para el Application Load Balancer (ALB)
resource "aws_security_group" "alb_sg" {
  name        = "temporal-alb-sg"
  description = "Allow HTTP and HTTPS from internet"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "API Service HTTP from internet"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "temporal-alb-sg" }

  lifecycle {
    ignore_changes = [description]
  }
}
