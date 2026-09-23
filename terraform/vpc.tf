resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  # aws_vpc is the network itself — 10.0.0.0/16 gives you 65,536 addresses to carve up
  # standard-sized private range

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "devops-app2-vpc"
  }
}

resource "aws_internet_gateway" "main" {

  # aws_internet_gateway is what actually lets anything in this VPC reach (or be reached from) 
  # the public internet — without it, this VPC would be totally isolated.

  vpc_id = aws_vpc.main.id

  # we will use this id in security_groups.tf

  tags = {
    Name = "devops-app2-igw"
  }
}

# big architectural change -> I am adding 4x private subnets, a and b for EC2[app] and RDS[db]

resource "aws_subnet" "private_app_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = "us-east-2a"

  tags = {
    Name = "devops-app2-private-app-a"
  }
}

resource "aws_subnet" "private_app_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = "us-east-2b"

  tags = {
    Name = "devops-app2-private-app-b"
  }
}

resource "aws_subnet" "private_db_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.20.0/24"
  availability_zone = "us-east-2a"

  tags = {
    Name = "devops-app2-private-db-a"
  }
}

resource "aws_subnet" "private_db_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.21.0/24"
  availability_zone = "us-east-2b"

  tags = {
    Name = "devops-app2-private-db-b"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "devops-app2-public-rt"
  }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# The route table + two associations is what tells each subnet "any traffic not staying inside this VPC, 
# send it out through the internet gateway" — subnets on their own don't know how to route anywhere without this.