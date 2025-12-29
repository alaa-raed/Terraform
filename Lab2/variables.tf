variable "region" {
  description = "AWS region"
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  default     = "10.0.0.0/16"
}

variable "instance_type" {
  description = "EC2 instance type"
  default     = "t2.micro"
}

variable "key_name" {
  description = "SSH key name for EC2 instances"
  type        = string
}

variable "s3_bucket_name" {
  description = "S3 bucket name (must be globally unique)"
  type        = string
}