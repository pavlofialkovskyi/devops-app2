data "aws_ec2_managed_prefix_list" "cloudfront" { # a list of Cloudfront IPs
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "Allows inbound requests from www via http and https"
  vpc_id      = aws_vpc.main.id


  # the HTTP block used to catch 80 port request from HTTP but now it is redirected anyways, 

  # Before ALB was not protected and was accepting all the traffic from PUBLIC internet 0.0.0.0/0
  # ALB now only accepts traffic from CloudFront adresses, because this gates are located all over the world,
  # their IP list is in prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront.id

  ingress {
    description     = "HTTPS from CloudFront only"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront.id] # list of Cloudfront IPs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ec2_sg" {
  name        = "ec2-sg"
  description = "Allows app traffic from the ALB only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "App port from ALB"
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "rds-sg"
  description = "Allows Postgres traffic from EC2 only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Postgres from EC2"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}