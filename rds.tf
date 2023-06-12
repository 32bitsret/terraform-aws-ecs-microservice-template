resource "random_string" "db_password" {
  length  = 31
  upper   = true
  numeric  = true
  special = false
}

resource "aws_security_group" "rds_sg" {
  vpc_id      = "${aws_default_vpc.default_vpc.id}"
  name        = "${var.app}-${var.environment}-rds_sg"
  description = "Allow all inbound for Postgres"
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    # cidr_blocks = [aws_default_vpc.default_vpc.cidr_block]
  }
}

resource "aws_db_instance" "app_database_instance" {
  identifier             = "${var.app}-${var.environment}-db"
  instance_class         = "db.t3.medium"
  allocated_storage      = 5
  engine                 = "postgres"
  engine_version         = "15"
  skip_final_snapshot    = true
  publicly_accessible    = true
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  username               = "db_admin"
  password               = "${random_string.db_password.result}"
  db_name                = "birs_data"
}


output "DATABASE_PASSWORD" {
  value = random_string.db_password.result
}

output "DATABASE_NAME" {
  value = aws_db_instance.app_database_instance.db_name
}

output "DATABASE_HOST" {
  value = aws_db_instance.app_database_instance.address
}

output "DATABASE_USER" {
  value = aws_db_instance.app_database_instance.username
}

output "DATABASE_ENGINE" {
  value = aws_db_instance.app_database_instance.engine
}

output "DATABASE_ENGINE_VERSION" {
  value = aws_db_instance.app_database_instance.engine_version
}