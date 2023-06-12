terraform {
  cloud {
    organization = "EverydayMoney"
    workspaces {
      name = "main-prod"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4.3"
    }
    acme = {
      source = "vancluever/acme"
      version = "2.10.0"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_elb_service_account" "main" {}
data "aws_partition" "current" {}

provider "aws" {
  region = var.region
}

resource "aws_default_vpc" "default_vpc" {
}

resource "aws_default_subnet" "default_subnet_a" {
  availability_zone = "${var.region}a"
}

resource "aws_default_subnet" "default_subnet_b" {
  availability_zone = "${var.region}b"
}

resource "aws_default_subnet" "default_subnet_c" {
  availability_zone = "${var.region}c"
}

resource "aws_service_discovery_private_dns_namespace" "main" {
  name        = "${var.app}-${var.environment}-service"
  description = "Private DNS namespace for microservices"
  vpc         = aws_default_vpc.default_vpc.id 
}

resource "aws_api_gateway_rest_api" "gw_service_api" {
  name        = "${var.app}-${var.environment}-gateway"
  description = "API Gateway"
}

resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on  = [
    aws_api_gateway_integration.ping_service_integration, 
    aws_api_gateway_integration.pong_service_integration,
    ]
  rest_api_id = aws_api_gateway_rest_api.gw_service_api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_integration.ping_service_integration.id,
      aws_api_gateway_integration.ping_service_base_integration.id,
      aws_api_gateway_integration.pong_service_base_integration.id,
      aws_api_gateway_integration.pong_service_integration.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  variables = {
    "environment" = var.environment
  }
}

resource "aws_api_gateway_stage" "main" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.gw_service_api.id
  stage_name    = "${var.environment}"

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.apigateway.arn
    format = "$context.identity.sourceIp $context.identity.caller $context.identity.user [$context.requestTime] \"$context.httpMethod $context.resourcePath $context.protocol\" $context.status $context.responseLength $context.requestId"
  }
  depends_on = [aws_api_gateway_account.account]
}

resource "aws_cloudwatch_log_group" "apigateway" {
  name              = "/aws/apigateway/${var.app}-${var.environment}"
  retention_in_days = 14
}

resource "aws_iam_role" "api_gw_cloudwatch" {
  name = "api_gw_cloudwatch_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "api_gw_cloudwatch_policy" {
  role = aws_iam_role.api_gw_cloudwatch.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents",
          "logs:GetLogEvents",
          "logs:FilterLogEvents"
        ],
        Effect   = "Allow",
        Resource = "*"
      },
    ]
  })
}

resource "aws_api_gateway_account" "account" {
  cloudwatch_role_arn = aws_iam_role.api_gw_cloudwatch.arn
}

resource "aws_security_group" "internal_traffic_sg" {
  name        = "internal-traffic-sg"
  description = "Allow internal traffic"

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_default_vpc.default_vpc.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "private-traffic-sg" {
  name        = "${var.app}-${var.environment}-private-traffic-sg"
  description = "App open SG for private network."
  vpc_id      = aws_default_vpc.default_vpc.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_default_vpc.default_vpc.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }
}

resource "aws_security_group" "public_traffic_sg" {
  name        = "public-traffic-sg"
  description = "Allow public traffic"

  ingress {
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]
}

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "ecsTaskExecutionRole" {
  name               = "${var.app}-${var.environment}-ecs"
  assume_role_policy = "${data.aws_iam_policy_document.assume_role_policy.json}"
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ecsTaskExecutionRole_policy" {
  role       = "${aws_iam_role.ecsTaskExecutionRole.name}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

output "AWS_ACCOUNT_ID" {
  value = data.aws_caller_identity.current.account_id
}

output "AWS_REGION" {
  value = var.region
}
