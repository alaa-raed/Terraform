provider "aws" {
  region = var.region
}

# VPC
resource "aws_vpc" "nti" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "nti-vpc" }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.nti.id
}

# Data source for availability zones
data "aws_availability_zones" "available" {}

# Public Subnets
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.nti.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = { Name = "Public Subnet 1" }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.nti.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = { Name = "Public Subnet 3" }
}

# Private Subnets
resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.nti.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = { Name = "Private Subnet 2" }
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.nti.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = { Name = "Private Subnet 4" }
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.nti.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

# Public Route Table Associations
resource "aws_route_table_association" "public" {
  for_each = {
    p1 = aws_subnet.public_1.id
    p2 = aws_subnet.public_2.id
  }

  subnet_id      = each.value
  route_table_id = aws_route_table.public.id
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"
}

# NAT Gateway
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_2.id
}

# Private Route Table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.nti.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
}

# Private Route Table Associations
resource "aws_route_table_association" "private" {
  for_each = {
    pr1 = aws_subnet.private_1.id
    pr2 = aws_subnet.private_2.id
  }

  subnet_id      = each.value
  route_table_id = aws_route_table.private.id
}

# S3 Bucket for Application
resource "aws_s3_bucket" "app_bucket" {
  bucket = var.s3_bucket_name
}

# S3 Bucket Public Access Block - Disable to allow public policy
resource "aws_s3_bucket_public_access_block" "app_bucket" {
  bucket = aws_s3_bucket.app_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# S3 Bucket Policy - Allow All Write Access
resource "aws_s3_bucket_policy" "app_bucket" {
  bucket = aws_s3_bucket.app_bucket.id
  
  # Add dependency to ensure public access block is configured first
  depends_on = [aws_s3_bucket_public_access_block.app_bucket]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.app_bucket.arn}/*"
      },
      {
        Effect = "Allow"
        Principal = "*"
        Action = "s3:ListBucket"
        Resource = aws_s3_bucket.app_bucket.arn
      }
    ]
  })
}

# Security Group for ALB
resource "aws_security_group" "alb_sg" {
  vpc_id = aws_vpc.nti.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "alb-sg" }
}

# Security Group for Private EC2 Instances
resource "aws_security_group" "private_ec2_sg" {
  vpc_id = aws_vpc.nti.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "private-ec2-sg" }
}

# Latest Amazon Linux AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# EC2 Instance 1
resource "aws_instance" "apache_1" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private_1.id
  vpc_security_group_ids = [aws_security_group.private_ec2_sg.id]
  key_name               = var.key_name
  user_data              = file("apache_user_data.sh")

  tags = { Name = "EC2 Instance 1" }
}

# EC2 Instance 2
resource "aws_instance" "apache_2" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private_2.id
  vpc_security_group_ids = [aws_security_group.private_ec2_sg.id]
  key_name               = var.key_name
  user_data              = file("apache_user_data.sh")

  tags = { Name = "EC2 Instance 2" }
}

# Application Load Balancer
resource "aws_lb" "alb" {
  load_balancer_type = "application"
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  security_groups    = [aws_security_group.alb_sg.id]

  tags = { Name = "Application LB" }
}

# Target Group
resource "aws_lb_target_group" "tg" {
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.nti.id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# Target Group Attachments
resource "aws_lb_target_group_attachment" "ec1" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.apache_1.id
}

resource "aws_lb_target_group_attachment" "ec2" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.apache_2.id
}

# Listener
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

# Outputs
output "alb_dns_name" {
  value = aws_lb.alb.dns_name
}

output "s3_bucket_name" {
  value = aws_s3_bucket.app_bucket.id
}