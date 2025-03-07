resource "aws_cloudwatch_log_group" "ecs_log_group" {
  name              = "/ecs/api-processamento"
  retention_in_days = 7
}

resource "aws_ecs_task_definition" "api_task" {
  family                   = "api-processamento-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "2048"
  memory                   = "4096"

  container_definitions = jsonencode([
    {
      name         = "api-container-processamento"
      image        = var.ecr_image
      essential    = true
      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "AWS_ACCESS_KEY_ID"
          value = var.aws_access_key_id
        },
        {
          name  = "AWS_SECRET_ACCESS_KEY"
          value = var.aws_secret_access_key
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options   = {
          awslogs-group         = "/ecs/api-processamento"
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  execution_role_arn = var.lab_role
}

resource "aws_security_group" "ecs_service_sg" {
  name   = "ecs-processamento-service-sg"
  vpc_id = var.vpc_id

  ingress {
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
}

resource "aws_security_group" "alb_sg" {
  name   = "fiap-x-alb-sg"
  vpc_id = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "api_alb" {
  name                       = "api-processamento-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb_sg.id]
  subnets                    = var.subnet_ids
  enable_deletion_protection = false

  enable_cross_zone_load_balancing = true
}

resource "aws_lb_listener" "api_listener" {
  load_balancer_arn = aws_lb.api_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "404 Not Found"
      status_code  = "404"
    }
  }
}

resource "aws_lb_target_group" "api_target_group" {
  name        = "api-processamento-target-group"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/health"
    interval            = 60
    timeout             = 10
    healthy_threshold   = 3
    unhealthy_threshold = 3
    matcher             = "200"
  }
}

resource "aws_lb_listener_rule" "processamento_rule" {
  listener_arn = aws_lb_listener.api_listener.arn
  priority     = 30

  condition {
    path_pattern {
      values = ["/api/v1/processamento*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api_target_group.arn
  }
}

resource "aws_ecs_service" "api_service" {
  name            = "api-processamento-service"
  cluster         = var.ecs_cluster_arn
  task_definition = aws_ecs_task_definition.api_task.arn
  launch_type     = "FARGATE"
  desired_count   = 2

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.ecs_service_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api_target_group.arn
    container_name   = "api-container-processamento"
    container_port   = 8080
  }
}

resource "aws_appautoscaling_target" "ecs_autoscaling_target" {
  max_capacity       = 6
  min_capacity       = 2
  resource_id        = "service/fiapx-cluster/${aws_ecs_service.api_service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "scale_up_policy" {
  name               = "scale-up"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.ecs_autoscaling_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_autoscaling_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_autoscaling_target.service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_lower_bound = 80
      scaling_adjustment          = 1
    }
  }
}

resource "aws_appautoscaling_policy" "scale_down_policy" {
  name               = "scale-down"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.ecs_autoscaling_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_autoscaling_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_autoscaling_target.service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_upper_bound = 0
      scaling_adjustment          = -1
    }
  }
}

resource "aws_db_subnet_group" "fiapx_subnet_group" {
  name       = "fiapx-subnet-group"
  subnet_ids = var.subnet_ids
}

resource "aws_security_group" "fiapx_db_sg" {
  name        = "fiapx-db-sg"
  description = "Acesso ao RDS PostgreSQL"
  vpc_id      = var.vpc_id

  ingress {
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
}

resource "aws_db_instance" "fiapx_db_produto" {
  db_name             = "fiapx_db"
  identifier          = "fiapx-db"
  allocated_storage   = 20
  engine              = "mysql"
  engine_version      = "8.0.39"
  instance_class      = "db.t3.micro"
  username            = "root"
  password            = "root1234"
  skip_final_snapshot = true

  vpc_security_group_ids = [aws_security_group.fiapx_db_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.fiapx_subnet_group.name
}

resource "aws_api_gateway_resource" "processamento_resource" {
  rest_api_id = var.api_gateway_id
  parent_id   = var.api_gateway_root_resource_id
  path_part   = "processamento"
}

resource "aws_api_gateway_resource" "user_id_resource" {
  rest_api_id = var.api_gateway_id
  parent_id   = aws_api_gateway_resource.processamento_resource.id
  path_part   = "{userId}"
}

resource "aws_api_gateway_resource" "download_resource" {
  rest_api_id = var.api_gateway_id
  parent_id   = aws_api_gateway_resource.processamento_resource.id
  path_part   = "download"
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name            = "CognitoUserPoolAPIAuthorizer"
  type            = "COGNITO_USER_POOLS"
  rest_api_id     = var.api_gateway_id
  provider_arns   = [var.cognito_user_pool_arn]
}

resource "aws_api_gateway_method" "processamento_get_method" {
  rest_api_id   = var.api_gateway_id
  resource_id   = aws_api_gateway_resource.user_id_resource.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id

  request_parameters = {
    "method.request.path.userId" = true
  }

  depends_on = [
    aws_api_gateway_authorizer.cognito_authorizer
  ]
}

resource "aws_api_gateway_method" "processamento_get_download_method" {
  rest_api_id   = var.api_gateway_id
  resource_id   = aws_api_gateway_resource.download_resource.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id

  request_parameters = {
    "method.request.querystring.chaveZip" = true
  }

  depends_on = [
    aws_api_gateway_authorizer.cognito_authorizer
  ]
}

resource "aws_api_gateway_integration" "processamento_get_integration" {
  rest_api_id             = var.api_gateway_id
  resource_id             = aws_api_gateway_resource.user_id_resource.id
  http_method             = aws_api_gateway_method.processamento_get_method.http_method
  integration_http_method = "GET"
  type                    = "HTTP_PROXY"
  uri                     = "http://${aws_lb.api_alb.dns_name}/api/v1/processamento/{userId}"

  request_parameters = {
    "integration.request.path.userId" = "method.request.path.userId"
  }
}

resource "aws_api_gateway_integration" "processamento_get_download_integration" {
  rest_api_id             = var.api_gateway_id
  resource_id             = aws_api_gateway_resource.download_resource.id
  http_method             = aws_api_gateway_method.processamento_get_download_method.http_method
  integration_http_method = "GET"
  type                    = "HTTP_PROXY"
  uri                     = "http://${aws_lb.api_alb.dns_name}/api/v1/processamento/download"

  request_parameters = {
    "integration.request.querystring.chaveZip" = "method.request.querystring.chaveZip"
  }
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = var.api_gateway_id

  depends_on = [
    aws_api_gateway_integration.processamento_get_integration,
    aws_api_gateway_method.processamento_get_method,
    aws_api_gateway_integration.processamento_get_download_integration,
    aws_api_gateway_method.processamento_get_download_method
  ]
}