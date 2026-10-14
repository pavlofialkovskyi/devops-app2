
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
  db_name                 = "devops_app2_db"
  username                = "app_user"
  password                = random_password.db_password.result
  db_subnet_group_name    = aws_db_subnet_group.main.name
  vpc_security_group_ids  = [aws_security_group.rds_sg.id]
  skip_final_snapshot     = true
  publicly_accessible     = false
  multi_az                = true
  backup_retention_period = 1
  backup_window           = "03:00-04:00"
}