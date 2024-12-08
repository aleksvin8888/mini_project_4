
######################################### Створює ECS cluster ##########################################################

resource "aws_ecs_cluster" "api_cluster" {
  name = var.cluster_name
}

################## Створює репозиторії в Amazon ECR для зберігання образів Docker ######################################
resource "aws_ecr_repository" "rds_api_repo" {
  name = "rds-api-repo"
  image_scanning_configuration {
    scan_on_push = true
  }
  tags = {
    Name = "RDS API Repository"
  }
}

resource "aws_ecr_repository" "redis_api_repo" {
  name = "redis-api-repo"
   image_scanning_configuration {
    scan_on_push = true
  }
  tags = {
    Name = "Redis API Repository"
  }
}


output "ecr_rds_api_registry" {
  value = aws_ecr_repository.rds_api_repo.repository_url
  description = "ECR registry URL for RDS API"
}

output "ecr_redis_api_registry" {
  value = aws_ecr_repository.redis_api_repo.repository_url
  description = "ECR registry URL for Redis API"
}

##################################### Створює task_definition ##########################################################

resource "aws_ecs_task_definition" "rds_api_task" {
  family = "rds-api-task"
  network_mode = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu = "256"
  memory = "512"

  container_definitions = jsonencode([
    {
      name = var.rds_container_name ,
      image = "${aws_ecr_repository.rds_api_repo.repository_url}:latest"

      essential = true
      portMappings = [
        {
          containerPort = 8000  # Контейнер слухатиме запити на цьому порту.
          protocol = "tcp"
        }
      ]
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:8000/test_connection/ || exit 1"]
        interval    = 30    # Перевіряти кожні 30 секунд
        timeout     = 5     # Таймаут перевірки - 5 секунд
        retries     = 3     # Спробувати 3 рази перед поміткою як unhealthy
        startPeriod = 10    # Дочекайтесь 10 секунд після запуску перед перевірками
      }
      environment = [
        {
          name  = "DB_NAME"
          value = var.db_name
        },
        {
          name  = "DB_USER"
          value = var.db_user
        },
        {
          name  = "DB_PASSWORD"
          value = var.db_password
        },
        {
          name  = "DB_HOST"
          value = aws_db_instance.pg_database.endpoint
        },
        {
          name  = "DB_PORT"
          value = "5432"
        },
        {
          name  = "CORS_ALLOWED_ORIGINS"
          value = "https://${aws_cloudfront_distribution.frontend_distribution.domain_name}"
        }
      ]
    }
  ])

  # IAM-роль, яку ECS використовує для виконання завдання (наприклад, доступ до ECR для завантаження образів).
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  #  IAM-роль для контейнера. Наприклад, для доступу до RDS чи інших AWS сервісів.
  task_role_arn = aws_iam_role.ecs_task_role.arn
}


resource "aws_ecs_task_definition" "redis_api_task" {
  family       = "redis-api-task"
  network_mode = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu          = "256"
  memory       = "512"

  container_definitions = jsonencode([
    {
      name      = var.redis_container_name,
      image     = "${aws_ecr_repository.redis_api_repo.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 8001
          protocol      = "tcp"
        }
      ]
       healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:8001/test_connection/ || exit 1"]
        interval    = 30    # Перевіряти кожні 30 секунд
        timeout     = 5     # Таймаут перевірки - 5 секунд
        retries     = 3     # Спробувати 3 рази перед поміткою як unhealthy
        startPeriod = 10    # Дочекайтесь 10 секунд після запуску перед перевірками
      }
       environment = [
        {
          name  = "REDIS_HOST"
          value = aws_elasticache_cluster.redis_cache.cache_nodes[0].address
        },
        {
          name  = "REDIS_PORT"
          value = "6379"
        },
        {
          name  = "REDIS_DB"
          value = "0" # База даних Redis (за замовчуванням 0)
        },
        {
          name  = "CORS_ALLOWED_ORIGINS"
          value = "https://${aws_cloudfront_distribution.frontend_distribution.domain_name}"
        }
      ]
    }
  ])
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn      = aws_iam_role.ecs_task_role.arn
}

######################################### ECS сервіси ##################################################################

resource "aws_ecs_service" "rds_api_service" {
  depends_on = [aws_alb_listener.https_listener]
  name            = var.rds_service_name
  cluster         = aws_ecs_cluster.api_cluster.id
  task_definition = aws_ecs_task_definition.rds_api_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets = aws_subnet.private_subnets[*].id
    security_groups = [aws_security_group.rds_api_sg.id]
  }

  load_balancer {
    target_group_arn = aws_alb_target_group.rds_target_group.arn
    container_name   = var.rds_container_name
    container_port   = 8000
  }
}

resource "aws_ecs_service" "redis_api_service" {
  depends_on = [aws_alb_listener.https_listener]
  name            = var.redis_service_name
  cluster         = aws_ecs_cluster.api_cluster.id
  task_definition = aws_ecs_task_definition.redis_api_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets = aws_subnet.private_subnets[*].id
    security_groups = [aws_security_group.redis_api_sg.id]
  }

  load_balancer {
    target_group_arn = aws_alb_target_group.redis_target_group.arn
    container_name   = var.redis_container_name
    container_port   = 8001
  }
}

################################################# ALB ##################################################################

resource "aws_alb" "api_alb" {
  name     = "api-load-balancer"
  internal = false
  security_groups = [aws_security_group.alb_sg.id]
  subnets  = aws_subnet.public_subnets[*].id
}

resource "aws_alb_target_group" "rds_target_group" {
  name     = "rds-target-group"
  port     = 8000
  protocol = "HTTP"
  vpc_id   = aws_vpc.custom_vpc.id
  target_type = "ip"

  health_check {
    path                = "/test_connection/" # URL-адреса для перевірки
    interval            = 30        # Перевіряти кожні 30 секунд
    timeout             = 5         # Таймаут перевірки
    healthy_threshold   = 2         # 2 успішні перевірки - healthy
    unhealthy_threshold = 3         # 3 невдалі перевірки - unhealthy
    matcher             = "200"     # Очікуваний код відповіді
  }
}

resource "aws_alb_target_group" "redis_target_group" {
  name     = "redis-target-group"
  port     = 8001
  protocol = "HTTP"
  vpc_id   = aws_vpc.custom_vpc.id
  target_type = "ip"

  health_check {
    path                = "/test_connection/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
    matcher             = "200"
  }
}

# HTTP Listener
resource "aws_alb_listener" "http_listener" {
  load_balancer_arn = aws_alb.api_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      protocol = "HTTPS"
      port     = "443"
      status_code = "HTTP_301"
    }
  }
}

# HTTPS Listener
resource "aws_alb_listener" "https_listener" {
   depends_on        = [aws_acm_certificate_validation.frontend_cert_validation]
  load_balancer_arn = aws_alb.api_alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate_validation.frontend_cert_validation.certificate_arn

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "404 Not Found"
      status_code  = "404"
    }
  }
}

# Правила маршрутизації
resource "aws_alb_listener_rule" "rds_rule" {
  listener_arn = aws_alb_listener.https_listener.arn
  priority     = 1

  condition {
    host_header {
      values = ["api-rds.${var.main_domain_name}"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.rds_target_group.arn
  }
}

resource "aws_alb_listener_rule" "redis_rule" {
  listener_arn = aws_alb_listener.https_listener.arn
  priority     = 2

  condition {
    host_header {
      values = ["api-redis.${var.main_domain_name}"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.redis_target_group.arn
  }
}


######################################### Postgres RDS #################################################################

resource "aws_db_instance" "pg_database" {
  allocated_storage = 20                             # Розмір сховища (ГБ)
  engine = "postgres"
  engine_version = "17.1"
  instance_class = "db.t3.micro"
  db_name = var.db_name
  username = var.db_user
  password = var.db_password
  publicly_accessible = false                       # Не робити базу доступною ззовні
  skip_final_snapshot = true                        # Пропустити створення знімка під час видалення
  vpc_security_group_ids = [aws_security_group.rds_db_sg.id]
  db_subnet_group_name = aws_db_subnet_group.rds-subnet-group.name
  port = 5432
}

resource "aws_db_subnet_group" "rds-subnet-group" {
  name       = "rds-subnet-group"
  description = "Subnet group for RDS database"
  subnet_ids = aws_subnet.private_subnets[*].id

  tags = {
    Name = "RDS Subnet Group"
  }
}

######################################### REDIS  #######################################################################

resource "aws_elasticache_cluster" "redis_cache" {
  cluster_id           = "simple-redis-cluster"
  engine               = "redis"
  engine_version       = "7.0"
  node_type            = "cache.t2.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.redis-subnet-group.name
  security_group_ids   = [aws_security_group.redis_sg.id]
}

resource "aws_elasticache_subnet_group" "redis-subnet-group" {
  name       = "elasticache-subnet-group"
  description = "Subnet group for Elastic cache Redis"
  subnet_ids = aws_subnet.private_subnets[*].id

  tags = {
    Name = "Elasticache Subnet Group"
  }
}

######################################### Security groups ##############################################################

#  SG  для  бази даних RDS
resource "aws_security_group" "rds_db_sg" {
  name_prefix = "rds-sg"
  vpc_id      = aws_vpc.custom_vpc.id

  ingress {
    from_port = 5432
    to_port   = 5432
    protocol  = "tcp"
    security_groups = [aws_security_group.rds_api_sg.id] # трафік тільки з контейнера rds_api
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#  SG  для  REDIS
resource "aws_security_group" "redis_sg" {
  name        = "redis-sg"
  description = "Security group for Redis"
  vpc_id      = aws_vpc.custom_vpc.id

  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    security_groups = [aws_security_group.redis_api_sg.id] # Доступ тільки від ECS контейнерів
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] # Дозволяє вихідний трафік на всі адреси
  }

  tags = {
    Name = "Redis Security Group"
  }
}

#  SG  для контейнера rds
resource "aws_security_group" "rds_api_sg" {
  name_prefix = "rds-api-sg-"
  vpc_id      = aws_vpc.custom_vpc.id

  ingress {
    from_port = 8000
    to_port   = 8000
    protocol  = "tcp"
    security_groups = [aws_security_group.alb_sg.id] # вхідний  трафік тільки від ALB
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "RDS API Security Group"
  }
}

#  SG  для  контейнера  redis
resource "aws_security_group" "redis_api_sg" {
  name_prefix = "redis-api-sg-"
  vpc_id      = aws_vpc.custom_vpc.id

  ingress {
    from_port = 8001
    to_port   = 8001
    protocol  = "tcp"
    security_groups = [aws_security_group.alb_sg.id] # вхідний  трафік тільки від ALB
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Redis API Security Group"
  }
}

# SG  для  ALB
resource "aws_security_group" "alb_sg" {
  name_prefix = "alb-sg-"
  vpc_id      = aws_vpc.custom_vpc.id

  ingress {
    from_port = 80                # HTTP
    to_port  = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 443               # HTTPS
    to_port  = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ALB Security Group"
  }
}

resource "aws_security_group" "ecr_endpoint_sg" {
  vpc_id = aws_vpc.custom_vpc.id

  ingress {
    from_port   = 443
    to_port     = 443
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
    Name = "ECR Endpoint Security Group"
  }
}

################################################# IMA & roles & policy #################################################

# ECS Task Execution Role
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Роль для доступу завдань ECS до інших сервісів (Task Role)
resource "aws_iam_role" "ecs_task_role" {
  name = "ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Політика для доступу до ECR та виконання ECS Task
resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Політика для доступу до ECR
resource "aws_iam_role_policy_attachment" "ecs_task_ecr_access" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Політика для ECS Task Role для доступу до RDS
resource "aws_iam_role_policy_attachment" "ecs_task_rds_access" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonRDSDataFullAccess"
}

# Політика для ECS Task Role для доступу до CloudWatch Logs
resource "aws_iam_role_policy_attachment" "ecs_task_logs_access" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

# Політика для ECS Task Role для доступу до Redis
resource "aws_iam_role_policy_attachment" "ecs_task_redis_access" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonElastiCacheFullAccess"
}

resource "aws_vpc_endpoint_policy" "ecr_policy" {
  vpc_endpoint_id = aws_vpc_endpoint.ecr_api.id

  policy = jsonencode({
    Statement = [
      {
        Sid       = "AllowECRAccess",
        Effect    = "Allow",
        Principal = "*",
        Action    = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:GetAuthorizationToken"
        ],
        Resource  = "*"
      }
    ]
  })
}

