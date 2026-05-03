# =============================================================================
# RDS MySQL de PRUEBA en AWS (NO es la RDS de produccion del TFG)
# =============================================================================
# RDS minima para validar el flujo de backup -> Azure Blob -> pilot light.
# Acceso publico activado para que GitHub Actions pueda conectar directamente
# (en el TFG real, RDS esta en subred privada accedida via bastion).
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend S3 parcial: el nombre del bucket se inyecta con -backend-config
  # en `terraform init` porque no se pueden usar variables en el bloque backend.
  backend "s3" {
    key    = "aws-test/terraform.tfstate"
    region = "eu-west-1"
  }
}

provider "aws" {
  region = "eu-west-1"
}

variable "db_password" {
  description = "Contrasena de RDS. Inyectar con TF_VAR_db_password."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 8
    error_message = "La contrasena debe tener al menos 8 caracteres."
  }
}

# VPC por defecto (para pruebas, no creamos custom)
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Security group: MySQL abierto (SOLO PARA PRUEBAS)
resource "aws_security_group" "rds_test" {
  name_prefix = "tfg-rds-test-"
  description = "RDS de prueba - MySQL abierto para test de backup"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "MySQL desde cualquier IP (SOLO PARA PRUEBAS)"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "tfg-rds-test-sg"
    Note = "SOLO-PARA-PRUEBAS-borrar-despues"
  }
}

resource "aws_db_subnet_group" "test" {
  name       = "tfg-test-subnet-group"
  subnet_ids = data.aws_subnets.default.ids

  tags = { Name = "tfg-test-subnet-group" }
}

resource "aws_db_instance" "test" {
  identifier = "tfg-test-mysql"

  engine         = "mysql"
  engine_version = "8.0"
  instance_class = "db.t3.micro"

  allocated_storage = 20
  storage_type      = "gp3"

  db_name  = "tfg_app"
  username = "admin"
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.test.name
  vpc_security_group_ids = [aws_security_group.rds_test.id]

  publicly_accessible = true # SOLO para pruebas

  multi_az            = false
  skip_final_snapshot = true
  deletion_protection = false
  apply_immediately   = true

  backup_retention_period = 1

  tags = {
    Name = "tfg-test-mysql"
    Note = "PRUEBA-borrar-despues"
  }
}

output "rds_endpoint" {
  description = "Endpoint de RDS (host:puerto)"
  value       = aws_db_instance.test.endpoint
}

output "rds_address" {
  description = "Hostname de RDS (sin puerto). Guardar como secreto AWS_RDS_HOST."
  value       = aws_db_instance.test.address
}
