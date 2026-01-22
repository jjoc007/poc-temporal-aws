output "vpc_id" {
  description = "ID de la VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs de las subnets públicas"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs de las subnets privadas"
  value       = aws_subnet.private[*].id
}

output "rds_endpoint" {
  description = "Endpoint de RDS MySQL"
  value       = aws_db_instance.temporal.endpoint
}

output "rds_address" {
  description = "Address de RDS MySQL (sin puerto)"
  value       = aws_db_instance.temporal.address
}

output "ecs_cluster_name" {
  description = "Nombre del ECS cluster"
  value       = aws_ecs_cluster.temporal.name
}

output "ecs_cluster_arn" {
  description = "ARN del ECS cluster"
  value       = aws_ecs_cluster.temporal.arn
}

output "nat_gateway_ip" {
  description = "IP pública del NAT Gateway"
  value       = aws_eip.nat_ip.public_ip
}

output "alb_dns_name" {
  description = "DNS del Application Load Balancer"
  value       = aws_lb.temporal_ui.dns_name
}

output "temporal_ui_url" {
  description = "URL de Temporal UI"
  value       = "http://${aws_lb.temporal_ui.dns_name}"
}
