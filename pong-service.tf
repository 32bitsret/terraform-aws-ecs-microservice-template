locals {
  pong_microservice = "pong-service"
  pong_service_port = 8080
}

resource "aws_ecr_repository" "pong_repo" {
  name                 = "${local.pong_microservice}-${var.environment}"
  image_tag_mutability = "IMMUTABLE"

  tags = {
    repository = "https://github.com/Softnet/API"
  }
}


resource "aws_ecr_repository_policy" "pong_repo_policy" {
  repository = aws_ecr_repository.pong_repo.name
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


resource "aws_cloudwatch_log_group" "pong_logs" {
  name              = "/fargate/service/${local.pong_microservice}-${var.environment}"
  retention_in_days = var.logs_retention_in_days
}

resource "aws_ecs_cluster" "pong_cluster" {
  name = "pong-service-${var.environment}-cluster"
}

resource "aws_ecs_task_definition" "pong_service_task_defination" {
  family                   = "${local.pong_microservice}-${var.environment}-service"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  memory                   = "2048"
  cpu                      = "1024"
  execution_role_arn       = "${aws_iam_role.ecsTaskExecutionRole.arn}"
  container_definitions    = jsonencode(
  [
    {
      "name": "${local.pong_microservice}-${var.environment}-service"
      "image": "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${aws_ecr_repository.pong_repo.name}",
      "memory": 512,
      "cpu": 256,
      "essential": true,
      "portMappings": [
        {
          "containerPort": local.pong_service_port,
          "hostPort": local.pong_service_port
        }
      ],
      "logConfiguration": {
          "logDriver": "awslogs",
          "options": {
            "awslogs-group": "/fargate/service/${local.pong_microservice}-${var.environment}",
            "awslogs-region": "${var.region}",
            "awslogs-stream-prefix": "ecs"
          }
      },
      "environment": [
          {
            "name": "PING_SERVICE_FQDN",
            "value": "http://${aws_service_discovery_service.ping_service.name}.${aws_service_discovery_private_dns_namespace.main.name}:8080"
          },
          {
            "name": "PORT",
            "value": "${tostring(local.pong_service_port)}"
          },
      ],
    }
  ])
}

resource "aws_ecs_service" "pong_service" {
  name            = "${local.pong_microservice}-${var.environment}-service"
  cluster         = aws_ecs_cluster.pong_cluster.id
  task_definition = aws_ecs_task_definition.pong_service_task_defination.arn
  launch_type     = "FARGATE"
  service_registries {
    registry_arn   = aws_service_discovery_service.pong_service.arn
  }
  network_configuration {
    subnets          = ["${aws_default_subnet.default_subnet_a.id}", "${aws_default_subnet.default_subnet_b.id}", "${aws_default_subnet.default_subnet_c.id}"]
    assign_public_ip = false
    security_groups  = ["${aws_security_group.private-traffic-sg.id}"]
  }

  desired_count = var.replicas

  load_balancer {
    target_group_arn = "${aws_lb_target_group.pong_service_lb_target_group.arn}"
    container_name   = "${aws_ecs_task_definition.pong_service_task_defination.family}"
    container_port   = local.pong_service_port
  }

  lifecycle {
    ignore_changes = [task_definition]
  }
}

resource "aws_s3_bucket" "pong_service_elb_logs" {
  bucket = "${local.pong_microservice}-${var.environment}-lb-logs"
}

resource "aws_s3_bucket_policy" "pong_service_allow_elb_logging" {
  bucket = aws_s3_bucket.pong_service_elb_logs.id
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
      "Resource": "${aws_s3_bucket.pong_service_elb_logs.arn}/AWSLogs/*",
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
#   name = "${local.pong_microservice}-${var.environment}"

#   vpc {
#     vpc_id = aws_default_vpc.default_vpc.id
#   }
# }

# resource "aws_route53_record" "pong_service-elb" {
#   zone_id = aws_route53_zone.private.id
#   name    = "${local.pong_microservice}"
#   type    = "A"

#   alias {
#     name                   = aws_alb.pong_service_load_balancer.dns_name
#     zone_id                = aws_alb.pong_service_load_balancer.zone_id
#     evaluate_target_health = false
#   }
# }

resource "aws_alb" "pong_service_load_balancer" {
  name               = "${local.pong_microservice}-${var.environment}-nlb"
  load_balancer_type = "network"
  subnets = [
    "${aws_default_subnet.default_subnet_a.id}",
    "${aws_default_subnet.default_subnet_b.id}",
    "${aws_default_subnet.default_subnet_c.id}"
  ]
  internal = false
}

resource "aws_lb_listener" "pong_service_listener" {
  load_balancer_arn = "${aws_alb.pong_service_load_balancer.arn}" 
  port              = "80"
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.pong_service_lb_target_group.arn}"
  }
}

resource "aws_lb_target_group" "pong_service_lb_target_group" {
  name        = "${local.pong_microservice}-${var.environment}-tg"
  port        = 80
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = "${aws_default_vpc.default_vpc.id}"
}


resource "aws_service_discovery_service" "pong_service" {
  name = "${local.pong_microservice}-${var.environment}"

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

resource "aws_api_gateway_resource" "pong_service_base_resource" {
  rest_api_id = aws_api_gateway_rest_api.gw_service_api.id
  parent_id   = aws_api_gateway_rest_api.gw_service_api.root_resource_id
  path_part   = "pong"
}

resource "aws_api_gateway_resource" "pong_service_resource" {
  rest_api_id = aws_api_gateway_rest_api.gw_service_api.id
  parent_id   = aws_api_gateway_resource.pong_service_base_resource.id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "pong_service_method" {
  rest_api_id   = aws_api_gateway_rest_api.gw_service_api.id
  resource_id   = aws_api_gateway_resource.pong_service_resource.id
  http_method   = "ANY"
  authorization = "NONE"
  request_parameters = {
    "method.request.path.proxy" = true
  }
}

resource "aws_api_gateway_integration" "pong_service_integration" {
  rest_api_id = aws_api_gateway_rest_api.gw_service_api.id
  resource_id = aws_api_gateway_resource.pong_service_resource.id
  http_method = aws_api_gateway_method.pong_service_method.http_method

  type                    = "HTTP_PROXY"
  uri                     = "http://${aws_alb.pong_service_load_balancer.dns_name}/{proxy}"
  integration_http_method = aws_api_gateway_method.pong_service_method.http_method
  passthrough_behavior    = "WHEN_NO_MATCH"

  request_parameters = {
    "integration.request.path.proxy" = "method.request.path.proxy"
  }
  
  connection_type         = "VPC_LINK"
  connection_id           = aws_api_gateway_vpc_link.pong_service_link.id

  depends_on = [ aws_alb.pong_service_load_balancer, aws_api_gateway_vpc_link.pong_service_link ]
}

resource "aws_api_gateway_vpc_link" "pong_service_link" {
  name        = "${local.pong_microservice}-${var.environment}"
  description = "VPC link for Pong service"
  target_arns = [
    aws_alb.pong_service_load_balancer.arn,
    ]
  depends_on = [ aws_alb.pong_service_load_balancer ]
}

resource "aws_api_gateway_method" "pong_service_base_method" {
  rest_api_id   = aws_api_gateway_rest_api.gw_service_api.id
  resource_id   = aws_api_gateway_resource.pong_service_base_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "pong_service_base_integration" {
  rest_api_id = aws_api_gateway_rest_api.gw_service_api.id
  resource_id = aws_api_gateway_resource.pong_service_base_resource.id
  http_method = aws_api_gateway_method.pong_service_base_method.http_method

  type                    = "HTTP_PROXY"
  uri                     = "http://${aws_alb.pong_service_load_balancer.dns_name}"
  integration_http_method = aws_api_gateway_method.pong_service_base_method.http_method
  passthrough_behavior    = "WHEN_NO_MATCH"

  connection_type         = "VPC_LINK"
  connection_id           = aws_api_gateway_vpc_link.pong_service_link.id

  depends_on = [ aws_alb.pong_service_load_balancer, aws_api_gateway_vpc_link.pong_service_link  ]
}

output "pong_service_endpoint" {
  description = "Endpoint for pong service"
  value       = "http://${aws_service_discovery_service.pong_service.name}.${aws_service_discovery_private_dns_namespace.main.name}"
}

output "pong_service_discovery_service_arn" {
  description = "The ARN of the service discovery service for the pong service"
  value       = aws_service_discovery_service.pong_service.arn
}

output "pong_SERVICE_AWS_ECR_ACCOUNT_URL" {
  description = "pong Service Docker Image"
  value = aws_ecr_repository.pong_repo.repository_url
}