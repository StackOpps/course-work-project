resource "aws_db_subnet_group" "main" {
  name       = "${local.name}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = { Name = "${local.name}-db-subnet-group" }
}

resource "aws_security_group" "db" {
  name        = "${local.name}-db-sg"
  description = "CraftHaven RDS access, restricted to the web tier"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL from web tier only"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name}-db-sg" }
}

# During a DR failover this apply runs with aws_region == var.dr_region, and
# needs to restore RDS from the latest recovery point AWS Backup copied into
# this region (backup/vault.tf's copy_action). Found directly with a data
# source instead of an external script threading an ARN through a separate
# CI job and a Terraform variable: AWS Backup's RDS recovery points are
# implemented as native RDS snapshots tagged SnapshotType=awsbackup, so
# they're visible to aws_db_snapshot like any other snapshot in the region.
data "aws_db_snapshot" "latest" {
  count = local.is_dr_region ? 1 : 0

  db_instance_identifier = "${local.name}-db"
  snapshot_type          = "awsbackup"
  most_recent            = true
}

resource "aws_db_instance" "main" {
  identifier     = "${local.name}-db"
  engine         = local.is_dr_region ? null : "mysql"
  engine_version = local.is_dr_region ? null : var.db_engine_version
  instance_class = var.db_instance_class

  # Restoring from AWS Backup's latest recovery point (DR failover) instead
  # of creating an empty instance: engine/db_name/username come from the
  # snapshot itself and must be left unset, but the password can still be
  # reset on top of the restored data (Terraform issues a ModifyDBInstance
  # call for it).
  snapshot_identifier = local.is_dr_region ? data.aws_db_snapshot.latest[0].id : null

  allocated_storage = local.is_dr_region ? null : var.db_allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = local.is_dr_region ? null : var.db_name
  username = local.is_dr_region ? null : var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  multi_az               = false

  # AWS Backup (see backup/) is the system of record for recovery points, so
  # native automated backups are kept short — just enough for point-in-time
  # recovery between AWS Backup's daily snapshots, not long-term retention.
  backup_retention_period = 3
  backup_window           = "02:00-02:30"
  maintenance_window      = "mon:03:30-mon:04:30"

  skip_final_snapshot       = var.environment != "prod"
  final_snapshot_identifier = var.environment == "prod" ? "${local.name}-db-final" : null
  deletion_protection       = var.environment == "prod"

  tags = {
    Name   = "${local.name}-db"
    Backup = "true"
  }
}
