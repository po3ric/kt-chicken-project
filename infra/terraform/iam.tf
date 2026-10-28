# ===== IAM ROLE =====
# ec2가 사용할 IAM Role 생성
resource "aws_iam_role" "ec2_ssm_role" {
  name = "accordion-ec2-ssm-role"

  # EC2가 이 역할을 사용할 수 있도록 허용 #신뢰 정책 JSON 복사
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Name = "accordion-ec2-ssm-role"
  }
}


# IAM ROLE에 SSM 관리 정책 연결
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# EC2가 Amazon ECR에서 컨테이너 이미지를 조회하고 다운로드할 수 있도록 AmazonEC2ContainerRegistryReadOnly 정책 연결
resource "aws_iam_role_policy_attachment" "ecr_readonly" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# IAM ROLE을 EC2에 연결하기 위해 Instance Profile 생성
resource "aws_iam_instance_profile" "ec2" {
  name = "accordion-ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm_role.name
}