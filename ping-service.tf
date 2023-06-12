locals {
  ping_microservice = "ping-service"
  ping_service_port = 8080
}

resource "aws_ecr_repository" "ping_repo" {
  name                 = "${local.ping_microservice}-${var.environment}"
  image_tag_mutability = "IMMUTABLE"

  tags = {
    repository = "https://github.com/Softnet/API"
  }
}


resource "aws_ecr_repository_policy" "ping_repo_policy" {
  repository = aws_ecr_repository.ping_repo.name
  policy = jsonencode(
  {
    "Version": "2008-10-17",
    "Statement": [
      {
            "Sid": "Core api",
            "Effect": "Allow",
            "Principal": "*",
            "Action": [
                "ecr:GetAuthorizationToken",
                "ecr:GetDownloadUrlForLayer",
                "ecr:BatchGetImage",
                "ecr:BatchCheckLayerAvailability",
                "ecr:PutImage",
                "ecr:InitiateLayerUpload",
                "ecr:UploadLayerPart",
                "ecr:CompleteLayerUpload",
                "ecr:DescribeRepositories",
                "ecr:GetRepositoryPolicy",
                "ecr:ListImages",
                "ecr:DeleteRepository",
                "ecr:BatchDeleteImage",
                "ecr:SetRepositoryPolicy",
                "ecr:DeleteRepositoryPolicy"
            ]
      }
    ]
  })
}


resource "aws_cloudwatch_log_group" "ping_logs" {
  name              = "/fargate/service/${local.ping_microservice}-${var.environment}"
  retention_in_days = var.logs_retention_in_days
}

resource "aws_ecs_cluster" "ping_cluster" {
  name = "ping-service-${var.environment}-cluster"
}

resource "aws_ecs_task_definition" "ping_service_task_defination" {
  family                   = "${local.ping_microservice}-${var.environment}-service"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  memory                   = "2048"
  cpu                      = "1024"
  execution_role_arn       = "${aws_iam_role.ecsTaskExecutionRole.arn}"
  container_definitions    = jsonencode(
  [
    {
      "name": "${local.ping_microservice}-${var.environment}-service"
      "image": "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${aws_ecr_repository.ping_repo.name}",
      "memory": 512,
      "cpu": 256,
      "essential": true,
      "portMappings": [
        {
          "containerPort": local.ping_service_port,
          "hostPort": local.ping_service_port
        }
      ],
      "logConfiguration": {
          "logDriver": "awslogs",
          "options": {
            "awslogs-group": "/fargate/service/${local.ping_microservice}-${var.environment}",
            "awslogs-region": "${var.region}",
            "awslogs-stream-prefix": "ecs"
          }
      },
      "environment": [
          {
            "name": "PONG_SERVICE_FQDN",
            "value": "http://${aws_service_discovery_service.pong_service.name}.${aws_service_discovery_private_dns_namespace.main.name}:8080"
          },
          {
            "name": "PORT",
            "value": "${tostring(local.ping_service_port)}"
          },
      ],
    }
  ])
}

# resource "aws_appautoscaling_target" "ping_service_app_scale_target" {
#   service_namespace  = "ecs"
#   resource_id        = "service/${aws_ecs_cluster.ping_cluster.name}/${aws_ecs_service.ping_service.name}"
#   scalable_dimension = "ecs:service:DesiredCount"
#   max_capacity       = var.ecs_autoscale_max_instances
#   min_capacity       = var.ecs_autoscale_min_instances
# }

resource "aws_ecs_service" "ping_service" {
  name            = "${local.ping_microservice}-${var.environment}-service"
  cluster         = aws_ecs_cluster.ping_cluster.id
  task_definition = aws_ecs_task_definition.ping_service_task_defination.arn
  launch_type     = "FARGATE"
  service_registries {
    registry_arn   = aws_service_discovery_service.ping_service.arn
  }
  network_configuration {
    subnets          = ["${aws_default_subnet.default_subnet_a.id}", "${aws_default_subnet.default_subnet_b.id}", "${aws_default_subnet.default_subnet_c.id}"]
    assign_public_ip = true # Providing our containers with public IPs
    security_groups  = ["${aws_security_group.private-traffic-sg.id}"]
  }

  desired_count = var.replicas

  load_balancer {
    target_group_arn = "${aws_lb_target_group.ping_service_lb_target_group.arn}"
    container_name   = "${aws_ecs_task_definition.ping_service_task_defination.family}"
    container_port   = local.ping_service_port
  }

  lifecycle {
    ignore_changes = [task_definition]
  }
}

resource "aws_s3_bucket" "ping_service_elb_logs" {
  bucket = "${local.ping_microservice}-${var.environment}-lb-logs"
}

resource "aws_s3_bucket_policy" "ping_service_allow_elb_logging" {
  bucket = aws_s3_bucket.ping_service_elb_logs.id
  policy = <<POLICY
{
  "Id": "Policy",
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:PutObject"
      ],
      "Effect": "Allow",
      "Resource": "${aws_s3_bucket.ping_service_elb_logs.arn}/AWSLogs/*",
      "Principal": {
        "AWS": [
          "${data.aws_elb_service_account.main.arn}"
        ]
      }
    }
  ]
}
POLICY
}

# resource "aws_route53_zone" "private" {
#   name = "${local.ping_microservice}-${var.environment}"

#   vpc {
#     vpc_id = aws_default_vpc.default_vpc.id
#   }
# }

# resource "aws_route53_record" "ping_service-elb" {
#   zone_id = aws_route53_zone.private.id
#   name    = "${local.ping_microservice}"
#   type    = "A"

#   alias {
#     name                   = aws_alb.ping_service_load_balancer.dns_name
#     zone_id                = aws_alb.ping_service_load_balancer.zone_id
#     evaluate_target_health = false
#   }
# }

resource "aws_alb" "ping_service_load_balancer" {
  name               = "${local.ping_microservice}-${var.environment}-lb"
  load_balancer_type = "application"
  subnets = [
    "${aws_default_subnet.default_subnet_a.id}",
    "${aws_default_subnet.default_subnet_b.id}",
    "${aws_default_subnet.default_subnet_c.id}"
  ]
  security_groups = ["${aws_security_group.public_traffic_sg.id}"]

  access_logs {
    bucket   = aws_s3_bucket.ping_service_elb_logs.bucket
    enabled = true
  }
}

resource "aws_lb_listener" "ping_service_listener" {
  load_balancer_arn = "${aws_alb.ping_service_load_balancer.arn}" 
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.ping_service_lb_target_group.arn}"
  }
}

resource "aws_lb_target_group" "ping_service_lb_target_group" {
  name        = "${local.ping_microservice}-${var.environment}-tg"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = "${aws_default_vpc.default_vpc.id}"
  health_check {
    matcher = "200,301,302"
    path = "/"
  }
}


resource "aws_service_discovery_service" "ping_service" {
  name = "${local.ping_microservice}-${var.environment}"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    # routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
  depends_on = [ aws_service_discovery_private_dns_namespace.main ]
}

resource "aws_api_gateway_resource" "ping_service_base_resource" {
  rest_api_id = aws_api_gateway_rest_api.gw_service_api.id
  parent_id   = aws_api_gateway_rest_api.gw_service_api.root_resource_id
  path_part   = "ping"
}

resource "aws_api_gateway_resource" "ping_service_resource" {
  rest_api_id = aws_api_gateway_rest_api.gw_service_api.id
  parent_id   = aws_api_gateway_resource.ping_service_base_resource.id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "ping_service_method" {
  rest_api_id   = aws_api_gateway_rest_api.gw_service_api.id
  resource_id   = aws_api_gateway_resource.ping_service_resource.id
  http_method   = "ANY"
  authorization = "NONE"
  request_parameters = {
    "method.request.path.proxy" = true
  }
}

resource "aws_api_gateway_integration" "ping_service_integration" {
  rest_api_id = aws_api_gateway_rest_api.gw_service_api.id
  resource_id = aws_api_gateway_resource.ping_service_resource.id
  http_method = aws_api_gateway_method.ping_service_method.http_method

  type                    = "HTTP_PROXY"
  uri                     = "http://${aws_alb.ping_service_load_balancer.dns_name}/{proxy}"
  integration_http_method = aws_api_gateway_method.ping_service_method.http_method
  passthrough_behavior    = "WHEN_NO_MATCH"

  request_parameters = {
    "integration.request.path.proxy" = "method.request.path.proxy"
  }

  depends_on = [ aws_alb.ping_service_load_balancer ]
}

resource "aws_api_gateway_method" "ping_service_base_method" {
  rest_api_id   = aws_api_gateway_rest_api.gw_service_api.id
  resource_id   = aws_api_gateway_resource.ping_service_base_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "ping_service_base_integration" {
  rest_api_id = aws_api_gateway_rest_api.gw_service_api.id
  resource_id = aws_api_gateway_resource.ping_service_base_resource.id
  http_method = aws_api_gateway_method.ping_service_base_method.http_method

  type                    = "HTTP_PROXY"
  uri                     = "http://${aws_alb.ping_service_load_balancer.dns_name}"
  integration_http_method = aws_api_gateway_method.ping_service_base_method.http_method
  passthrough_behavior    = "WHEN_NO_MATCH"

  depends_on = [ aws_alb.ping_service_load_balancer ]
}

output "ping_service_endpoint" {
  description = "Endpoint for pong service"
  value       = "http://${aws_service_discovery_service.pong_service.name}.${aws_service_discovery_private_dns_namespace.main.name}"
}

output "ping_service_discovery_service_arn" {
  description = "The ARN of the service discovery service for the ping service"
  value       = aws_service_discovery_service.ping_service.arn
}

output "PING_SERVICE_AWS_ECR_ACCOUNT_URL" {
  description = "Ping Service Docker Image"
  value = aws_ecr_repository.ping_repo.repository_url
}