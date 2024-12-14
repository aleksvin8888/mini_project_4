
################################################# VPC ##################################################################

# Отримання Default VPC
data "aws_vpc" "default" {
  default = true
}

# Отримання існуючих Internet Gateway у Default VPC
data "aws_internet_gateway" "default" {
  filter {
    name   = "attachment.vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Отримання існуючих підмереж у Default VPC
data "aws_subnets" "default_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Дані про доступні зони
data "aws_availability_zones" "available" {
  state = "available"
}

# Отримання деталей підмереж
data "aws_subnet" "default_subnets" {
  for_each = toset(data.aws_subnets.default_subnets.ids)

  id = each.value
}

# Локальні змінні
locals {
  # Основний CIDR-блок VPC
  vpc_cidr_block = data.aws_vpc.default.cidr_block

  # Список CIDR-блоків існуючих підмереж
  used_cidr_blocks = [for subnet in data.aws_subnet.default_subnets : subnet.cidr_block]

  # Визначення вільних CIDR-блоків
  available_cidr_blocks = [
    for i in range(8) : cidrsubnet(local.vpc_cidr_block, 4, i)
    if !contains(local.used_cidr_blocks, cidrsubnet(local.vpc_cidr_block, 4, i))
  ]

  # Безпечне визначення публічних CIDR
  new_public_cidrs = length(local.available_cidr_blocks) >= 2 ? slice(local.available_cidr_blocks, 0, 2) : []

  # Безпечне визначення приватних CIDR
  new_private_cidrs = length(local.available_cidr_blocks) >= 4 ? slice(local.available_cidr_blocks, 2, 4) : []
}

################################################# Public Subnets ##################################################################

# Публічні підмережі
resource "aws_subnet" "public_subnets" {
  count             = length(local.new_public_cidrs)
  vpc_id            = data.aws_vpc.default.id
  cidr_block        = local.new_public_cidrs[count.index]
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true

  tags = {
    Name = "Public Subnet ${count.index + 1}"
  }
}

# Таблиця маршрутів для публічних підмереж
resource "aws_route_table" "public" {
  vpc_id = data.aws_vpc.default.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = data.aws_internet_gateway.default.id
  }

  tags = {
    Name = "Public Route Table"
  }
}

# Асоціація публічних підмереж з таблицею маршрутів
resource "aws_route_table_association" "public_subnets" {
  count          = length(aws_subnet.public_subnets)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public.id
}

################################################# Private Subnets ##################################################################

# Приватні підмережі
resource "aws_subnet" "private_subnets" {
  count             = length(local.new_private_cidrs)
  vpc_id            = data.aws_vpc.default.id
  cidr_block        = local.new_private_cidrs[count.index]
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = false

  tags = {
    Name = "Private Subnet ${count.index + 1}"
  }
}

# Таблиця маршрутів для приватних підмереж
resource "aws_route_table" "private" {
  vpc_id = data.aws_vpc.default.id

  tags = {
    Name = "Private Route Table"
  }
}

# Асоціація приватних підмереж з таблицею маршрутів
resource "aws_route_table_association" "private_subnets" {
  count          = length(aws_subnet.private_subnets)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private.id
}

# VPC Endpoint для ECR API
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id       = data.aws_vpc.default.id
  service_name = "com.amazonaws.${var.region}.ecr.api"
  vpc_endpoint_type = "Interface"

  security_group_ids = [aws_security_group.ecr_endpoint_sg.id]
  subnet_ids         = aws_subnet.private_subnets[*].id

  private_dns_enabled = true
  tags = {
    Name = "ECR API Endpoint"
  }
}

# VPC Endpoint для ECR Docker Registry
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id       = data.aws_vpc.default.id
  service_name = "com.amazonaws.${var.region}.ecr.dkr"
  vpc_endpoint_type = "Interface"

  security_group_ids = [aws_security_group.ecr_endpoint_sg.id]
  subnet_ids         = aws_subnet.private_subnets[*].id

  private_dns_enabled = true
  tags = {
    Name = "ECR Docker Registry Endpoint"
  }
}

# VPC Endpoint для S3 (для доступу до шарів Docker-образів)
resource "aws_vpc_endpoint" "s3" {
  vpc_id           = data.aws_vpc.default.id
  service_name     = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [aws_route_table.private.id]

  tags = {
    Name = "S3 Gateway Endpoint"
  }
}

# VPC Endpoint для CloudWatch Logs
resource "aws_vpc_endpoint" "cloudwatch_logs" {
  vpc_id       = data.aws_vpc.default.id
  service_name = "com.amazonaws.${var.region}.logs"
  vpc_endpoint_type = "Interface"

  security_group_ids = [aws_security_group.logs_endpoint_sg.id]
  subnet_ids         = aws_subnet.private_subnets[*].id

  private_dns_enabled = true

  tags = {
    Name = "CloudWatch Logs Endpoint"
  }
}
