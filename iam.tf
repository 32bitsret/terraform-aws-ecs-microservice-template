# resource "aws_iam_user" "app_user" {
#   name = "devOps_${var.app}_${var.environment}_app_user"
# }

# resource "aws_iam_access_key" "app_user_keys" {
#   user = aws_iam_user.app_user.name
# }

# # grant required permissions to the APP to carry out the following actions. 
# # Kindly apply the priciple of least priviledge
# data "aws_iam_policy_document" "app_user_policy" {
#   # statement {
#   #   effect = "Deny"
#   #   actions = ["*"]
#   #   resources = ["*"]
#   # }
#   statement {
#     effect = "Allow"
#     actions = ["s3:ListAllMyBuckets"]
#     resources = ["*"]
#   }
# }

# resource "aws_iam_user_policy" "app_user_policy" {
#   name   = "devOps_${var.app}_${var.environment}_app_user"
#   user   = aws_iam_user.app_user.name
#   policy = data.aws_iam_policy_document.app_user_policy.json
# }

# # The AWS keys for the App user to use in a build system
# output "app_user_keys" {
#   value = "terraform show -json | jq '.values.root_module.resources | .[] | select ( .address == \"aws_iam_access_key.app_user_keys\") | { AWS_ACCESS_KEY_ID: .values.id, AWS_SECRET_ACCESS_KEY: .values.secret }'"
# }