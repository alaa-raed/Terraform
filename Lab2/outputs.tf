output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.nti.id
}

output "alb_dns_Name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.alb.dns_name
}

output "s3_bucket_name_id" {
  description = "ID of the S3 bucket"
  value       = aws_s3_bucket.app_bucket.id
}

output "nat_gateway_ip" {
  description = "NAT Gateway public IP"
  value       = aws_eip.nat.public_ip
}