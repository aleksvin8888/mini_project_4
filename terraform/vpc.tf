
################################################# VPC ##################################################################

# Custom VPC
resource "aws_vpc" "custom_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "Custom VPC"
  }
}

# Інтернет-шлюз для публічних підмереж
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.custom_vpc.id

  tags = {
    Name = "Internet Gateway"
  }
}

# Таблиця маршрутів для публічних підмереж
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.custom_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "Public Route Table"
  }
}

# Таблиця маршрутів для приватних підмереж
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.custom_vpc.id

  tags = {
    Name = "Private Route Table"
  }
}

# Публічні підмережі
resource "aws_subnet" "public_subnets" {
  count             = length(data.aws_availability_zones.available.names)
  vpc_id            = aws_vpc.custom_vpc.id
  cidr_block        = cidrsubnet(aws_vpc.custom_vpc.cidr_block, 4, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "Public Subnet ${count.index + 1}"
  }
}

# Приватні підмережі
resource "aws_subnet" "private_subnets" {
  count             = length(data.aws_availability_zones.available.names)
  vpc_id            = aws_vpc.custom_vpc.id
  cidr_block        = cidrsubnet(aws_vpc.custom_vpc.cidr_block, 4, count.index + length(data.aws_availability_zones.available.names))
  availability_zone = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "Private Subnet ${count.index + 1}"
  }
}

# Асоціація публічних підмереж з таблицею маршрутів
resource "aws_route_table_association" "public_subnets" {
  count          = length(aws_subnet.public_subnets)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public.id
}

# Асоціація приватних підмереж з таблицею маршрутів
resource "aws_route_table_association" "private_subnets" {
  count          = length(aws_subnet.private_subnets)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private.id
}

# Дані про доступні зони
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC Endpoint для ECR API
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id       = aws_vpc.custom_vpc.id
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
  vpc_id       = aws_vpc.custom_vpc.id
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
  vpc_id           = aws_vpc.custom_vpc.id
  service_name     = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [aws_route_table.private.id]

  tags = {
    Name = "S3 Gateway Endpoint"
  }
}

# VPC Endpoint для CloudWatch Logs
resource "aws_vpc_endpoint" "cloudwatch_logs" {
  vpc_id       = aws_vpc.custom_vpc.id
  service_name = "com.amazonaws.${var.region}.logs"
  vpc_endpoint_type = "Interface"

  security_group_ids = [aws_security_group.logs_endpoint_sg.id]
  subnet_ids         = aws_subnet.private_subnets[*].id

  private_dns_enabled = true

  tags = {
    Name = "CloudWatch Logs Endpoint"
  }
}
