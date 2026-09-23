resource "random_password" "db_password" {
  length  = 20
  special = false
}

resource "aws_ssm_parameter" "db_password" {
  name  = "/devops-app2/db_password"
  type  = "SecureString"
  value = random_password.db_password.result
}

resource "aws_db_subnet_group" "main" {
  name       = "devops-app2-db-subnet-group"
  subnet_ids = [aws_subnet.private_db_a.id, aws_subnet.private_db_b.id]
}

resource "aws_db_instance" "main" {
  identifier              = "devops-app2-db"
  engine                  = "postgres"
  engine_version          = "16"
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  db_name                 = "devopsapp2"
  username                = "postgres"
  password                = random_password.db_password.result
  db_subnet_group_name    = aws_db_subnet_group.main.name
  vpc_security_group_ids  = [aws_security_group.rds_sg.id]
  skip_final_snapshot     = true
  publicly_accessible     = false
  multi_az                = true
  backup_retention_period = 1
  backup_window           = "03:00-04:00"
}