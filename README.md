# AWS Infrastructure Automation Using Terraform & GitHub Actions

## Objective
Provision AWS infrastructure with Terraform and automate its deployment through a GitHub Actions pipeline with a manual approval gate.

## Overall Workflow

```
GitHub → GitHub Actions → Format → Init → Validate → Plan → Plan Artifact
       → Approval → Apply → AWS Infrastructure → Outputs → Validation
```

| # | Stage | What happens | Where |
|---|-------|--------------|-------|
| 1 | **GitHub** | Code pushed / PR opened on `main` touching `infra/**` | trigger |
| 2 | **GitHub Actions** | Workflow starts, authenticates to AWS via OIDC (no access keys) | `terraform.yml` |
| 3 | **Format** | `terraform fmt -check -recursive` — fails on unformatted code | `plan` job |
| 4 | **Init** | `terraform init` with S3 remote backend + native state locking | `plan` job |
| 5 | **Validate** | `terraform validate` — syntax & internal consistency | `plan` job |
| 6 | **Plan** | `terraform plan -out=tfplan -detailed-exitcode`; plan posted to PR & job summary | `plan` job |
| 7 | **Plan Artifact** | `tfplan`, `plan.txt`, lock file uploaded as an artifact | `plan` job |
| 8 | **Approval** | `apply` job targets the `production` environment → waits for a required reviewer | `apply` job |
| 9 | **Apply** | `terraform apply tfplan` — applies exactly the reviewed plan | `apply` job |
| 10 | **AWS Infrastructure** | VPC, subnets, IGW, routes, SG, EC2 (nginx), IAM, S3 created | AWS |
| 11 | **Outputs** | `terraform output -json` → job summary + artifact | `apply` job |
| 12 | **Validation** | VPC state, EC2 status checks, S3 head-bucket, HTTP 200 from web server | `apply` job |

PRs run stages 1–7 only (plan is commented on the PR). Merging to `main` runs the full pipeline.

## Architecture

```
                         ┌──────────────── VPC 10.0.0.0/16 ────────────────┐
Internet ── IGW ── Route │  Public Subnet 10.0.1.0/24   Public Subnet 10.0.2.0/24 │
              Table      │   ┌───────────────────┐                          │
                         │   │ EC2 t3.micro       │  SG: 80/tcp in           │
                         │   │ Amazon Linux 2023  │  IAM: SSM Session Mgr    │
                         │   │ nginx  /health     │  IMDSv2, encrypted gp3   │
                         │   └───────────────────┘                          │
                         └──────────────────────────────────────────────────┘
          S3 app bucket (private, versioned, encrypted)
          S3 state bucket (bootstrap; versioned, encrypted, native lockfile)
```

## Repository Structure

```
aws-terraform-gha/
├── .github/workflows/
│   ├── terraform.yml            # main CI/CD pipeline (all 12 stages)
│   └── terraform-destroy.yml    # manual teardown (also approval-gated)
├── bootstrap/
│   └── main.tf                  # one-time: state bucket + GitHub OIDC + IAM role
├── infra/
│   ├── versions.tf              # Terraform/provider versions, S3 backend
│   ├── variables.tf
│   ├── terraform.tfvars
│   ├── network.tf               # VPC, subnets, IGW, route table, SG
│   ├── compute.tf               # EC2, IAM instance profile, AMI lookup
│   ├── user_data.sh.tftpl       # installs nginx + /health endpoint
│   ├── storage.tf               # application S3 bucket
│   └── outputs.tf
└── README.md
```

## Setup

### Prerequisites
- AWS account and AWS CLI configured locally with admin credentials
- Terraform ≥ 1.10 installed locally (needed for native S3 state locking)
- A GitHub repository

### Step 1 — Bootstrap (run once, locally)
```bash
cd bootstrap
terraform init
terraform apply -var="github_org=<your-github-username>" -var="github_repo=<your-repo-name>"
```
Note the two outputs: `state_bucket_name` and `github_actions_role_arn`.

> If your account already has a GitHub OIDC provider, import it first:
> `terraform import aws_iam_openid_connect_provider.github arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com`

### Step 2 — Configure GitHub
In **Settings → Secrets and variables → Actions**:

| Type | Name | Value |
|------|------|-------|
| Secret | `AWS_ROLE_ARN` | `github_actions_role_arn` from bootstrap |
| Secret | `TF_STATE_BUCKET` | `state_bucket_name` from bootstrap |
| Variable | `AWS_REGION` | `ap-south-1` |

In **Settings → Environments → New environment** create `production`, tick **Required reviewers**, and add yourself. This is the approval gate.

### Step 3 — Push and run
```bash
git init && git add . && git commit -m "Initial infrastructure"
git branch -M main
git remote add origin https://github.com/<user>/<repo>.git
git push -u origin main
```
Open the **Actions** tab → the run pauses at *Approval* → **Review deployments → Approve** → apply, outputs and validation run. The web URL appears in the job summary.

### Step 4 — Teardown
Actions → **Terraform Destroy** → Run workflow → type `destroy` → approve.
The bootstrap state bucket has `prevent_destroy`; remove it manually if you no longer need it.

## Security Highlights
- **OIDC** short-lived credentials, trust restricted to this repo — no AWS keys stored in GitHub
- **Remote state** in encrypted, versioned S3 with native locking (`use_lockfile`)
- **Approval gate** via GitHub Environments before any change hits AWS
- **Saved plan apply** — exactly what was reviewed is what gets applied
- EC2: IMDSv2 enforced, encrypted root volume, no SSH port (SSM Session Manager instead)
- S3: public access blocked, SSE encryption, versioning

## Cost
`t3.micro` is Free-Tier eligible in its first year; the remaining resources (VPC, IGW, SG, S3 with little data) are free or a few cents. Note that AWS charges for public IPv4 addresses (~$0.005/hour). Run the destroy workflow when finished.
