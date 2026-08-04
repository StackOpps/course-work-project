# CraftHaven — AWS Disaster Recovery & Backup

Implementation supporting *Evaluating Cost-Effective Disaster Recovery and
Backup Strategies for Small Companies and Startups Using AWS Cloud
Infrastructure* (`Dissertation-draft.docx`). CraftHaven is the dissertation's
fictional small e-commerce vendor; this repo provisions its AWS environment
and the automation that backs it up, protects it, and recovers it.

## Layout

```text
infra/                  Terraform, one file per resource group (no modules)
  providers.tf            AWS provider, S3 backend (hardcoded — see below)
  variables.tf             all inputs
  network.tf                VPC, public/private subnets, NAT, routing
  compute.tf                 EC2 web tier (nginx + PHP-FPM), security group, IAM instance profile
  database.tf                 RDS MySQL, subnet group, security group; restores from the
                                latest AWS Backup recovery point when applied against the DR region
  storage.tf                   S3 product-assets bucket + CloudTrail log bucket
  acm.tf                         ACM certificate for the storefront domain, DNS-validated
  dns.tf                          Route 53 alias record (primary region only)
  monitoring.tf                    CloudWatch alarms (EC2 status check, RDS free storage), CloudTrail
  outputs.tf
  site_src/                          Storefront static assets + PHP app (waitlist signup form)
  terraform.tfvars                   real values, gitignored — see "Getting started"

backup/                 Separate Terraform root module: AWS Backup plan/vaults, one region each
  vault.tf                 primary vault (eu-west-2) + DR vault (eu-west-1), hourly backup plan
                             with cross-region copy_action; only the RDS instance is tagged
                             Backup=true — EC2/S3 are reproduced by Terraform instead, see Architecture
  monitoring.tf              CloudWatch alarms + EventBridge → SNS on backup/copy/restore job state,
                               one topic per region
  providers.tf, variables.tf, outputs.tf

restore_testing/        Separate Terraform root module: AWS Backup's native restore-testing plan
  main.tf                  aws_backup_restore_testing_plan + _selection (RDS only), targeting the
                             DR vault by name convention — no Terraform dependency on backup/'s state
  providers.tf, variables.tf, outputs.tf

scripts/                Python DR tooling (boto3), no separate test suite currently
  dr_lib.py                 shared RecoveryResult/RTO-RPO dataclass and dashboard history read/write
  record_dr_result.py        appends a dr_failover.yml drill's result to docs/data/history.json
  record_restore_testing_results.py
                               polls AWS Backup for newly completed restore-testing-plan jobs and
                                appends them to the same dashboard history file
  empty_backup_vault.py        deletes every recovery point in a vault (destroy.yml needs empty
                                 vaults before Terraform can destroy them)

docs/                   GitHub Pages dashboard (docs/index.html) plotting RTO/RPO history
  data/history.json       one JSON record per drill/test, appended to by the workflows below

.github/workflows/
  pr.yml                    terraform fmt/validate/plan against infra/ on every PR (no test step)
  main.yml                    manual (workflow_dispatch): terraform apply for infra/, backup/,
                                and/or restore_testing/, independently toggled
  dr_failover.yml               manual: re-applies infra/ into the DR region, restores RDS from
                                  the latest recovery point, smoke-checks, cuts Route 53 over,
                                  records the drill's RTO/RPO
  trigger_backup.yml              manual: on-demand RDS backup + copy into the DR vault, so a
                                    drill doesn't have to wait for the hourly backup schedule
  record_restore_testing.yml        polls restore_testing/'s AWS-scheduled restore-testing-plan
                                      jobs hourly and records newly completed ones to the dashboard
  destroy.yml                        manual + every 2 hours: tears down infra/ (both the primary
                                       state and any DR-region state a failover drill left behind),
                                       restore_testing/, and backup/, for cost control between
                                       demo/drill sessions
```

## Architecture

Six layers, matching Dissertation §3.2–3.3: application, backup, protection,
recovery, monitoring, and infrastructure-as-code/automation.

- **Application** — EC2 storefront (nginx + PHP-FPM), RDS MySQL, S3 (product
  assets), all inside one VPC across public/private subnets. The storefront's
  waitlist form (`site_src/signup.php`) writes real rows to RDS and
  `site_src/signups.php` reads them straight back — a live write path is
  what makes a DR restore provable rather than asserted.
- **Backup** — AWS Backup (`backup/vault.tf`) runs an hourly plan against
  the RDS instance (the only tier tagged `Backup=true` — EC2 is stateless and
  S3 objects are Terraform-managed, so both are reproduced by re-applying
  `infra/` rather than restored), copying every recovery point into a second
  vault in the DR region as soon as it's created.
- **Protection** — recovery points live in a vault separate from the
  primary-region resources they protect. Vault Lock (governance-mode
  immutability) is scaffolded in `backup/vault.tf` but currently commented
  out, not yet enabled.
- **Recovery** — `dr_failover.yml` runs a full environment failover (DR
  region re-apply, RDS restore, Route 53 cutover). Independently,
  `restore_testing/`'s AWS Backup restore-testing plan restores a sample
  recovery point on its own hourly, AWS-internal schedule and validates it,
  with `record_restore_testing_results.py` (polled by
  `record_restore_testing.yml`) folding completed jobs into the same
  dashboard. Both are AWS-native or Terraform-declared rather than a
  hand-rolled restore script.
- **Monitoring** — CloudWatch alarms on EC2 status checks and RDS free
  storage, CloudTrail audit logging, and (`backup/monitoring.tf`)
  CloudWatch + EventBridge → SNS alerting on backup/copy/restore job state
  in both regions. Failure detection that triggers a failover automatically
  is out of scope by design (see the comment at the top of
  `dr_failover.yml`) — a drill is started manually, exercising the same
  recovery path an alarm would.
- **IaC & automation** — everything above is Terraform (`infra/`, `backup/`,
  `restore_testing/` as three independent root modules/state, one shared S3
  backend, native S3 state locking rather than a separate DynamoDB table),
  applied and torn down via the GitHub Actions workflows above, all calling
  the one reusable `_terraform.yml` workflow rather than duplicating
  init/plan/apply/destroy logic per stack.

## Getting started

The S3 backend (`infra/providers.tf`) points at a fixed bucket, key, and
region, using Terraform's native S3 state locking (no separate DynamoDB
table). The bucket must exist before the first `terraform init` (created
once by hand, since Terraform can't create the backend it depends on to
run). Edit `providers.tf` directly if you need a different bucket/region/env.

```bash
cd infra
# create terraform.tfvars yourself (gitignored, not tracked — no example
# file ships in the repo) with at least db_password and app_domain_name set
terraform init
terraform plan
```

`db_password` and `alert_email` have no defaults — set them via
`terraform.tfvars` or `TF_VAR_db_password` / `TF_VAR_alert_email`.

## Demoing a full DR cycle

1. **Deploy primary infra** — run `main.yml` with `Deploy-Infra: true` (and
   `Deploy-Backup: true` / `Deploy-RestoreTesting: true` on first run, to
   create the backup plan/vaults and the restore-testing plan).
2. **Write live data** — submit the waitlist form on the storefront (or
   `curl -X POST http://<alb-dns>/signup.php -d '{"email":"demo@x.com"}'`),
   then confirm it at `/signups.php`, which reads straight from RDS.
3. **Force a fresh recovery point** — run `trigger_backup.yml` so the row
   just entered has a recovery point copied into the DR vault, instead of
   waiting for the hourly schedule.
4. **Fail over** — run `dr_failover.yml`. It re-applies `infra/` into the DR
   region under its own Terraform state, restores RDS from that recovery
   point, smoke-checks the new environment, and cuts Route 53 over.
5. **Verify** — load `/signups.php` on the DR ALB's DNS name: the same row
   is there, restored, proving the data survived the failover.
6. **Check the dashboard** — `docs/index.html` (GitHub Pages) now has one
   more RTO/RPO point from this drill, plus whatever AWS Backup's own
   restore-testing plan has independently validated on its own schedule.

Between sessions, `destroy.yml` tears everything down (primary, any
DR-region stack left by step 4, and `restore_testing/`) every 2 hours to
control cost — redeploy before the next demo if it's had time to run.

## CI/CD

- **`pr.yml`** — `terraform fmt -check`, `terraform validate`, and
  `terraform plan` against `infra/` on every pull request.
- **`main.yml`** — manual (`workflow_dispatch`) `terraform apply` for
  `infra/`, `backup/`, and/or `restore_testing/`, each independently
  toggled and gated behind the `development`/`backup` environments.
- **`trigger_backup.yml`** — manual on-demand RDS backup + DR-vault copy.
- **`dr_failover.yml`** — manual full-environment failover drill.
- **`record_restore_testing.yml`** — polls hourly for restore-testing-plan
  jobs AWS Backup has run on its own schedule and records completed ones to
  the dashboard; also runnable manually.
- **`destroy.yml`** — manual plus every 2 hours on a schedule; tears down
  `infra/` (primary state and any DR-region state), `restore_testing/`, and
  `backup/` in that order, emptying the backup vaults first since AWS
  Backup refuses to delete a non-empty one.

All workflows authenticate to AWS with long-lived access keys
(`secrets.AWS_ACCESS_KEY_PLATFORM` / `AWS_ACCESS_SECRET_KEY_PLATFORM`), an
acceptable simplification for this research testbed but not for a
production deployment.
