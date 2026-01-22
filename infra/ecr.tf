# ECR Repository para Worker Service
resource "aws_ecr_repository" "worker_service" {
  name                 = "temporal-worker-service"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = "temporal-worker-service"
  }
}

# Lifecycle policy para Worker Service
resource "aws_ecr_lifecycle_policy" "worker_service" {
  repository = aws_ecr_repository.worker_service.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = {
        type = "expire"
      }
    }]
  })
}

# ECR Repository para API Service
resource "aws_ecr_repository" "api_service" {
  name                 = "temporal-api-service"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = "temporal-api-service"
  }
}

# Lifecycle policy para API Service
resource "aws_ecr_lifecycle_policy" "api_service" {
  repository = aws_ecr_repository.api_service.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = {
        type = "expire"
      }
    }]
  })
}
