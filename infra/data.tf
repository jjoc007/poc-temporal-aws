# Data source para obtener AZs disponibles
data "aws_availability_zones" "available" {
  state = "available"
}

# Subnet group para RDS (usar subnets privadas)
resource "aws_db_subnet_group" "temporal" {
  name       = "temporal-db-subnets"
  subnet_ids = aws_subnet.private[*].id
  tags       = { Name = "temporal-db-subnet-group" }
}

# RDS MySQL Instance
resource "aws_db_instance" "temporal" {
  identifier             = "temporal-mysql-db"
  engine                 = "mysql"
  engine_version         = "8.0"         # MySQL 8.x
  instance_class         = "db.t3.small" # usar instancia burstable
  allocated_storage      = 20            # 20 GB almacenamiento
  storage_type           = "gp2"
  username               = "temporaluser"
  password               = "CambioEstaContrasena123!" # (ideal generar aleatoria/secret)
  db_name                = "temporal"                 # BD principal
  multi_az               = false                      # single AZ (costos bajos; considerar true en prod)
  publicly_accessible    = false
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.temporal.name
  tags                   = { Name = "temporal-db" }
}
