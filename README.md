# CraftHaven — AWS Disaster Recovery & Backup

Implementation supporting *A Cost-Effective, Automated Disaster Recovery and
Backup Infrastructure for Small Business on AWS* (`Dissertation-draft.docx`).
CraftHaven is the dissertation's fictional small e-commerce vendor. This repo
provisions its AWS environment and the automation that backs it up, protects
it, and recovers it.

## Getting started

The S3 backend (`infra/providers.tf`) points at a fixed bucket, key, and
region, using Terraform's native S3 state locking (no separate DynamoDB
table). The bucket must exist before the first `terraform init` — create it
by hand once, since Terraform can't create the backend it depends on.

```bash
cd infra
# create terraform.tfvars yourself (gitignored, not tracked) with at least
# db_password and app_domain_name set
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
   just entered gets copied into the DR vault, instead of waiting for the
   hourly schedule.
4. **Fail over** — run `dr_failover.yml`. It re-applies `infra/` into the DR
   region under its own Terraform state, restores RDS from that recovery
   point, smoke-checks the new environment, and cuts Route 53 over.
5. **Verify** — load `/signups.php` on the DR ALB's DNS name: the same row
   is there, restored, proving the data survived the failover.
6. **Check the dashboard** — `docs/index.html` (GitHub Pages) now has one
   more RTO/RPO point from this drill, restore-testing results AWS Backup
   validated on its own schedule, and daily whole-account cost from Cost
   Explorer.

`destroy.yml` tears `infra/` and `restore_testing/` down every 2 hours
between sessions to bound compute cost — redeploy before the next demo.
`backup/`'s vaults are left up (see Protection below) and are only torn down
on manual dispatch.

## Protection

AWS Backup Vault Lock is enabled in Terraform for both the primary and DR
vaults, with a 1-day minimum retention — no one, including the account root
user, can delete a recovery point before it passes. That's why `backup/` sits
outside the 2-hourly teardown: emptying a locked vault before its retention
window elapses simply fails, so it's destroyed manually instead, once that
window has passed.

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
- **`record_cost.yml`** — polls AWS Cost Explorer daily for whole-account
  spend and records it to the dashboard; also runnable manually.
- **`destroy.yml`** — `infra/` and `restore_testing/` on a 2-hour schedule
  (plus manual dispatch); `backup/`'s vaults only on manual dispatch, since
  Vault Lock blocks emptying them until the retention window passes.

All workflows authenticate to AWS with long-lived access keys
(`secrets.AWS_ACCESS_KEY_PLATFORM` / `AWS_ACCESS_SECRET_KEY_PLATFORM`), an
acceptable simplification for this research testbed but not for a
production deployment.
