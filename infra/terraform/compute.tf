# ===== EC2 Compute =====
# ===== Master EC2 생성 =====
resource "aws_instance" "master" {
  ami           = var.ubuntu_ami_id
  instance_type = var.master_instance_type

  subnet_id = aws_subnet.private_b.id
  # key_name      = aws_key_pair.main.key_name # 자동완성이 지정해준건데 아직은 변수에 없어서 주석처리함

  vpc_security_group_ids      = [aws_security_group.master.id]
  associate_public_ip_address = false # private이라 공인 IP 할당 X

  iam_instance_profile = aws_iam_instance_profile.ec2.name # IAM Role 연결

  depends_on = [aws_iam_role_policy_attachment.ssm] # SSM 정책 연결 후 EC2 설정 적용

  # 루트 EBS 30GiB로 증가 (기존 8GiB)
  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  # 삭제 방지
  lifecycle {
    prevent_destroy = true
  }
  disable_api_termination = true # AWS 콘솔에서도 삭제 방지

  tags = {
    Name = "accordion-master"
  }
}

# ===== Worker EC2 생성 =====
resource "aws_instance" "worker" {
  ami           = var.ubuntu_ami_id
  instance_type = var.worker_instance_type

  subnet_id = aws_subnet.private_d.id
  # key_name      = aws_key_pair.main.key_name # 자동완성이 지정해준건데 아직은 변수에 없어서 주석처리함

  vpc_security_group_ids      = [aws_security_group.worker.id]
  associate_public_ip_address = false # private이라 공인 IP 할당 X

  iam_instance_profile = aws_iam_instance_profile.ec2.name # IAM Role 연결

  depends_on = [aws_iam_role_policy_attachment.ssm] # SSM 정책 연결 후 EC2 설정 적용

  # 루트 EBS 30GiB로 증가 (기존 8GiB)
  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  # 삭제 방지
  lifecycle {
    prevent_destroy = true
  }
  disable_api_termination = true # AWS 콘솔에서도 삭제 방지

  tags = {
    Name = "accordion-worker"
  }
}