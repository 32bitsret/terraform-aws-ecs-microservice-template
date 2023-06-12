# The application's name
variable "app" {
  default = "em"
}

# The environment that is being built
variable "environment" {
  default = "prod"
}

variable "region" {
  default = "eu-central-1"
}

variable "logs_retention_in_days" {
  type        = number
  default     = 90
  description = "Specifies the number of days you want to retain log events"
}

# SSL
variable "frontend_domain" {
  default = "everydaymoney.ng"
}

variable "api_domain" {
  default = "api.everydaymoney.ng"
}

variable "acme_registration_email" {
  default = "contact@everydaymoney.ng"
}

variable "acme_server_url" {
  default = "https://acme-v02.api.letsencrypt.org/directory"
}

variable "domain_r53_host_id" {
  default = "Z04022021N21JSANVWAJ7"
}

# How many containers to run
variable "replicas" {
  default = "1"
}

variable "ecs_autoscale_min_instances" {
  default = "1"
}

# The maximum number of containers that should be running.
# used by both autoscale-perf.tf and autoscale.time.tf
variable "ecs_autoscale_max_instances" {
  default = "3"
}