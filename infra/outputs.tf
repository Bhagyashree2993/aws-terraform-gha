output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "security_group_id" {
  description = "ID of the web security group"
  value       = aws_security_group.web.id
}

output "instance_id" {
  description = "ID of the EC2 web server"
  value       = aws_instance.web.id
}

output "instance_public_ip" {
  description = "Public IP of the EC2 web server"
  value       = aws_instance.web.public_ip
}

output "web_url" {
  description = "URL of the deployed web page"
  value       = "http://${aws_instance.web.public_dns}"
}

output "app_bucket_name" {
  description = "Name of the application S3 bucket"
  value       = aws_s3_bucket.app.bucket
}
