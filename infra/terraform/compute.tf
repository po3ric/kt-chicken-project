# ===== EC2 Compute =====
# data 블럭은 이미 있는거 조회 / resource 블럭은 새로 생성하는거

# ===== Ubuntu 24.04 LTS AMI 조회 =====
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  # 이미지 검색
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  # CPU 아키텍처 종류 제한
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  # H/W 가상화 방식 지정
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}


# ===== Master EC2 생성 =====
resource "aws_instance" "master" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.master_instance_type

  subnet_id = aws_subnet.private_b.id
  # key_name      = aws_key_pair.main.key_name # 자동완성이 지정해준건데 아직은 변수에 없어서 주석처리함

  vpc_security_group_ids      = [aws_security_group.master.id]
  associate_public_ip_address = false # private이라 공인 IP 할당 X

  iam_instance_profile = aws_iam_instance_profile.ec2.name # IAM Role 연결

  depends_on = [aws_iam_role_policy_attachment.ssm] # SSM 정책 연결 후 EC2 설정 적용

  tags = {
    Name = "accordion-master"
  }
}

# ===== Worker EC2 생성 =====
resource "aws_instance" "worker" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.worker_instance_type

  subnet_id = aws_subnet.private_d.id
  # key_name      = aws_key_pair.main.key_name # 자동완성이 지정해준건데 아직은 변수에 없어서 주석처리함

  vpc_security_group_ids      = [aws_security_group.worker.id]
  associate_public_ip_address = false # private이라 공인 IP 할당 X

  iam_instance_profile = aws_iam_instance_profile.ec2.name # IAM Role 연결

  depends_on = [aws_iam_role_policy_attachment.ssm] # SSM 정책 연결 후 EC2 설정 적용

  tags = {
    Name = "accordion-worker"
  }
}