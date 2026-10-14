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

    # thse resources are provision to give it to WEB APP Container on creation, as I did locally in Docker-compose.yml
    # for AWS they live in the Bootstrap.sh
    resources = [
      "arn:aws:ssm:us-east-2:364077344467:parameter/devops-app2/db_password", # EC2 has a key to PostgresDB
      "arn:aws:ssm:us-east-2:364077344467:parameter/devops-app2/ghcr_token",  # EC2 can download the private Image package
      "arn:aws:ssm:us-east-2:364077344467:parameter/devops-app2/db_host",     # EC2 knows the name of the PostgresDB to talk to
      "arn:aws:ssm:us-east-2:364077344467:parameter/devops-app2/jwt_secret",  # now EC2 flask web server has access > jwt_secret
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
