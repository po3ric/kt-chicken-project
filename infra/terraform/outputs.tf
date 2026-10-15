# terraform으로 생성한 리소스 정보 확인용

# ===== VPC 정보 =====
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

# ===== Public/Private Subnet B 정보 =====
output "public_subnet_b_id" {
  description = "Public Subnet B ID"
  value       = aws_subnet.public_b.id
}

output "private_subnet_b_id" {
  description = "Private Subnet B ID"
  value       = aws_subnet.private_b.id
}

output "private_subnet_d_id" {
  description = "Private Subnet D ID"
  value       = aws_subnet.private_d.id
}

# ===== NAT Gateway 정보 =====
output "nat_gateway_id" {
  description = "NAT Gateway ID"
  value       = try(aws_nat_gateway.nat_a[0].id, null)
}

# ===== Security Group 정보 =====
output "master_security_group_id" {
  description = "Master Security Group ID"
  value       = aws_security_group.master.id
}

output "worker_security_group_id" {
  description = "Worker Security Group ID"
  value       = aws_security_group.worker.id
}

# ===== EC2 정보 ======
output "master_instance_id" {
  description = "Master EC2 Instance ID"
  value       = aws_instance.master.id
}

output "master_private_ip" {
  description = "Master EC2 Private IP"
  value       = aws_instance.master.private_ip
}

output "worker_instance_id" {
  description = "Worker EC2 Instance ID"
  value       = aws_instance.worker.id
}

output "worker_private_ip" {
  description = "Worker EC2 Private IP"
  value       = aws_instance.worker.private_ip
}