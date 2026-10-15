# ===== AWS 기본 설정 =====

# AWS 리전 설정
variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "ap-northeast-2"
}

# 프로젝트 이름
variable "project_name" {
  description = "Project name"
  type        = string
  default     = "accordion"
}


# ===== VPC 설정 (validation으로 CIDR 형식 검증) =====
# 잘못된 CIDR 형식 들어오면 실행하기 전에 차단하는 용도 *안정성 높이기

# VPC CIDR
variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "입력한 VPC CIDR 주소가 올바른 IPv4 CIDR 형식(예: 10.0.0.0/16)이 아닙니다. 현재 입력값: ${var.vpc_cidr}"
  }
}

# VPC DNS 설정
variable "enable_dns_support" {
  description = "Enable DNS resolution in VPC"
  type        = bool
}

variable "enable_dns_hostnames" {
  description = "Enable DNS hostnames in VPC"
  type        = bool
}


# ===== Subnet 설정 =====

# Public Subnet B CIDR
variable "public_sub_b_cidr" {
  description = "Public Subnet B CIDR Block"
  type        = string

  validation {
    condition     = can(cidrhost(var.public_sub_b_cidr, 0))
    error_message = "입력한 Public Subnet B CIDR 주소가 올바른 IPv4 CIDR 형식(예: 10.0.0.0/24)이 아닙니다. 현재 입력값: ${var.public_sub_b_cidr}"
  }
}

# Private Subnet B CIDR
variable "private_sub_b_cidr" {
  description = "Private Subnet B CIDR Block"
  type        = string

  validation {
    condition     = can(cidrhost(var.private_sub_b_cidr, 0))
    error_message = "입력한 Private Subnet B CIDR 주소가 올바른 IPv4 CIDR 형식(예: 10.0.101.0/24)이 아닙니다. 현재 입력값: ${var.private_sub_b_cidr}"
  }
}

# Private Subnet D CIDR
variable "private_sub_d_cidr" {
  description = "Private Subnet D CIDR Block"
  type        = string

  validation {
    condition     = can(cidrhost(var.private_sub_d_cidr, 0))
    error_message = "입력한 Private Subnet D CIDR 주소가 올바른 IPv4 CIDR 형식(예: 10.0.102.0/24)이 아닙니다. 현재 입력값: ${var.private_sub_d_cidr}"
  }
}

# Public Subnet B 가용 영역
variable "availability_zone_b" {
  description = "Availability Zone B"
  type        = string
}

# Public Subnet D 가용 영역
variable "availability_zone_d" {
  description = "Availability Zone D"
  type        = string
}

# master ec2 가용 영역
variable "master_availability_zone" {
  description = "Master EC2 Availability Zone"
  type        = string
}

# worker ec2 가용 영역
variable "worker_availability_zone" {
  description = "Worker EC2 Availability Zone"
  type        = string
}



variable "map_public_ip_on_launch" {
  description = "Automatically assign public IPv4 to instances"
  type        = bool
}


# ===== EC2 설정 =====
variable "master_instance_type" {
  description = "Kubernetes Control Plane instance type"
  type        = string
}

# Kubernetes Worker EC2 사양
variable "worker_instance_type" {
  description = "Kubernetes Worker instance type"
  type        = string
}


# ===== NAT G/W 삭제/생성 enable 변수 추가 =====
variable "enable_nat_gateway" {
  description = "Enable NAT Gateway"
  type        = bool
  default     = false # true 시 생성, false 시 삭제
}