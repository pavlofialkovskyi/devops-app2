data "aws_iam_policy_document" "ec2_assume_role" {

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_role" {
  name               = "devops-app2-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "ssm_param_read" {
  statement {
    effect  = "Allow"
    actions = ["ssm:GetParameter"]

    resources = [
      "arn:aws:ssm:us-east-2:364077344467:parameter/devops-app2/db_password",
      "arn:aws:ssm:us-east-2:364077344467:parameter/devops-app2/ghcr_token",
      "arn:aws:ssm:us-east-2:364077344467:parameter/devops-app2/db_host",
    ]
  }
}

resource "aws_iam_role_policy" "ssm_param_read" {

  name   = "devops-app2-ssm-param-read"
  role   = aws_iam_role.ec2_role.id
  policy = data.aws_iam_policy_document.ssm_param_read.json
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "devops-app2-ec2-role"
  role = aws_iam_role.ec2_role.name
}

resource "random_password" "db_password" {
  length  = 20
  special = false
}

resource "aws_ssm_parameter" "db_password" {
  name  = "/devops-app2/db_password"
  type  = "SecureString"
  value = random_password.db_password.result
}

resource "aws_db_instance" "main" {
  # ...same as before...
  password = random_password.db_password.result
}