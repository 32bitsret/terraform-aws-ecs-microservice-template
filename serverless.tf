# data "archive_file" "lambda_jwtauth_zip" {
#   type        = "zip"
#   source_file = "${path.module}/serverless/jwt_auth.js"
#   output_path = "${path.module}/dist/jwt_auth.zip"
# }

# resource "aws_lambda_function" "jwt_auth" {
#   filename      = data.archive_file.lambda_jwtauth_zip.output_path
#   function_name = "${var.app}_${var.environment}_jwt_auth"
#   role          = aws_iam_role.lambda_exec.arn
#   handler       = "jwt_auth.handler"
#   runtime       = "nodejs18.x"
#   source_code_hash = data.archive_file.lambda_jwtauth_zip.output_base64sha256
# }

# resource "aws_cloudwatch_log_group" "jwt_auth" {
#   name = "/aws/lambda/${aws_lambda_function.jwt_auth.function_name}"
#   retention_in_days = 30
# }

# resource "aws_iam_role" "lambda_exec" {
#   name = "${var.app}-${var.environment}_lambda_exec"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Action = "sts:AssumeRole",
#         Principal = {
#           Service = "lambda.amazonaws.com"
#         },
#         Effect = "Allow",
#         Sid = ""
#       },
#     ]
#   })
# }

# resource "aws_iam_role_policy_attachment" "lambda_exec_policy" {
#   role       = aws_iam_role.lambda_exec.name
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
# }

# resource "aws_api_gateway_authorizer" "jwt_auth" {
#   name                   = "jwt_auth"
#   rest_api_id            = aws_api_gateway_rest_api.user_service_api.id
#   authorizer_uri         = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.jwt_auth.arn}/invocations"
#   authorizer_credentials = aws_iam_role.lambda_exec.arn
#   type                   = "TOKEN"
#   identity_source        = "method.request.header.Authorization"
# }