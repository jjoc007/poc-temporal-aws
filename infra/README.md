# 🚀 Guía Completa: Desplegando Temporal en AWS ECS con Monitoreo en Datadog

## 📚 Tabla de Contenidos

1. [Introducción y Conceptos](#introducción-y-conceptos)
2. [Prerrequisitos](#prerrequisitos)
3. [Arquitectura de la Solución](#arquitectura-de-la-solución)
4. [Paso 1: Configuración Inicial](#paso-1-configuración-inicial)
5. [Paso 2: Infraestructura de Red](#paso-2-infraestructura-de-red)
6. [Paso 3: Base de Datos RDS](#paso-3-base-de-datos-rds)
7. [Paso 4: Configuración de ECS](#paso-4-configuración-de-ecs)
8. [Paso 5: Despliegue de Temporal](#paso-5-despliegue-de-temporal)
9. [Paso 6: Integración con Datadog](#paso-6-integración-con-datadog)
10. [Paso 7: Validación y Pruebas](#paso-7-validación-y-pruebas)
11. [Troubleshooting](#troubleshooting)

---

## 🎯 Introducción y Conceptos

### ¿Qué es AWS ECS?

**Amazon Elastic Container Service (ECS)** es un servicio de orquestación de contenedores completamente administrado que permite ejecutar, detener y gestionar contenedores Docker en un clúster. En esta POC utilizamos **ECS Fargate**, que es la modalidad serverless de ECS donde no necesitas gestionar servidores EC2.

**Características clave:**
- **Fargate**: Sin gestión de servidores, solo defines contenedores
- **Fargate Spot**: Versión más económica con interrupciones ocasionales
- **Auto-scaling**: Escala automáticamente según la demanda
- **Service Discovery**: Resolución DNS automática entre servicios

### ¿Qué es Temporal?

**Temporal** es una plataforma de código abierto para orquestar workflows distribuidos. Permite escribir código de negocio que se ejecuta de manera confiable, incluso ante fallos de infraestructura.

**Conceptos principales:**
- **Workflow**: Flujo de trabajo que define la lógica de negocio
- **Activity**: Tarea individual ejecutada por un worker
- **Task Queue**: Cola de tareas pendientes
- **History Service**: Almacena el historial de ejecuciones
- **Matching Service**: Asigna tareas a workers disponibles

**¿Por qué Temporal?**
- ✅ Ejecución confiable y durable
- ✅ Retry automático ante fallos
- ✅ Versionado de workflows
- ✅ Observabilidad completa

### ¿Qué es Datadog?

**Datadog** es una plataforma de monitoreo y observabilidad que permite:
- **Métricas**: Recopilación y visualización de métricas en tiempo real
- **Logs**: Agregación y análisis de logs
- **APM**: Application Performance Monitoring
- **Dashboards**: Visualización personalizada de métricas

**En esta POC usamos Datadog para:**
- Monitorear métricas de Temporal (workflows, activities, latencias)
- Recopilar logs de todos los servicios
- Visualizar el estado de la infraestructura ECS

---

## 📋 Prerrequisitos

Antes de comenzar, asegúrate de tener:

### Herramientas Instaladas

```bash
# Terraform (versión >= 1.0)
terraform --version

# AWS CLI configurado
aws --version
aws configure list

# jq (para procesar JSON)
jq --version

# curl
curl --version
```

### Cuentas y Credenciales

1. **AWS Account** con permisos para:
   - ECS, VPC, RDS, IAM, Secrets Manager, CloudWatch
   - ECR (para almacenar imágenes Docker)

2. **Datadog Account** con:
   - API Key (disponible en Organization Settings → API Keys)
   - Acceso a la región `us5.datadoghq.com`

### Configuración de AWS

```bash
# Configurar credenciales AWS
aws configure

# Verificar acceso
aws sts get-caller-identity

# Configurar región por defecto
export AWS_DEFAULT_REGION=us-east-1
```

---

## 🏗️ Arquitectura de la Solución

```
┌─────────────────────────────────────────────────────────────┐
│                        Internet                              │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│              Application Load Balancer (ALB)                 │
│              - Temporal UI (puerto 80)                       │
│              - API Service (puerto 8080)                      │
└──────────────┬──────────────────────────────┬───────────────┘
               │                              │
               ▼                              ▼
┌──────────────────────────┐    ┌──────────────────────────┐
│   Subnet Pública         │    │   Subnet Privada         │
│   - NAT Gateway          │    │   - ECS Tasks (Fargate)   │
│   - Internet Gateway     │    │     • temporal-frontend   │
└──────────────────────────┘    │     • temporal-ui         │
                                 │     • temporal-worker     │
                                 │     • temporal-api        │
                                 │   - Datadog Agent         │
                                 │   - RDS MySQL             │
                                 └──────────────────────────┘
```

### Componentes Principales

1. **VPC**: Red privada aislada (10.0.0.0/16)
2. **Subnets**: 2 públicas + 2 privadas en diferentes AZs
3. **RDS MySQL**: Base de datos para Temporal
4. **ECS Cluster**: Clúster Fargate para ejecutar contenedores
5. **ALB**: Load balancer para exponer servicios
6. **Datadog Agent**: Sidecar en cada task para recopilar métricas

---

## 📝 Paso 1: Configuración Inicial

### 1.1 Estructura del Proyecto

Crea la siguiente estructura de directorios:

```
infra-2/
├── provider.tf          # Configuración del provider AWS
├── data.tf             # Data sources (AZs, etc.)
├── network.tf           # VPC, subnets, NAT, ALB
├── sg.tf               # Security Groups
├── ecr.tf              # ECR repositories
├── logs.tf             # CloudWatch Log Groups
├── secrets.tf          # Secrets Manager
├── ecs.tf              # ECS cluster, tasks, services
├── datadog.tf          # Configuración Datadog
└── outputs.tf          # Outputs de Terraform
```

### 1.2 Configurar Provider de Terraform

Crea `provider.tf`:

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}
```

### 1.3 Inicializar Terraform

```bash
cd infra-2/
terraform init
```

**Qué verificar:**
- ✅ Debe descargar el provider de AWS
- ✅ No debe haber errores
- ✅ Se crea el directorio `.terraform/`

---

## 🌐 Paso 2: Infraestructura de Red

### 2.1 Crear VPC y Subnets

En `network.tf`, define:

#### **aws_vpc.main** - Virtual Private Cloud

**¿Qué hace?**
Crea una red privada virtual aislada en AWS. Es como crear tu propia red privada en la nube, completamente separada de otras VPCs y de internet.

**Parámetros importantes:**
- `cidr_block = "10.0.0.0/16"`: Define el rango de IPs privadas. `/16` significa 65,536 direcciones IP (10.0.0.0 a 10.0.255.255). Este es un rango estándar para VPCs.
- `enable_dns_hostnames = true`: Permite asignar nombres DNS a las instancias dentro de la VPC. Necesario para que los servicios se encuentren por nombre.
- `enable_dns_support = true`: Habilita la resolución DNS dentro de la VPC. Sin esto, los servicios no pueden resolverse entre sí.

**¿Por qué es necesario?**
- Aísla tu infraestructura de otros proyectos
- Permite controlar el tráfico de red con Security Groups
- Base para todas las demás redes (subnets)

```hcl
# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "temporal-vpc" }
}
```

#### **aws_subnet.public** - Subnets Públicas

**¿Qué hace?**
Crea subredes públicas donde los recursos pueden tener IPs públicas y acceso directo a internet. Usamos 2 subnets en diferentes Availability Zones (AZs) para alta disponibilidad.

**Parámetros importantes:**
- `count = 2`: Crea 2 subnets (una en cada AZ). Esto es necesario para alta disponibilidad.
- `cidrsubnet(aws_vpc.main.cidr_block, 4, count.index)`: Divide el bloque `/16` en subnets `/20`.
  - `4` significa dividir en 16 subnets posibles
  - `count.index` (0, 1) crea subnets en 10.0.0.0/20 y 10.0.16.0/20
- `availability_zone`: Coloca cada subnet en una AZ diferente (us-east-1a, us-east-1b). Si una AZ falla, la otra sigue funcionando.
- `map_public_ip_on_launch = true`: Asigna automáticamente una IP pública a los recursos. Necesario para NAT Gateway y ALB.

**¿Por qué es necesario?**
- NAT Gateway necesita estar en una subnet pública para acceder a internet
- ALB debe estar en subnets públicas para recibir tráfico de internet
- Alta disponibilidad: si una AZ falla, la otra sigue operativa

```hcl
# Subnets públicas (para NAT Gateway y ALB)
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 4, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = { Name = "temporal-public-${count.index}" }
}
```

#### **aws_subnet.private** - Subnets Privadas

**¿Qué hace?**
Crea subredes privadas donde los recursos NO tienen IPs públicas directas. Los recursos aquí solo pueden acceder a internet a través del NAT Gateway.

**Parámetros importantes:**
- `count.index + 4`: Crea subnets en 10.0.64.0/20 y 10.0.80.0/20 (offset de 4 para no sobreponerse con las públicas)
- `map_public_ip_on_launch = false`: NO asigna IPs públicas. Los recursos están "ocultos" de internet directo.
- Misma distribución en AZs para alta disponibilidad.

**¿Por qué es necesario?**
- **Seguridad**: ECS tasks y RDS no están expuestos directamente a internet
- **Mejores prácticas**: Solo expones lo necesario (ALB) y mantienes el resto privado
- **Costo**: Puedes usar Fargate Spot en subnets privadas sin preocuparte por IPs públicas

```hcl
# Subnets privadas (para ECS tasks y RDS)
resource "aws_subnet" "private" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 4, count.index + 4)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false
  tags = { Name = "temporal-private-${count.index}" }
}
```

### 2.2 Configurar Internet Gateway y NAT Gateway

#### **aws_internet_gateway.gw** - Internet Gateway

**¿Qué hace?**
Crea un gateway que permite que los recursos en subnets públicas accedan directamente a internet y que internet acceda a ellos. Es como el "router" que conecta tu VPC con internet.

**Parámetros importantes:**
- `vpc_id`: Asocia el gateway a nuestra VPC. Solo puede haber un IGW por VPC.

**¿Por qué es necesario?**
- Permite que el ALB reciba tráfico de internet
- Permite que el NAT Gateway acceda a internet para actualizaciones, descargas, etc.
- Sin esto, los recursos en subnets públicas no pueden comunicarse con internet

**Cómo funciona:**
1. Recursos en subnets públicas con IP pública → Internet Gateway → Internet
2. Tráfico entrante de internet → Internet Gateway → Recursos en subnets públicas

```hcl
# Internet Gateway (para acceso público)
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "temporal-igw" }
}
```

#### **aws_eip.nat_ip** - Elastic IP para NAT Gateway

**¿Qué hace?**
Reserva una IP pública estática (Elastic IP) que no cambia. Esta IP se asigna al NAT Gateway.

**Parámetros importantes:**
- `domain = "vpc"`: Indica que la IP es para uso en VPC (no para EC2 clásico). Esto es obligatorio desde 2024.

**¿Por qué es necesario?**
- El NAT Gateway necesita una IP pública estática para funcionar
- Si la IP cambiara, los recursos privados perderían conectividad
- AWS cobra por Elastic IPs no asociadas, pero no si están en uso

```hcl
# NAT Gateway (para que subnets privadas accedan a internet)
resource "aws_eip" "nat_ip" {
  domain = "vpc"
  tags   = { Name = "temporal-nat-eip" }
}
```

#### **aws_nat_gateway.nat** - NAT Gateway

**¿Qué hace?**
Permite que recursos en subnets privadas (sin IPs públicas) accedan a internet de forma saliente. Hace Network Address Translation (NAT): los recursos privados usan la IP pública del NAT Gateway para salir a internet.

**Parámetros importantes:**
- `allocation_id`: La Elastic IP que reservamos. El NAT Gateway usará esta IP.
- `subnet_id`: Debe estar en una subnet pública (necesita acceso directo a internet vía IGW).

**¿Por qué es necesario?**
- ECS tasks en subnets privadas necesitan descargar imágenes Docker
- Necesitan acceder a APIs externas (Datadog, etc.)
- RDS puede necesitar actualizaciones
- **Seguridad**: Los recursos privados pueden salir a internet pero no pueden recibir conexiones entrantes directas

**Cómo funciona:**
1. ECS task en subnet privada quiere acceder a internet
2. El tráfico va al NAT Gateway (según la route table)
3. NAT Gateway traduce la IP privada a su IP pública
4. El tráfico sale a internet con la IP del NAT Gateway
5. Las respuestas vuelven al NAT Gateway que las reenvía al recurso privado

**Costo:** ~$32/mes + costos de datos transferidos. Es uno de los recursos más caros.

```hcl
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_ip.id
  subnet_id     = aws_subnet.public[0].id
  tags          = { Name = "temporal-nat" }
}
```

### 2.3 Configurar Route Tables

Las Route Tables definen cómo se enruta el tráfico de red. Son como las "tablas de enrutamiento" que dicen "si el destino es X, envía por Y".

#### **aws_route_table.public** - Route Table Pública

**¿Qué hace?**
Define las rutas para las subnets públicas. Le dice a los recursos en subnets públicas cómo llegar a internet.

**Parámetros importantes:**
- `route { cidr_block = "0.0.0.0/0" }`: Esta es la "ruta por defecto". `0.0.0.0/0` significa "todo el tráfico que no tenga otra ruta específica". Es como decir "todo lo demás, envíalo por aquí".
- `gateway_id`: Apunta al Internet Gateway. Significa "para ir a internet, usa el IGW".

**¿Por qué es necesario?**
- Sin esto, los recursos en subnets públicas no sabrían cómo llegar a internet
- El ALB necesita esta ruta para funcionar
- El NAT Gateway necesita esta ruta para acceder a internet

**Cómo funciona:**
- Recurso en subnet pública quiere acceder a `8.8.8.8` (Google DNS)
- Consulta la route table: "¿Cómo llego a 8.8.8.8?"
- La ruta `0.0.0.0/0` dice: "usa el Internet Gateway"
- El tráfico se envía al IGW y sale a internet

```hcl
# Route table pública (ruta a Internet Gateway)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = { Name = "temporal-public-rt" }
}
```

#### **aws_route_table_association.public_assoc** - Asociar Route Table a Subnets

**¿Qué hace?**
Asocia la route table pública con las subnets públicas. Esto "aplica" las rutas a esas subnets.

**Parámetros importantes:**
- `count = length(aws_subnet.public[*].id)`: Crea una asociación para cada subnet pública (2 en total).
- `subnet_id`: La subnet específica a asociar.
- `route_table_id`: La route table a aplicar.

**¿Por qué es necesario?**
- Sin esta asociación, las subnets no sabrían qué route table usar
- Cada subnet debe tener una route table asociada

```hcl
resource "aws_route_table_association" "public_assoc" {
  count          = length(aws_subnet.public[*].id)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
```

#### **aws_route_table.private** - Route Table Privada

**¿Qué hace?**
Define las rutas para las subnets privadas. Le dice a los recursos privados cómo acceder a internet (a través del NAT Gateway).

**Parámetros importantes:**
- `route { cidr_block = "0.0.0.0/0" }`: Misma ruta por defecto, pero apunta al NAT Gateway.
- `nat_gateway_id`: Apunta al NAT Gateway. Significa "para ir a internet, usa el NAT Gateway".

**¿Por qué es necesario?**
- Permite que ECS tasks descarguen imágenes Docker
- Permite que los servicios accedan a APIs externas
- Mantiene la seguridad: solo tráfico saliente, no entrante directo

**Cómo funciona:**
- ECS task en subnet privada quiere acceder a `registry-1.docker.io`
- Consulta la route table privada
- La ruta dice: "usa el NAT Gateway"
- El tráfico va al NAT Gateway que lo traduce y envía a internet

```hcl
# Route table privada (ruta a NAT Gateway)
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
```

### 2.4 Validar Red

```bash
terraform plan
```

**Qué verificar:**
- ✅ Debe planear crear VPC, subnets, gateways
- ✅ No debe haber errores de sintaxis
- ✅ CIDR blocks deben ser válidos

**Aplicar cambios:**
```bash
terraform apply
```

**Qué verificar después del apply:**
```bash
# Verificar VPC creada
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=temporal-vpc"

# Verificar subnets
aws ec2 describe-subnets --filters "Name=vpc-id,Values=<vpc-id>"

# Verificar NAT Gateway
aws ec2 describe-nat-gateways --filter "Name=tag:Name,Values=temporal-nat"
```

---

## 🗄️ Paso 3: Base de Datos RDS

### 3.1 Crear Security Group para RDS

En `sg.tf`:

```hcl
resource "aws_security_group" "rds_sg" {
  name        = "temporal-rds-sg"
  description = "Security group for Temporal RDS MySQL"
  vpc_id      = aws_vpc.main.id

  ingress {
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
}
```

### 3.2 Crear DB Subnet Group

#### **aws_db_subnet_group.temporal** - DB Subnet Group

**¿Qué hace?**
Define en qué subnets puede estar la instancia RDS. RDS requiere al menos 2 subnets en diferentes AZs para alta disponibilidad.

**Parámetros importantes:**
- `subnet_ids = aws_subnet.private[*].id`: Especifica las subnets privadas. El `[*]` significa "todas las subnets privadas" (2 en total, una en cada AZ).

**¿Por qué es necesario?**
- RDS requiere un DB Subnet Group para saber dónde puede crear la instancia
- Para alta disponibilidad, necesita subnets en al menos 2 AZs diferentes
- Las subnets deben ser privadas por seguridad

**Cómo funciona:**
- Cuando creas la instancia RDS, AWS elige una de las subnets del grupo
- Si habilitas Multi-AZ, crea una réplica en otra subnet del grupo (diferente AZ)
- Si una AZ falla, RDS puede fallover a la otra

```hcl
resource "aws_db_subnet_group" "temporal" {
  name       = "temporal-db-subnets"
  subnet_ids = aws_subnet.private[*].id  # Subnets privadas en diferentes AZs
  tags       = { Name = "temporal-db-subnets" }
}
```

### 3.3 Crear Instancia RDS MySQL

#### **aws_db_instance.temporal** - Instancia RDS MySQL

**¿Qué hace?**
Crea una instancia de base de datos MySQL 8.0 completamente administrada por AWS. Temporal usa MySQL para almacenar el estado de workflows, historial y metadata.

**Parámetros importantes:**

- `identifier`: Nombre único de la instancia. Se usa para referenciarla en comandos AWS CLI.
- `engine = "mysql"`: Motor de base de datos. Temporal soporta MySQL y PostgreSQL.
- `engine_version = "8.0"`: Versión específica de MySQL. 8.0 es estable y tiene buen rendimiento.
- `instance_class = "db.t3.micro"`: Tipo de instancia (CPU, RAM). `t3.micro` es el más pequeño y económico, suficiente para POC. En producción usar `db.t3.medium` o mayor.
- `allocated_storage = 20`: Espacio en GB. 20GB es suficiente para empezar. AWS puede auto-escalar hasta el límite.
- `storage_type = "gp2"`: Tipo de almacenamiento. `gp2` es SSD general purpose, balance entre costo y rendimiento.
- `db_name = "temporal"`: Nombre de la base de datos que se crea automáticamente. Temporal creará sus tablas aquí.
- `username/password`: Credenciales del usuario administrador. **⚠️ En producción, usar Secrets Manager exclusivamente.**
- `vpc_security_group_ids`: Security groups a aplicar. Controla quién puede acceder.
- `db_subnet_group_name`: El subnet group que definimos. RDS se creará en una de esas subnets.
- `skip_final_snapshot = true`: No crear snapshot al eliminar. Útil para POC, pero en producción debería ser `false`.
- `backup_retention_period = 7`: Mantener backups por 7 días. Permite point-in-time recovery.

**¿Por qué es necesario?**
- Temporal necesita una base de datos persistente para:
  - Almacenar el estado de workflows
  - Guardar el historial de ejecuciones
  - Metadata de task queues
  - Información de namespaces

**Cómo funciona:**
1. AWS crea la instancia en una subnet privada
2. Asigna una IP privada (ej: 10.0.64.50)
3. Crea la base de datos "temporal"
4. Temporal se conecta y crea sus tablas automáticamente
5. Los ECS tasks se conectan usando el endpoint de RDS

**Tiempo de creación:** 5-10 minutos. Es uno de los recursos que más tarda.

```hcl
resource "aws_db_instance" "temporal" {
  identifier             = "temporal-mysql-db"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"        # Más pequeño y económico
  allocated_storage      = 20                    # 20GB inicial
  storage_type           = "gp2"                 # SSD general purpose
  db_name                = "temporal"           # Base de datos que se crea
  username               = "admin"
  password               = "temporal-password-123" # ⚠️ En producción usar Secrets Manager
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.temporal.name
  skip_final_snapshot    = true                  # Para POC, en producción false
  backup_retention_period = 7                    # Backups por 7 días
  tags = { Name = "temporal-mysql-db" }
}
```

### 3.4 Configurar Secrets Manager

AWS Secrets Manager es un servicio para almacenar secretos (contraseñas, API keys, etc.) de forma segura y rotarlos automáticamente.

#### **aws_secretsmanager_secret.db_creds** - Secret para Credenciales de DB

**¿Qué hace?**
Crea un "contenedor" seguro para almacenar las credenciales de la base de datos. Es como una caja fuerte digital.

**Parámetros importantes:**
- `name`: Nombre del secret. Se usa para referenciarlo desde otros recursos.
- `recovery_window_in_days = 7`: Si eliminas el secret, AWS lo mantiene 7 días antes de borrarlo permanentemente. Permite recuperarlo si fue un error.

**¿Por qué es necesario?**
- **Seguridad**: Las credenciales no están hardcodeadas en código
- **Rotación**: Permite rotar contraseñas automáticamente (configuración avanzada)
- **Auditoría**: AWS registra quién accede al secret y cuándo
- **Cumplimiento**: Requisito para certificaciones de seguridad

**Cómo funciona:**
1. Almacena el secret encriptado en AWS
2. Solo recursos con permisos IAM pueden acceder
3. ECS tasks pueden leer el secret usando `valueFrom` en la task definition
4. AWS registra todos los accesos en CloudTrail

```hcl
resource "aws_secretsmanager_secret" "db_creds" {
  name                    = "temporal-db-credentials"
  description             = "Database credentials for Temporal"
  recovery_window_in_days = 7  # Ventana de recuperación si se elimina
}
```

#### **aws_secretsmanager_secret_version.db_creds** - Versión del Secret

**¿Qué hace?**
Almacena la versión actual de las credenciales. Secrets Manager soporta múltiples versiones, permitiendo rotación sin downtime.

**Parámetros importantes:**
- `secret_id`: Referencia al secret que creamos.
- `secret_string`: El valor del secret en formato JSON. Usamos `jsonencode()` para crear JSON válido.

**Estructura del JSON:**
- `HOST`: Endpoint de RDS (ej: `temporal-mysql-db.xxx.rds.amazonaws.com`)
- `PORT`: Puerto de MySQL (3306)
- `USERNAME`: Usuario de la base de datos
- `PASSWORD`: Contraseña (⚠️ en producción, generar automáticamente)

**¿Por qué JSON?**
- Formato estándar fácil de parsear
- Permite múltiples campos en un solo secret
- Compatible con la forma en que ECS lee secrets

**Cómo se usa:**
En la task definition de ECS, referencias el secret así:
```hcl
secrets = [{
  name      = "MYSQL_USER"
  valueFrom = "${aws_secretsmanager_secret.db_creds.arn}:USERNAME::"
}]
```
El `:USERNAME::` extrae solo el campo USERNAME del JSON.

```hcl
resource "aws_secretsmanager_secret_version" "db_creds" {
  secret_id = aws_secretsmanager_secret.db_creds.id
  secret_string = jsonencode({
    HOST     = aws_db_instance.temporal.address  # Endpoint de RDS
    PORT     = "3306"                            # Puerto MySQL
    USERNAME = "admin"                            # Usuario
    PASSWORD = "temporal-password-123"           # ⚠️ En producción generar automáticamente
  })
}
```

### 3.5 Validar Base de Datos

```bash
terraform apply
```

**Qué verificar:**
```bash
# Verificar instancia RDS
aws rds describe-db-instances --db-instance-identifier temporal-mysql-db

# Verificar secret
aws secretsmanager get-secret-value --secret-id temporal-db-credentials

# Probar conexión (desde una instancia EC2 o local si tienes acceso)
mysql -h <rds-endpoint> -u admin -p
```

**Nota importante:** La instancia RDS puede tardar 5-10 minutos en estar disponible.

---

## 🐳 Paso 4: Configuración de ECS

### 4.1 Crear ECS Cluster

#### **aws_ecs_cluster.temporal** - ECS Cluster

**¿Qué hace?**
Crea un clúster lógico que agrupa tus servicios ECS. Es como un "grupo de trabajo" donde ejecutas tus contenedores. El clúster en sí no tiene costo, solo pagas por los recursos que ejecutas dentro.

**Parámetros importantes:**
- `name`: Nombre del clúster. Se usa para referenciarlo al crear servicios y tasks.

**¿Por qué es necesario?**
- Es el contenedor lógico para todos tus servicios ECS
- Permite organizar y gestionar múltiples servicios juntos
- Necesario antes de crear cualquier servicio o task

**Cómo funciona:**
- El clúster es solo metadata (no consume recursos)
- Los servicios y tasks se "registran" en el clúster
- Puedes ver todos los servicios del clúster en la consola AWS

```hcl
resource "aws_ecs_cluster" "temporal" {
  name = "temporal-ecs-cluster"
}
```

#### **aws_ecs_cluster_capacity_providers.temporal** - Capacity Providers

**¿Qué hace?**
Configura qué tipos de capacidad (compute) están disponibles en el clúster. Define si usas Fargate normal, Fargate Spot, o EC2.

**Parámetros importantes:**
- `capacity_providers = ["FARGATE", "FARGATE_SPOT"]`: Habilita ambos tipos:
  - **FARGATE**: Servicio completamente administrado, sin gestión de servidores. Más caro pero más estable.
  - **FARGATE_SPOT**: Versión económica de Fargate. Puede ser interrumpido con 2 minutos de aviso, pero cuesta ~70% menos.

- `default_capacity_provider_strategy`: Estrategia por defecto cuando no especificas una en el servicio:
  - `capacity_provider = "FARGATE"`: Usa Fargate normal por defecto
  - `base = 0`: No garantiza ninguna tarea en Fargate normal
  - `weight = 1`: Si hay capacidad disponible, prefiere Fargate normal

**¿Por qué es necesario?**
- Permite usar Fargate Spot para ahorrar costos
- Puedes definir estrategias por servicio (algunos en Spot, otros en Fargate normal)
- Flexibilidad para balancear costo vs. disponibilidad

**Estrategia recomendada:**
- Servicios críticos (frontend): Fargate normal (más estable)
- Servicios menos críticos (workers): Fargate Spot (más económico)

```hcl
resource "aws_ecs_cluster_capacity_providers" "temporal" {
  cluster_name       = aws_ecs_cluster.temporal.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"  # Por defecto usa Fargate normal
    base              = 0          # No garantiza tareas
    weight            = 1          # Preferencia relativa
  }
}
```

### 4.2 Configurar IAM Roles

IAM (Identity and Access Management) controla quién puede hacer qué en AWS. Los roles IAM dan permisos a los servicios de AWS.

#### **aws_iam_role.ecs_execution_role** - Role de Ejecución de Tasks

**¿Qué hace?**
Crea un rol IAM que ECS usa para ejecutar tus tasks. Este rol tiene permisos para que ECS pueda hacer su trabajo (descargar imágenes, escribir logs, leer secrets).

**Parámetros importantes:**
- `name`: Nombre del rol. Debe ser único en tu cuenta AWS.
- `assume_role_policy`: Define quién puede "asumir" este rol. En este caso, solo el servicio `ecs-tasks.amazonaws.com` puede usarlo. Es como decir "solo ECS puede usar estos permisos".

**¿Por qué es necesario?**
- ECS necesita permisos para:
  - Descargar imágenes Docker de ECR
  - Escribir logs a CloudWatch
  - Leer secrets de Secrets Manager
  - Crear ENIs (Elastic Network Interfaces) para las tasks

**Cómo funciona:**
1. Cuando ECS inicia una task, "asume" este rol
2. El rol le da permisos temporales a ECS
3. ECS usa esos permisos para descargar imágenes, escribir logs, etc.
4. Cuando la task termina, los permisos se revocan

```hcl
# Role para ejecutar tasks (pull imágenes, escribir logs)
resource "aws_iam_role" "ecs_execution_role" {
  name               = "TemporalECSTaskExecutionRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"  # Permite "asumir" el rol
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"  # Solo ECS puede usar este rol
      }
    }]
  })
}
```

#### **aws_iam_role_policy_attachment.ecs_exec_attach** - Política Básica de ECS

**¿Qué hace?**
Adjunta una política administrada por AWS que da los permisos básicos que ECS necesita.

**Parámetros importantes:**
- `policy_arn`: ARN de la política de AWS. Esta política incluye:
  - Permisos para descargar imágenes de ECR
  - Permisos para escribir logs a CloudWatch
  - Permisos para crear ENIs

**¿Por qué es necesario?**
- Sin esto, ECS no puede descargar imágenes Docker
- No puede escribir logs
- Las tasks no pueden iniciar

```hcl
# Attach políticas necesarias
resource "aws_iam_role_policy_attachment" "ecs_exec_attach" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
```

#### **aws_iam_policy.ecs_exec_secrets_policy** - Política para Secrets Manager

**¿Qué hace?**
Crea una política personalizada que permite leer secrets de Secrets Manager y desencriptarlos con KMS.

**Parámetros importantes:**
- `name`: Nombre de la política personalizada.
- `policy`: Define los permisos:
  - `secretsmanager:GetSecretValue`: Permite leer el valor de un secret
  - `kms:Decrypt`: Permite desencriptar (los secrets están encriptados con KMS)

**¿Por qué es necesario?**
- Las task definitions referencian secrets usando `valueFrom`
- ECS necesita permisos para leer esos secrets
- Los secrets están encriptados, necesita `kms:Decrypt`

**⚠️ Nota de seguridad:**
- `Resource = "*"` permite acceder a todos los secrets. En producción, restringe a ARNs específicos.

```hcl
# Policy para Secrets Manager
resource "aws_iam_policy" "ecs_exec_secrets_policy" {
  name = "TemporalExecutionRoleSecretsPolicy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",  # Leer secrets
        "kms:Decrypt"                     # Desencriptar (secrets están encriptados)
      ]
      Resource = "*"  # ⚠️ En producción, restringir a ARNs específicos
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_exec_secrets_attach" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = aws_iam_policy.ecs_exec_secrets_policy.arn
}
```

#### **aws_iam_role.ecs_task_role** - Role de la Aplicación

**¿Qué hace?**
Crea un rol que la aplicación (dentro del contenedor) puede usar para acceder a servicios de AWS. Es diferente del execution role: el execution role es para ECS, el task role es para tu código.

**Parámetros importantes:**
- Similar al execution role, pero este es para que TU código acceda a AWS
- Por ahora está vacío (sin políticas adjuntas)
- Se puede usar si tus workflows necesitan acceder a S3, DynamoDB, etc.

**¿Por qué es necesario?**
- Si tus workflows de Temporal necesitan leer/escribir en S3
- Si necesitan acceder a otros servicios AWS
- Por ahora no lo usamos, pero es buena práctica tenerlo

```hcl
# IAM role for ECS Task (application role)
resource "aws_iam_role" "ecs_task_role" {
  name               = "TemporalECSTaskRole"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
}
# (Opcionalmente adjuntar políticas si el workflow de Temporal debe acceder a AWS)
```

### 4.3 Crear CloudWatch Log Groups

CloudWatch Logs es el servicio de AWS para almacenar y consultar logs de tus aplicaciones.

#### **aws_cloudwatch_log_group** - Log Groups

**¿Qué hace?**
Crea "contenedores" para almacenar logs de cada servicio. Cada servicio ECS escribe sus logs en su propio log group.

**Parámetros importantes:**
- `name`: Nombre del log group. El prefijo `/ecs/` es una convención común.
- `retention_in_days = 7`: Mantiene los logs por 7 días, luego los elimina automáticamente. Opciones: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653, o "Never".

**¿Por qué es necesario?**
- ECS necesita que el log group exista ANTES de que las tasks escriban logs
- Si no existe, las tasks fallan al iniciar
- Organiza los logs por servicio para fácil búsqueda

**Cómo funciona:**
1. ECS task escribe logs usando el driver `awslogs`
2. Los logs se envían a CloudWatch Logs
3. Se almacenan en el log group correspondiente
4. Puedes verlos en la consola AWS o con `aws logs tail`

**Costo:**
- Primeros 5GB/mes: gratis
- Después: ~$0.50 por GB almacenado
- Ingesta: ~$0.50 por GB ingerido

```hcl
resource "aws_cloudwatch_log_group" "temporal_frontend" {
  name              = "/ecs/temporal-frontend"  # Nombre del servicio
  retention_in_days = 7                          # Mantener 7 días
}

resource "aws_cloudwatch_log_group" "temporal_ui" {
  name              = "/ecs/temporal-ui"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "worker_service" {
  name              = "/ecs/worker-service"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "api_service" {
  name              = "/ecs/api-service"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "datadog_agent" {
  name              = "/ecs/datadog-agent"
  retention_in_days = 7
}
```

### 4.4 Validar ECS

```bash
terraform apply
```

**Qué verificar:**
```bash
# Verificar cluster creado
aws ecs describe-clusters --clusters temporal-ecs-cluster

# Verificar IAM roles
aws iam get-role --role-name TemporalECSTaskExecutionRole

# Verificar log groups
aws logs describe-log-groups --log-group-name-prefix "/ecs/temporal"
```

---

## ⚙️ Paso 5: Despliegue de Temporal

### 5.1 Task Definition: Temporal Frontend

Una **Task Definition** es como una "receta" que describe cómo ejecutar un contenedor. Define qué imagen usar, cuántos recursos necesita, qué puertos exponer, etc.

El frontend de Temporal es un servidor "all-in-one" que incluye:
- **Frontend service**: API gRPC que recibe requests de clientes
- **History service**: Almacena y recupera el historial de workflows
- **Matching service**: Asigna tareas a workers disponibles
- **Worker service**: Procesa tareas internas

#### **aws_ecs_task_definition.temporal_frontend** - Task Definition del Frontend

**¿Qué hace?**
Define la configuración para ejecutar el contenedor de Temporal Frontend. Es como un "template" que ECS usa para crear tasks.

**Parámetros importantes a nivel de Task:**

- `family = "temporal-frontend"`: Nombre de la familia. Cada vez que actualizas la task definition, AWS crea una nueva revisión, pero mantiene el mismo nombre de familia.
- `network_mode = "awsvpc"`: Usa el modo de red de VPC. Permite que cada task tenga su propia IP privada y esté en la VPC. **Requerido para Fargate.**
- `requires_compatibilities = ["FARGATE"]`: Especifica que esta task solo puede ejecutarse en Fargate (no en EC2).
- `cpu = 1024`: CPU en unidades (1024 = 1 vCPU). Opciones comunes: 256 (0.25 vCPU), 512 (0.5 vCPU), 1024 (1 vCPU), 2048 (2 vCPU), 4096 (4 vCPU).
- `memory = 2048`: Memoria en MB (2048 = 2 GB). Debe ser compatible con la CPU (ver [combinaciones válidas](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-cpu-memory-error.html)).
- `execution_role_arn`: Role que ECS usa para ejecutar la task (descargar imágenes, escribir logs).
- `task_role_arn`: Role que la aplicación dentro del contenedor puede usar.

**Parámetros importantes a nivel de Container:**

- `name = "temporal-frontend"`: Nombre del contenedor dentro de la task.
- `image = "temporalio/auto-setup:1.25.0"`: Imagen Docker a usar. `auto-setup` es una imagen especial que:
  - Configura automáticamente la base de datos (crea tablas)
  - Inicia todos los servicios necesarios
  - Perfecta para POCs y desarrollo
- `essential = true`: Si este contenedor falla, la task completa se detiene. Si es `false`, otros contenedores pueden seguir corriendo.
- `portMappings`: Puertos que el contenedor expone:
  - `7233`: Puerto gRPC para comunicación entre servicios Temporal
  - `8000`: Puerto Prometheus para métricas
- `environment`: Variables de entorno:
  - `SERVICES`: Qué servicios iniciar (frontend, history, matching, worker)
  - `DB`: Tipo de base de datos (mysql8)
  - `SKIP_SCHEMA_SETUP = false`: No saltar la creación de tablas (auto-setup las crea)
  - `NUM_HISTORY_SHARDS = 4`: Número de shards para el historial (afecta escalabilidad)
- `secrets`: Credenciales desde Secrets Manager:
  - `valueFrom`: ARN del secret + campo JSON (`:HOST::`, `:USERNAME::`, `:PASSWORD::`)
  - ECS lee el secret automáticamente y lo inyecta como variable de entorno
- `logConfiguration`: Configuración de logs:
  - `logDriver = "awslogs"`: Usa CloudWatch Logs
  - `awslogs-group`: Log group donde escribir
  - `awslogs-stream-prefix`: Prefijo para los streams (organiza logs por task)

**¿Por qué es necesario?**
- Define exactamente cómo ejecutar Temporal
- Permite versionar la configuración (cada cambio crea una nueva revisión)
- Reutilizable: múltiples services pueden usar la misma task definition

**Cómo funciona:**
1. Creas la task definition (esta es la "receta")
2. Creas un ECS Service que usa esta task definition
3. ECS crea tasks basadas en la definición
4. Cada task ejecuta el contenedor según la configuración

```hcl
resource "aws_ecs_task_definition" "temporal_frontend" {
  family                   = "temporal-frontend"
  network_mode             = "awsvpc"  # Requerido para Fargate
  requires_compatibilities = ["FARGATE"]
  cpu                      = 1024        # 1 vCPU
  memory                   = 2048        # 2 GB RAM
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "temporal-frontend"
      image     = "temporalio/auto-setup:1.25.0"  # Imagen con auto-configuración
      essential = true                            # Si falla, la task se detiene
      portMappings = [
        { containerPort = 7233, protocol = "tcp" }, # gRPC para comunicación
        { containerPort = 8000, protocol = "tcp" }  # Prometheus para métricas
      ]
      environment = [
        { name = "SERVICES", value = "frontend,history,matching,worker" },
        { name = "DB", value = "mysql8" },
        { name = "DB_PORT", value = "3306" },
        { name = "ENABLE_ES", value = "false" },  # Elasticsearch deshabilitado
        { name = "SKIP_SCHEMA_SETUP", value = "false" },  # Crear tablas automáticamente
        { name = "NUM_HISTORY_SHARDS", value = "4" }  # Shards para escalabilidad
      ]
      secrets = [
        {
          name      = "MYSQL_SEEDS"
          valueFrom = "${aws_secretsmanager_secret.db_creds.arn}:HOST::"
        },
        {
          name      = "MYSQL_USER"
          valueFrom = "${aws_secretsmanager_secret.db_creds.arn}:USERNAME::"
        },
        {
          name      = "MYSQL_PWD"
          valueFrom = "${aws_secretsmanager_secret.db_creds.arn}:PASSWORD::"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/temporal-frontend"
          awslogs-region        = "us-east-1"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}
```

### 5.2 Task Definition: Temporal UI

```hcl
resource "aws_ecs_task_definition" "temporal_ui" {
  family                   = "temporal-ui"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

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
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/temporal-ui"
          awslogs-region        = "us-east-1"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}
```

### 5.3 Configurar Service Discovery

Para que los servicios se encuentren entre sí:

```hcl
resource "aws_service_discovery_private_dns_namespace" "temporal_ns" {
  name        = "temporal"
  vpc         = aws_vpc.main.id
  description = "Private DNS namespace for Temporal services"
}

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
```

### 5.4 Crear ECS Services

Un **ECS Service** mantiene un número deseado de tasks ejecutándose. Si una task falla, el service la reemplaza automáticamente.

#### **aws_ecs_service.svc_frontend** - Service del Frontend

**¿Qué hace?**
Crea un servicio ECS que mantiene 1 task de Temporal Frontend ejecutándose continuamente. Si la task falla, ECS la reemplaza automáticamente.

**Parámetros importantes:**

- `name`: Nombre del servicio. Único dentro del clúster.
- `cluster`: Clúster donde ejecutar el servicio.
- `task_definition`: Task definition a usar. Puede ser ARN completo o solo familia:revisión.
- `desired_count = 1`: Número de tasks que el servicio debe mantener ejecutándose. Si una falla, ECS crea una nueva.
- `network_configuration`: Configuración de red:
  - `subnets`: Subnets donde ejecutar las tasks (privadas para seguridad)
  - `security_groups`: Security groups a aplicar a las tasks
  - `assign_public_ip = false`: No asignar IP pública (las tasks están en subnets privadas)
- `service_registries`: Registro en Service Discovery:
  - `registry_arn`: ARN del servicio de Service Discovery
  - Permite que otros servicios encuentren este servicio por nombre DNS
- `capacity_provider_strategy`: Estrategia de capacidad:
  - `capacity_provider = "FARGATE_SPOT"`: Usa Fargate Spot (más económico)
  - `weight = 1`: Preferencia relativa (si hay múltiples providers)
- `depends_on`: Dependencias. Espera a que RDS esté disponible antes de iniciar.

**¿Por qué es necesario?**
- **Alta disponibilidad**: Mantiene las tasks ejecutándose
- **Auto-recovery**: Si una task falla, la reemplaza automáticamente
- **Escalabilidad**: Puedes aumentar `desired_count` para escalar horizontalmente
- **Service Discovery**: Permite que otros servicios encuentren este servicio

**Cómo funciona:**
1. ECS crea la primera task según la task definition
2. Monitorea el estado de la task
3. Si la task falla o se detiene, ECS crea una nueva
4. Mantiene siempre `desired_count` tasks ejecutándose
5. Se registra en Service Discovery con el nombre `frontend.temporal`

**Diferencia entre Task Definition y Service:**
- **Task Definition**: La "receta" (qué ejecutar, cómo)
- **Service**: El "cocinero" que ejecuta la receta continuamente

```hcl
resource "aws_ecs_service" "svc_frontend" {
  name            = "temporal-frontend-svc"
  cluster         = aws_ecs_cluster.temporal.id
  task_definition = aws_ecs_task_definition.temporal_frontend.arn
  desired_count   = 1  # Mantener 1 task ejecutándose

  network_configuration {
    subnets          = aws_subnet.private[*].id  # Subnets privadas
    security_groups  = [aws_security_group.tasks_sg.id]
    assign_public_ip = false  # Sin IP pública (usa NAT Gateway para salir)
  }

  service_registries {
    registry_arn = aws_service_discovery_service.frontend_sd.arn
    # Registra este servicio como "frontend.temporal" en DNS
  }

  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"  # Usar Spot para ahorrar costos
    weight            = 1
  }

  depends_on = [aws_db_instance.temporal]  # Esperar a que RDS esté listo
}
```

### 5.5 Configurar Application Load Balancer

Un **Application Load Balancer (ALB)** distribuye el tráfico HTTP/HTTPS entre múltiples targets (en nuestro caso, tasks de ECS). También hace health checks y puede terminar SSL.

#### **aws_lb.temporal_ui** - Application Load Balancer

**¿Qué hace?**
Crea un load balancer de capa 7 (HTTP/HTTPS) que distribuye el tráfico entrante a las tasks de Temporal UI.

**Parámetros importantes:**

- `name`: Nombre del ALB. Se usa para identificarlo en la consola.
- `internal = false`: ALB público (puede recibir tráfico de internet). Si fuera `true`, solo sería accesible desde dentro de la VPC.
- `load_balancer_type = "application"`: Tipo Application Load Balancer (capa 7). También existe Network Load Balancer (capa 4).
- `security_groups`: Security groups a aplicar. Controla qué tráfico puede llegar al ALB.
- `subnets`: Subnets donde crear el ALB. **Deben ser públicas** para que sea accesible desde internet.

**¿Por qué es necesario?**
- **Punto de entrada único**: Un solo DNS para acceder a múltiples tasks
- **Alta disponibilidad**: Si una task falla, el ALB enruta a otras
- **Health checks**: Verifica que las tasks estén saludables
- **SSL termination**: Puede terminar SSL/TLS (configuración avanzada)

**Cómo funciona:**
1. El ALB obtiene un DNS público (ej: `temporal-ui-alb-xxx.us-east-1.elb.amazonaws.com`)
2. El tráfico de internet llega al ALB
3. El ALB verifica qué targets están saludables
4. Distribuye el tráfico entre los targets saludables
5. Si un target falla el health check, el ALB deja de enviarle tráfico

**Costo:** ~$16/mes base + costos de datos transferidos.

```hcl
resource "aws_lb" "temporal_ui" {
  name               = "TemporalUI-ALB"
  internal           = false  # Público (accesible desde internet)
  load_balancer_type = "application"  # ALB (capa 7)
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = aws_subnet.public[*].id  # Debe estar en subnets públicas
}
```

#### **aws_lb_target_group.ui_tg** - Target Group para UI

**¿Qué hace?**
Define un grupo de targets (tasks de ECS) a los que el ALB enrutará el tráfico. También configura health checks.

**Parámetros importantes:**

- `name`: Nombre del target group.
- `port = 8080`: Puerto donde el ALB enviará el tráfico (puerto 8080 = puerto donde Temporal UI escucha).
- `protocol = "HTTP"`: Protocolo a usar (HTTP o HTTPS).
- `target_type = "ip"`: Los targets son direcciones IP (Fargate usa IPs, no instancias EC2).
- `vpc_id`: VPC donde están los targets.
- `health_check`: Configuración de health checks:
  - `path = "/"`: Endpoint a verificar (el ALB hace GET a este path)
  - `interval = 30`: Verificar cada 30 segundos
  - `timeout = 5`: Timeout de 5 segundos por check
  - `healthy_threshold = 2`: Necesita 2 checks exitosos consecutivos para marcar como saludable
  - `unhealthy_threshold = 3`: Necesita 3 checks fallidos consecutivos para marcar como no saludable
  - `matcher = "200"`: Solo código HTTP 200 se considera saludable

**¿Por qué es necesario?**
- Define qué targets reciben el tráfico
- Health checks aseguran que solo se enrute a targets saludables
- Permite que el ALB sepa cuándo un target está listo o no

**Cómo funciona:**
1. El ALB hace health checks periódicos a cada target
2. Si el target responde con 200, se marca como saludable
3. El ALB solo enruta tráfico a targets saludables
4. Si un target falla, se marca como no saludable y se deja de enrutar tráfico
5. Cuando vuelve a responder, se marca como saludable de nuevo

```hcl
resource "aws_lb_target_group" "ui_tg" {
  name        = "tg-temporal-ui"
  port        = 8080  # Puerto donde Temporal UI escucha
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"  # Fargate usa IPs, no instancias EC2

  health_check {
    enabled             = true
    healthy_threshold   = 2     # 2 checks exitosos = saludable
    unhealthy_threshold = 3     # 3 checks fallidos = no saludable
    timeout             = 5    # Timeout de 5 segundos
    interval            = 30    # Cada 30 segundos
    path                = "/"  # Verificar el root path
    matcher             = "200"  # Solo código 200 es válido
  }
}
```

#### **aws_lb_listener.http** - Listener HTTP

**¿Qué hace?**
Define en qué puerto escucha el ALB y qué hacer con el tráfico entrante. Un listener "escucha" en un puerto y enruta el tráfico a un target group.

**Parámetros importantes:**

- `load_balancer_arn`: ARN del ALB donde crear el listener.
- `port = 80`: Puerto donde escuchar (80 = HTTP estándar).
- `protocol = "HTTP"`: Protocolo HTTP (para HTTPS usar 443 y un certificado).
- `default_action`: Acción por defecto (qué hacer con el tráfico):
  - `type = "forward"`: Enviar el tráfico a un target group
  - `target_group_arn`: Target group destino

**¿Por qué es necesario?**
- Sin listeners, el ALB no sabe qué hacer con el tráfico entrante
- Define las reglas de enrutamiento
- Puedes tener múltiples listeners (ej: HTTP en 80, HTTPS en 443)

**Cómo funciona:**
1. Cliente hace request a `http://alb-dns:80/`
2. El listener en puerto 80 recibe el request
3. Aplica la acción por defecto: forward al target group
4. El target group selecciona un target saludable
5. El tráfico se enruta a ese target

```hcl
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.temporal_ui.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"  # Enviar a target group
    target_group_arn = aws_lb_target_group.ui_tg.arn
  }
}
```

### 5.6 Validar Despliegue de Temporal

```bash
terraform apply
```

**Qué verificar:**
```bash
# Verificar servicios ECS
aws ecs describe-services \
  --cluster temporal-ecs-cluster \
  --services temporal-frontend-svc temporal-ui-svc \
  --query 'services[*].[serviceName,runningCount,desiredCount,status]' \
  --output table

# Verificar tasks ejecutándose
aws ecs list-tasks \
  --cluster temporal-ecs-cluster \
  --service-name temporal-frontend-svc

# Verificar logs
aws logs tail /ecs/temporal-frontend --follow

# Verificar ALB
aws elbv2 describe-load-balancers \
  --names TemporalUI-ALB
```

**Acceder a Temporal UI:**
```bash
# Obtener URL del ALB
terraform output temporal_ui_url

# Abrir en navegador
# Deberías ver la interfaz de Temporal
```

**Tiempo estimado:** 5-10 minutos para que los servicios estén completamente operativos.

---

## 📊 Paso 6: Integración con Datadog

### 6.1 Configurar Datadog API Key

En `secrets.tf` o `datadog.tf`:

```hcl
resource "aws_secretsmanager_secret" "datadog_api_key" {
  name                    = "datadog-api-key"
  description             = "DataDog API Key para monitoreo"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "datadog_api_key" {
  secret_id     = aws_secretsmanager_secret.datadog_api_key.id
  secret_string = "TU_DATADOG_API_KEY_AQUI"
}
```

**Obtener API Key de Datadog:**
1. Ve a Datadog → Organization Settings → API Keys
2. Crea una nueva API Key o copia una existente
3. Reemplaza `TU_DATADOG_API_KEY_AQUI` con tu key

### 6.2 Configurar Agente Datadog como Sidecar

En `datadog.tf`:

```hcl
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
      { name = "DD_DOGSTATSD_NON_LOCAL_TRAFFIC", value = "true" },
      { name = "DD_DOGSTATSD_PORT", value = "8125" },
      { name = "DD_AUTODISCOVERY_ENABLED", value = "true" },
      { name = "DD_EXTRA_CONFIG_PROVIDERS", value = "docker" }
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
        awslogs-group         = "/ecs/datadog-agent"
        awslogs-region        = "us-east-1"
        awslogs-stream-prefix = "datadog"
      }
    }
  }
}
```

### 6.3 Agregar Agente Datadog a Task Definitions

Modifica `temporal_frontend` task definition para incluir el agente:

```hcl
container_definitions = jsonencode([
  local.datadog_agent_container,  # Agregar esto primero
  {
    name      = "temporal-frontend"
    # ... resto de la configuración
  }
])
```

### 6.4 Configurar Métricas de Temporal

Agrega variables de entorno a Temporal para enviar métricas:

```hcl
locals {
  temporal_datadog_env = [
    { name = "STATSD_ADDRESS", value = "127.0.0.1:8125" },
    { name = "STATSD_ENABLED", value = "true" },
    { name = "PROMETHEUS_ENDPOINT", value = "0.0.0.0:8000" },
    { name = "TEMPORAL_EMIT_METRICS", value = "true" },
    { name = "TEMPORAL_METRICS_PREFIX", value = "temporal" }
  ]
}
```

Y agrega estas variables al contenedor de Temporal:

```hcl
environment = concat([
  { name = "SERVICES", value = "frontend,history,matching,worker" },
  # ... otras variables
], local.temporal_datadog_env)
```

### 6.5 Configurar Prometheus Scraping

Para que Datadog scrapee métricas de Prometheus, agrega Docker labels:

```hcl
dockerLabels = {
  "com.datadoghq.ad.check_names"  = jsonencode(["openmetrics"])
  "com.datadoghq.ad.init_configs" = jsonencode([{}])
  "com.datadoghq.ad.instances" = jsonencode([{
    prometheus_url = "http://127.0.0.1:8000/metrics"
    namespace      = "temporal"
    metrics        = ["temporal_*", "go_*", "process_*"]
    tags           = ["service:temporal-server", "environment:production"]
  }])
}
```

### 6.6 Aplicar Configuración Datadog

```bash
terraform apply
```

**Qué verificar:**
```bash
# Verificar que el agente Datadog esté corriendo
aws ecs describe-tasks \
  --cluster temporal-ecs-cluster \
  --tasks <task-arn> \
  --query 'tasks[0].containers[*].[name,lastStatus]' \
  --output table

# Verificar logs del agente
aws logs tail /ecs/datadog-agent --follow

# Buscar mensajes como:
# "dogstatsd-udp: starting to listen on [::]:8125"
# "Scheduling check openmetrics:temporal:..."
```

**En Datadog:**
1. Ve a **Metrics** → **Explorer**
2. Busca métricas que empiecen con `temporal.*`
3. Deberías ver métricas después de 2-5 minutos

---

## ✅ Paso 7: Validación y Pruebas

### 7.1 Verificar Servicios ECS

```bash
# Estado de todos los servicios
aws ecs describe-services \
  --cluster temporal-ecs-cluster \
  --services temporal-frontend-svc temporal-ui-svc temporal-worker-svc temporal-api-svc \
  --query 'services[*].[serviceName,runningCount,desiredCount,status]' \
  --output table
```

**Qué verificar:**
- ✅ `runningCount` debe ser igual a `desiredCount`
- ✅ `status` debe ser `ACTIVE`
- ✅ No debe haber errores en los eventos

### 7.2 Verificar Temporal UI

```bash
# Obtener URL
ALB_URL=$(terraform output -raw temporal_ui_url)
echo "Temporal UI: $ALB_URL"

# Verificar que responde
curl -I $ALB_URL
```

**Qué verificar:**
- ✅ Debe responder con HTTP 200
- ✅ Debe mostrar la interfaz de Temporal
- ✅ No debe haber errores 500

### 7.3 Ejecutar Workflows de Prueba

Crea un script `ejecutar-5-workflows.sh`:

```bash
#!/bin/bash
ALB_DNS=$(terraform output -raw alb_dns_name)
API_URL="http://${ALB_DNS}:8080"

# Ejecutar 5 workflows
for i in {1..5}; do
  curl -X POST "${API_URL}/workflows/start" \
    -H "Content-Type: application/json" \
    -d "{
      \"workflowId\": \"test-workflow-${i}\",
      \"input\": {
        \"message\": \"Workflow de prueba ${i}\"
      }
    }"
  sleep 2
done
```

**Qué verificar:**
- ✅ Workflows deben iniciarse correctamente
- ✅ Deben aparecer en Temporal UI
- ✅ Deben completarse exitosamente

### 7.4 Verificar Métricas en Datadog

**En Datadog UI:**

1. **Metrics Explorer:**
   - Ve a **Metrics** → **Explorer**
   - Busca: `temporal.workflow.started`
   - Filtra por: `service:temporal-server`

2. **Dashboards:**
   - Importa el dashboard desde `datadog-dashboard-temporal.json`
   - Deberías ver gráficos de workflows, activities y latencias

3. **Logs:**
   - Ve a **Logs** → **Explorer**
   - Filtra por: `service:temporal-server`
   - Deberías ver logs de Temporal

**Qué verificar:**
- ✅ Métricas aparecen después de ejecutar workflows
- ✅ Gráficos muestran datos
- ✅ No hay errores en los logs del agente

### 7.5 Verificar Logs

```bash
# Logs de Temporal Frontend
aws logs tail /ecs/temporal-frontend --follow

# Logs del agente Datadog
aws logs tail /ecs/datadog-agent --follow

# Buscar errores
aws logs filter-log-events \
  --log-group-name /ecs/temporal-frontend \
  --filter-pattern "ERROR" \
  --max-items 10
```

---

## 🔧 Troubleshooting

### Problema: Servicios ECS no inician

**Síntomas:**
- `runningCount` es 0
- Tasks fallan inmediatamente

**Soluciones:**
```bash
# Ver eventos del servicio
aws ecs describe-services \
  --cluster temporal-ecs-cluster \
  --services temporal-frontend-svc \
  --query 'services[0].events[:5]'

# Ver logs de la task
aws logs tail /ecs/temporal-frontend --since 10m

# Verificar que RDS esté disponible
aws rds describe-db-instances \
  --db-instance-identifier temporal-mysql-db \
  --query 'DBInstances[0].DBInstanceStatus'
```

### Problema: Temporal UI muestra error 500

**Síntomas:**
- UI carga pero muestra error interno
- Logs muestran errores de conexión

**Soluciones:**
```bash
# Verificar que frontend esté corriendo
aws ecs describe-services \
  --cluster temporal-ecs-cluster \
  --services temporal-frontend-svc \
  --query 'services[0].runningCount'

# Verificar service discovery
aws servicediscovery get-service \
  --id <service-id>

# Verificar conectividad desde UI a frontend
# Revisar logs de temporal-ui
aws logs tail /ecs/temporal-ui --since 10m | grep -i error
```

### Problema: Métricas no aparecen en Datadog

**Síntomas:**
- Agente Datadog está corriendo
- No hay métricas en Datadog

**Soluciones:**
```bash
# Verificar logs del agente
aws logs tail /ecs/datadog-agent --since 10m | grep -i "openmetrics\|error"

# Verificar que el check esté programado
# Buscar: "Scheduling check openmetrics"

# Verificar que Temporal esté exponiendo métricas
# Desde dentro del contenedor (si tienes acceso):
curl http://127.0.0.1:8000/metrics

# Verificar configuración de StatsD
aws ecs describe-task-definition \
  --task-definition temporal-frontend \
  --query 'taskDefinition.containerDefinitions[?name==`temporal-frontend`].environment[?name==`STATSD_ADDRESS`]'
```

### Problema: Workflows no se ejecutan

**Síntomas:**
- Workflows se crean pero no avanzan
- Workers no procesan tareas

**Soluciones:**
```bash
# Verificar que worker service esté corriendo
aws ecs describe-services \
  --cluster temporal-ecs-cluster \
  --services temporal-worker-svc

# Verificar logs del worker
aws logs tail /ecs/worker-service --since 10m

# Verificar conectividad del worker al frontend
# Buscar errores de conexión en logs
```

---

## 📈 Métricas Clave a Monitorear

### Métricas de Temporal

1. **Workflows:**
   - `temporal.workflow.started` - Workflows iniciados
   - `temporal.workflow.completed` - Workflows completados
   - `temporal.workflow.failed` - Workflows fallidos
   - `temporal.workflow.execution_time` - Tiempo de ejecución

2. **Activities:**
   - `temporal.activity.started` - Activities iniciadas
   - `temporal.activity.completed` - Activities completadas
   - `temporal.activity.execution_latency` - Latencia de ejecución

3. **Task Queues:**
   - `temporal.task_queue.depth` - Profundidad de cola
   - `temporal.task_queue.throughput` - Throughput
   - `temporal.task_queue.latency` - Latencia

### Métricas de Infraestructura

1. **ECS:**
   - CPU utilization por task
   - Memory utilization por task
   - Task count

2. **RDS:**
   - CPU utilization
   - Database connections
   - Read/Write latency

---

## 🎯 Resumen y Próximos Pasos

### Lo que hemos logrado

✅ Infraestructura completa en AWS usando Terraform  
✅ Temporal desplegado en ECS Fargate  
✅ Integración con Datadog para monitoreo  
✅ Métricas de workflows y activities visibles  
✅ Dashboard personalizado en Datadog  

### Próximos pasos recomendados

1. **Producción:**
   - Usar Secrets Manager para todas las credenciales
   - Habilitar SSL/TLS en el ALB
   - Configurar auto-scaling para los servicios
   - Implementar backup automático de RDS

2. **Monitoreo:**
   - Configurar alertas en Datadog
   - Crear más dashboards específicos
   - Implementar SLOs (Service Level Objectives)

3. **Seguridad:**
   - Restringir Security Groups
   - Usar VPC Endpoints para AWS services
   - Implementar WAF en el ALB

---

## 📚 Recursos Adicionales

- [Documentación de Temporal](https://docs.temporal.io/)
- [Documentación de AWS ECS](https://docs.aws.amazon.com/ecs/)
- [Documentación de Datadog](https://docs.datadoghq.com/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
