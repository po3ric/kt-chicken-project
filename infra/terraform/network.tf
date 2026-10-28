# ===== VPC 설정 =====
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  enable_dns_support   = var.enable_dns_support
  enable_dns_hostnames = var.enable_dns_hostnames

  tags = {
    Name = "accordion-vpc"
  }
}

# ===== Public Subnet B =====
resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_sub_b_cidr
  availability_zone       = var.master_availability_zone
  map_public_ip_on_launch = var.map_public_ip_on_launch

  tags = {
    Name = "accordion-public-subnet-b"
  }
}

# ===== Private Subnet B (Master) =====
resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_sub_b_cidr
  availability_zone = var.master_availability_zone

  tags = {
    Name = "accordion-private-subnet-b"
  }
}

# ===== Private Subnet D (Worker) =====
resource "aws_subnet" "private_d" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_sub_d_cidr
  availability_zone = var.worker_availability_zone

  lifecycle {
    precondition {
      condition     = var.master_availability_zone != var.worker_availability_zone
      error_message = "Master와 Worker의 AZ는 서로 달라야 합니다."
    }
  }

  tags = {
    Name = "accordion-private-subnet-d"
  }
}

# ===== Internet Gateway # VPC의 인터넷 출입구 =====
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "accordion-igw"
  }
}


# ===== 기본 Route Table  =====
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "accordion-public-rt"
  }
}

# ===== Public Route Table에 0.0.0.0/0 -> Internet Gateway 연결 =====
resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

# ===== Public Subnet B -> Public Route Table 연결 =====
resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}


# ===== NAT G/W용 Elastic IP =====
resource "aws_eip" "nat_a" {
  count  = var.enable_nat_gateway ? 1 : 0
  domain = "vpc"

  tags = {
    Name = "accordion-nat-eip"
  }
}

# ===== NAT G/W Private EC2의 outbound 통신용 =====
resource "aws_nat_gateway" "nat_a" {
  count = var.enable_nat_gateway ? 1 : 0

  allocation_id = aws_eip.nat_a[0].id
  subnet_id     = aws_subnet.public_b.id

  depends_on = [aws_internet_gateway.main] # NAT G/W 생성 전에 IGW가 먼저 생성되어야 함

  tags = {
    Name = "accordion-nat-a"
  }
}


# ===== Private Route Table #Private B/D가 공유하는 용도 =====
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "accordion-private-rt"
  }
}

# ===== Private Default Route Table: 0.0.0.0/0 -> NAT G/W 연결 =====
resource "aws_route" "private_internet" {
  count = var.enable_nat_gateway ? 1 : 0

  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_a[0].id
}

# ===== Private Subnet B -> Private Route Table 연결 =====
resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}

# ===== Private Subnet D -> Private Route Table 연결 =====
resource "aws_route_table_association" "private_d" {
  subnet_id      = aws_subnet.private_d.id
  route_table_id = aws_route_table.private.id
}


# ===== NAT G/W 리소스 잘못 교체 방지 =====
# 이부분은 잘 모르지만 일단 적어두고 나중에 찾아보겠습니다!!!
# Terraform에게 기존 리소스의 관리 주소가 변경되었다는 사실을 알려주는 역할
moved {
  from = aws_eip.nat_a
  to   = aws_eip.nat_a[0]
}

moved {
  from = aws_nat_gateway.nat_a
  to   = aws_nat_gateway.nat_a[0]
}

moved {
  from = aws_route.private_internet
  to   = aws_route.private_internet[0]
}