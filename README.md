# CraftHaven — AWS Disaster Recovery & Backup

Implementation supporting *Evaluating Cost-Effective Disaster Recovery and
Backup Strategies for Small Companies and Startups Using AWS Cloud
Infrastructure* (`Dissertation-draft.docx`). CraftHaven is the dissertation's
fictional small e-commerce vendor; this repo provisions its AWS environment
and the automation that backs it up, protects it, and recovers it.

## Layout

```text
infra/                  Terraform, one file per resource group (no modules)
  providers.tf           AWS provider, S3 backend (hardcoded — see below)
  variables.tf            all inputs
  network.tf              VPC, public/private subnets, NAT, routing
  compute.tf               EC2 web tier, security group, IAM instance profile
  database.tf              RDS MySQL, subnet group, security group
  storage.tf                S3 product-assets bucket + CloudTrail log bucket
  backup.tf                  AWS Backup vault, Vault Lock (governance mode), plan, selection
  monitoring.tf                CloudWatch alarms, CloudTrail, EventBridge, SNS
  outputs.tf
  terraform.tfvars.example    copy to terraform.tfvars (gitignored)

scripts/                Python DR tooling (boto3)
  dr_lib.py                shared RTO/RPO result helpers
  restore_test.py           restores the latest recovery point, measures RTO/RPO
  failure_simulation.py      terminates EC2 / force-fails-over RDS on demand

tests/                  pytest unit tests for scripts/

docs/diagrams/          Mermaid source for Figures 1–3 (Dissertation Ch. 3)

.github/workflows/
  pr.yml                    pytest + terraform fmt/validate/plan on every PR
  main.yml                   terraform apply on push to main
  restore-test.yml             weekly scheduled restore test + manual trigger
  failure-simulation.yml       manual failure/recovery drill (protected environment)
```

## Architecture

Six layers, matching Dissertation §3.2–3.3: application, backup, protection,
recovery, monitoring, and infrastructure-as-code/automation. See
[docs/diagrams](docs/diagrams) for the three referenced figures.

- **Application** — EC2 storefront, RDS MySQL (orders/customers), S3
  (product assets), all inside one VPC across public/private subnets.
- **Backup** — AWS Backup runs a daily plan against everything tagged
  `Backup=true` (EC2, RDS, S3), storing recovery points in a central vault.
- **Protection** — the vault is locked in Vault Lock governance mode, so
  recovery points can't be deleted or shortened during the retention window.
- **Recovery** — `scripts/restore_test.py` and `scripts/failure_simulation.py`
  automate restore and failure drills instead of a manual runbook.
- **Monitoring** — CloudWatch alarms on EC2/RDS/backup-job health, CloudTrail
  audit logging, EventBridge → SNS for backup/restore state changes.
- **IaC & automation** — everything above is Terraform, applied by GitHub
  Actions on merge to `main`.

## Getting started

The S3 backend (`infra/providers.tf`) points at a fixed bucket, key, region,
and DynamoDB lock table — `crafthaven-terraform-state` / `crafthaven-terraform-locks`
in `eu-west-2`. Both must exist before the first `terraform init` (created
once by hand, since Terraform can't create the backend it depends on to
run). Edit `providers.tf` directly if you need a different bucket/region/env.

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars   # fill in real values
terraform init
terraform plan
```

`db_password` and `alert_email` have no defaults — set them via
`terraform.tfvars` (gitignored) or `TF_VAR_db_password` / `TF_VAR_alert_email`.

## Running a DR drill locally

```bash
pip install -r requirements.txt

python scripts/failure_simulation.py --target rds \
  --db-instance-identifier crafthaven-dev-db --region eu-west-2

python scripts/restore_test.py --resource-type RDS \
  --resource-arn <rds-arn> --vault crafthaven-dev-vault \
  --iam-role-arn <backup-role-arn> --region eu-west-2
```

Results (RTO, RPO, restore success) are written as JSON to `results/`,
which is gitignored — see Dissertation §3.4 for how these feed into
Chapter 4's evaluation.

## CI/CD

- **`pr.yml`** — runs on every pull request: pytest against `scripts/`, plus
  `terraform fmt -check`, `terraform validate`, and `terraform plan` against
  `infra/`. Authenticates to AWS via OIDC (`secrets.AWS_TERRAFORM_ROLE_ARN`),
  no long-lived access keys.
- **`main.yml`** — `terraform apply` on push to `main` for changes under
  `infra/`, same OIDC auth, gated behind the `production` environment.
- **`restore-test.yml`** — scheduled weekly, plus manual dispatch; runs
  `restore_test.py` and uploads the result JSON as a workflow artifact.
- **`failure-simulation.yml`** — manual-only, gated behind a
  `disaster-recovery-drill` environment that should have required reviewers
  configured in repo settings before first use.
