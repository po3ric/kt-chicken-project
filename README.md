# ACCORDION -- Terraform AWS Infrastructure
  
## 검증 순서
```
terraform fmt
terraform validate
terraform plan
```

## 적용 방법
```
terraform apply
 * 웬만해서는 실행하지 않고 검증만 하기.
```

### 파일 구조(임시)
```
terraform/
├── provider.tf         # AWS Provider 및 Terraform 설정
├── variables.tf        # 입력 변수 선언 및 유효성 검사
├── terraform.tfvars    # 실제 AWS 환경 설정값        (*Git에는 업로드하지 않음.)
├── network.tf          # VPC, Subnet, IGW, NAT, EIP, Route Table
├── security.tf         # Master/Worker Security Group
├── compute.tf          # Ubuntu AMI 조회, EC2 생성 및 IAM Profile 연결
├── iam.tf              # IAM Role, SSM 정책, Instance Profile
├── outputs.tf          # VPC ID, Subnet ID, EC2 ID, Private IP 출력
└── .terraform.lock.hcl # Provider 버전 잠금
```

## 즉, 우리 프로젝트의 추천 작업 순서
1. versions.tf, provider.tf, variables.tf, terraform.tfvars, locals.tf로 기본 설정 정리
2. network.tf로 VPC·Subnet·IGW·Route Table 구축
3. security.tf로 Master·Worker 보안그룹 구성
4. compute.tf로 EC2 Master·Worker 생성
5. ecr.tf로 컨테이너 이미지 저장소 구축
6. outputs.tf와 조건 검증으로 결과 확인
  

> precondition, postcondition 사용해서 안정성 높여보기 

* 1단계: 지난번 실습처럼 AWS VPC, Subnet, SG, EC2를 Terraform으로 구성한다.
* 2단계: variables.tf에 CIDR, 관리자 IP, 인스턴스 유형에 대한 validation을 추가한다.
* 3단계: compute.tf에 AMI 호환성 precondition과 필요한 결과 postcondition을 추가한다.
* 4단계: 일부러 잘못된 값을 입력하고 terraform plan에서 실제로 차단되는지 확인해 결과를 기록한다.

> 4단계에서 오류가 나야 정상 작동하는 것!


  
`**terraform state list**를 통해 현재 terraform에서 관리중인 리스트 확인 가능`
  
    

## NAT G/W 삭제하는 방법
> NAT G/W는 과금이 되기에 삭제했다 지웠다 할 것. EC2는 콘솔로 중지

```
variables.tf 파일의 enable_nat_gateway 블록 내

default = true를 false로 변경 시 NAT G/W 삭제.
```


------
## 만약 terraform이 실행이 안된다면?
1. 현재 상위 폴더에 terraform.exe가 있는지 확인.
2. terraform.exe가 들어있는 폴더가 환경변수가 설정되어 있는지 확인.
3. AWS Key가 정상적으로(현재 aws의 액세스키) 저장되어 있는지 확인.