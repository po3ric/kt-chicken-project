# ACCORDION -- Terraform AWS Infrastructure
AWS 인프라를 Terraform으로 구축하고 관리하기 위한 코드입니다.

A1 팀원이 설계한 네트워크 규격과 아키텍처를 기반으로 구현했습니다.
  
## 주요 구성
- **Network**: VPC, Public/Private Subnet, Internet Gateway, NAT Gateway, Route Table  
- **Compute**: Master EC2, Worker EC2 (Ubuntu 24.04 LTS)  
- **Security**: Security Group을 통한 노드 간 통신 제어  
- **IAM**: SSM Session Manager 접근 및 ECR 읽기 권한  
- **Storage**: Master/Worker 루트 EBS 30GiB  
- **Stability**: EC2 삭제 방지 및 Terraform 입력값 검증  
  

## Terraform 파일 구조
```
terraform/
├── provider.tf              # AWS Provider 및 Terraform 설정
├── variables.tf             # 입력 변수 선언 및 유효성 검사
├── terraform.tfvars.example # 환경 설정 예시 파일
├── terraform.tfvars         # 실제 환경 설정값 (Git 업로드 제외)
├── network.tf               # VPC, Subnet, IGW, NAT, EIP, Route Table
├── security.tf              # Master/Worker Security Group
├── compute.tf               # Master/Worker EC2 및 EBS 설정
├── iam.tf                   # IAM Role, SSM/ECR 정책, Instance Profile
├── outputs.tf               # 생성된 AWS 리소스 정보 출력
├── .terraform.lock.hcl      # Provider 버전 고정
└── README.md                # 프로젝트 실행 및 설정 안내
```
  
Terraform은 같은 디렉터리의 .tf 파일을 하나로 읽기 때문에 나누어도 상관 없고,  
나눈 이유는 실행 순서 지정이 아닌, 리소스별 역할 구분 용도입니다.

## 실행 환경 설정
```
1. 사전 준비
- Terraform 설치
- AWS CLI 설치 및 인증 설정
- AWS 리소스 관리 가능한 IAM 권한
- AWS 리전 : ap-northeast-2(서울)

2. 환경 변수 파일 준비
 현재 파일 내 terraform.ftvars.example을 복사해 terraform.tfvars 생성

> terraform.tfvars는 Git에 업로드하지 않았습니다.(보안상)
```
  
## Terraform 실행 및 검증 방법
1. 초기화 - `terraform init`    * 테라폼이 실행 가능한 환경 구성
2. 코드 형식 검사 - `terraform fmt` * 코드가 보기 좋게 변경됨
3. 구성 유효성 검사 - `terraform validate`
4. 변경 계획 확인 - `terraform plan` * AWS에 적용하기 전 마지막 단계로, 리소스의 생성·변경·삭제 계획을 확인

※ 만약, 원인 모를 삭제 또는 재생성 계획이 있다면 plan을 보고 추적해서 찾아내야 함.

5. AWS 인프라 적용 - `terraform apply`  * 실제 AWS 환경에 인프라를 구축함. (주의)
  
  <br/>
  <br/><br/>

## =====추가 기능과 팁=====
### (추가 기능) EC2 삭제 방지
Master와 Worker EC2에는 의도하지 않은 삭제 및 재생성을 방지하기 위한 설정을 적용했습니다.
```
lifecycle {
  prevent_destroy = true
}
disable_api_termination = true

* prevent_destroy: Terraform에서 EC2 삭제·교체 계획을 차단합니다.
* disable_api_termination: AWS API를 통한 일반적인 EC2 종료(termination)를 방지합니다
```
  
### (추가 기능) AMI ID 고정
Ubuntu AMI를 최신 버전으로 자동 조회하는 과정에서 기존 EC2가 재생성 대상으로 표시되는 문제가 발생했습니다.

이를 방지하기 위해 `most_recent = true` 방식 대신 기존 `AMI ID`를 변수로 고정했습니다.
  
### (추가 기능) 입력값 및 가용 영역 검증
1. validation으로 VPC CIDR 형식 검사

2. precondition으로 Master와 Worker의 가용 영역 중복 방지

3. terraform plan으로 실제 적용 전 변경 내용 확인

  
<br>

### NAT G/W 삭제하는 방법(관리)
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
  -> `aws sts get-caller-identity`


___
#### 그 외 종종 사용하는 명령어
1. `**terraform state list**를 통해 현재 terraform에서 관리중인 리스트 확인 가능`
2. `**terraform fmt -check**를 통해 파일 수정 없이 코드 형식만 검사 가능 `
3. `**terraform output**을 통해 AWS 출력값 확인 가능`

  
<br>
  
## 인프라 재현성 검증
실제 팀 AWS 환경에 영향을 주지 않도록 별도의 개인 AWS 계정에서 재현성 검증을 진행했습니다.

| 순서 | 명령어 | 검증 결과 |
| :--- | :--- | :--- |
| 1 | `terraform apply` | AWS 리소스 22개 생성 |
| 2 | `terraform destroy` | AWS 리소스 22개 삭제 |
| 3 | `terraform apply` | AWS 리소스 22개 재생성 |

동일한 Terraform 코드를 사용하여 동일한 구성의 AWS 인프라가 재생성되는 것을 확인했습니다.

apply와 destroy 도중 오류가 발생할 것입니다.
> EC2 인스턴스 삭제 방지로 인해 오류 발생 -> compute.tf Master/Worker의 옵션 false로 변경