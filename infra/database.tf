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

resource "aws_db_instance" "main" {
  identifier     = "${local.name}-db"
  engine         = var.db_snapshot_identifier == "" ? "mysql" : null
  engine_version = var.db_snapshot_identifier == "" ? var.db_engine_version : null
  instance_class = var.db_instance_class

  # Restoring from a recovery point (DR failover) instead of creating an
  # empty instance: engine/db_name/username come from the snapshot itself
  # and must be left unset, but the password can still be reset on top of
  # the restored data (Terraform issues a ModifyDBInstance call for it).
  snapshot_identifier = var.db_snapshot_identifier != "" ? var.db_snapshot_identifier : null

  allocated_storage = var.db_snapshot_identifier == "" ? var.db_allocated_storage : null
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_snapshot_identifier == "" ? var.db_name : null
  username = var.db_snapshot_identifier == "" ? var.db_username : null
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
