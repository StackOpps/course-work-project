# --- Primary region: the daily backup job against the primary vault -------

resource "aws_sns_topic" "alerts_primary" {
  provider = aws.primary
  name     = "${local.name}-backup-alerts"
}

resource "aws_sns_topic_subscription" "alerts_primary_email" {
  provider  = aws.primary
  topic_arn = aws_sns_topic.alerts_primary.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_sns_topic_policy" "allow_eventbridge_primary" {
  provider = aws.primary
  arn      = aws_sns_topic.alerts_primary.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEventBridgePublish"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "SNS:Publish"
      Resource  = aws_sns_topic.alerts_primary.arn
    }]
  })
}

resource "aws_cloudwatch_metric_alarm" "backup_job_failed_primary" {
  provider = aws.primary

  alarm_name          = "${local.name}-backup-jobs-failed"
  namespace           = "AWS/Backup"
  metric_name         = "NumberOfBackupJobsFailed"
  statistic           = "Sum"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  period              = 3600
  evaluation_periods  = 1
  alarm_description   = "CraftHaven AWS Backup job failed for a monitored resource (primary region)"
  alarm_actions       = [aws_sns_topic.alerts_primary.arn]
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_event_rule" "backup_state_change_primary" {
  provider = aws.primary
  name     = "${local.name}-backup-state-change"

  event_pattern = jsonencode({
    source      = ["aws.backup"]
    detail-type = ["Backup Job State Change", "Restore Job State Change", "Copy Job State Change"]
  })
}

resource "aws_cloudwatch_event_target" "backup_state_change_sns_primary" {
  provider  = aws.primary
  rule      = aws_cloudwatch_event_rule.backup_state_change_primary.name
  target_id = "${local.name}-backup-alerts"
  arn       = aws_sns_topic.alerts_primary.arn
}

# --- DR region: the copy job into the DR vault, and any restore activity --
# Independent of the primary region's health — if the primary region is
# down, no new backup jobs run there (nothing to alert on), but a restore
# from the DR vault during failover still needs its own alerting path.

resource "aws_sns_topic" "alerts_dr" {
  provider = aws.dr
  name     = "${local.name}-backup-alerts-dr"
}

resource "aws_sns_topic_subscription" "alerts_dr_email" {
  provider  = aws.dr
  topic_arn = aws_sns_topic.alerts_dr.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_sns_topic_policy" "allow_eventbridge_dr" {
  provider = aws.dr
  arn      = aws_sns_topic.alerts_dr.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEventBridgePublish"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "SNS:Publish"
      Resource  = aws_sns_topic.alerts_dr.arn
    }]
  })
}

resource "aws_cloudwatch_metric_alarm" "backup_job_failed_dr" {
  provider = aws.dr

  alarm_name          = "${local.name}-backup-jobs-failed-dr"
  namespace           = "AWS/Backup"
  metric_name         = "NumberOfBackupJobsFailed"
  statistic           = "Sum"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  period              = 3600
  evaluation_periods  = 1
  alarm_description   = "CraftHaven AWS Backup copy or restore job failed in the DR region"
  alarm_actions       = [aws_sns_topic.alerts_dr.arn]
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_event_rule" "backup_state_change_dr" {
  provider = aws.dr
  name     = "${local.name}-backup-state-change-dr"

  event_pattern = jsonencode({
    source      = ["aws.backup"]
    detail-type = ["Backup Job State Change", "Restore Job State Change", "Copy Job State Change"]
  })
}

resource "aws_cloudwatch_event_target" "backup_state_change_sns_dr" {
  provider  = aws.dr
  rule      = aws_cloudwatch_event_rule.backup_state_change_dr.name
  target_id = "${local.name}-backup-alerts-dr"
  arn       = aws_sns_topic.alerts_dr.arn
}
