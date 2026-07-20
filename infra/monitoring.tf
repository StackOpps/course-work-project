resource "aws_sns_topic" "alerts" {
  name = "${local.name}-alerts"
}

resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_sns_topic_policy" "allow_eventbridge" {
  arn = aws_sns_topic.alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEventBridgePublish"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "SNS:Publish"
      Resource  = aws_sns_topic.alerts.arn
    }]
  })
}

resource "aws_cloudtrail" "main" {
  name                          = "${local.name}-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}

resource "aws_cloudwatch_metric_alarm" "ec2_status_check" {
  alarm_name          = "${local.name}-ec2-status-check-failed"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  statistic           = "Maximum"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  period              = 60
  evaluation_periods  = 3
  alarm_description   = "CraftHaven web instance failing EC2 status checks"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    InstanceId = aws_instance.web.id
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_free_storage" {
  alarm_name          = "${local.name}-rds-low-free-storage"
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  statistic           = "Average"
  comparison_operator = "LessThanThreshold"
  threshold           = 2147483648 # 2 GiB
  period              = 300
  evaluation_periods  = 2
  alarm_description   = "CraftHaven RDS instance running low on free storage"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }
}

resource "aws_cloudwatch_metric_alarm" "backup_job_failed" {
  alarm_name          = "${local.name}-backup-jobs-failed"
  namespace           = "AWS/Backup"
  metric_name         = "NumberOfBackupJobsFailed"
  statistic           = "Sum"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  period              = 3600
  evaluation_periods  = 1
  alarm_description   = "CraftHaven AWS Backup job failed for a monitored resource"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"
}

# EventBridge catches every backup/restore state transition, not just
# failures — this is what makes recovery-job completion visible without
# polling the AWS Backup API indefinitely from restore_test.py.
resource "aws_cloudwatch_event_rule" "backup_state_change" {
  name = "${local.name}-backup-state-change"

  event_pattern = jsonencode({
    source      = ["aws.backup"]
    detail-type = ["Backup Job State Change", "Restore Job State Change"]
  })
}

resource "aws_cloudwatch_event_target" "backup_state_change_sns" {
  rule      = aws_cloudwatch_event_rule.backup_state_change.name
  target_id = "${local.name}-backup-alerts"
  arn       = aws_sns_topic.alerts.arn
}

# --- Failure detection & failover (Section 3.2/3.3) ------------------------
# Three independent signals — the Synthetics canary, ALB error/health alarms,
# and AWS Health events — feed a composite alarm so a single blip can't
# trigger a failover. All of it is primary-region-only so a DR re-apply of
# this same configuration doesn't stand up a second detection pipeline.

resource "aws_cloudwatch_metric_alarm" "canary_failure" {
  count = local.is_primary_region ? 1 : 0

  alarm_name          = "${local.name}-canary-failure"
  namespace           = "CloudWatchSynthetics"
  metric_name         = "SuccessPercent"
  statistic           = "Average"
  comparison_operator = "LessThanThreshold"
  threshold           = 100
  period              = 300
  evaluation_periods  = 3
  treat_missing_data  = "breaching"
  alarm_description   = "CraftHaven storefront canary failed its browse/checkout journey"

  dimensions = {
    CanaryName = aws_synthetics_canary.storefront[0].name
  }
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx_errors" {
  count = local.is_primary_region ? 1 : 0

  alarm_name          = "${local.name}-alb-5xx-errors"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 5
  period              = 60
  evaluation_periods  = 3
  treat_missing_data  = "notBreaching"
  alarm_description   = "CraftHaven ALB seeing elevated HTTP 5XX responses from the web tier"

  dimensions = {
    LoadBalancer = aws_lb.web.arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
  count = local.is_primary_region ? 1 : 0

  alarm_name          = "${local.name}-alb-unhealthy-hosts"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  statistic           = "Average"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  period              = 60
  evaluation_periods  = 3
  treat_missing_data  = "breaching"
  alarm_description   = "CraftHaven ALB target group has no healthy web instances"

  dimensions = {
    LoadBalancer = aws_lb.web.arn_suffix
    TargetGroup  = aws_lb_target_group.web.arn_suffix
  }
}

resource "aws_cloudwatch_composite_alarm" "site_down" {
  count = local.is_primary_region ? 1 : 0

  alarm_name        = "${local.name}-site-down"
  alarm_description = "CraftHaven storefront confirmed down: triggers the automated restore workflow"

  alarm_rule = join(" OR ", [
    "ALARM(${aws_cloudwatch_metric_alarm.canary_failure[0].alarm_name})",
    "ALARM(${aws_cloudwatch_metric_alarm.alb_5xx_errors[0].alarm_name})",
    "ALARM(${aws_cloudwatch_metric_alarm.alb_unhealthy_hosts[0].alarm_name})",
  ])

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

# Authenticates to the GitHub REST API with a fine-grained PAT so the two
# rules below can call repository_dispatch and start the restore workflow
# without a human noticing the outage first.
resource "aws_cloudwatch_event_connection" "github" {
  count = local.is_primary_region ? 1 : 0

  name               = "${local.name}-github"
  authorization_type = "API_KEY"

  auth_parameters {
    api_key {
      key   = "Authorization"
      value = "Bearer ${var.github_pat}"
    }
  }
}

resource "aws_cloudwatch_event_api_destination" "github_dispatch" {
  count = local.is_primary_region ? 1 : 0

  name                = "${local.name}-github-dispatch"
  connection_arn      = aws_cloudwatch_event_connection.github[0].arn
  invocation_endpoint = "https://api.github.com/repos/${var.github_owner}/${var.github_repo}/dispatches"
  http_method         = "POST"
}

resource "aws_iam_role" "eventbridge_dr_trigger" {
  count = local.is_primary_region ? 1 : 0

  name = "${local.name}-eventbridge-dr-trigger"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "eventbridge_dr_trigger" {
  count = local.is_primary_region ? 1 : 0

  name = "${local.name}-eventbridge-dr-trigger"
  role = aws_iam_role.eventbridge_dr_trigger[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "events:InvokeApiDestination"
      Resource = aws_cloudwatch_event_api_destination.github_dispatch[0].arn
    }]
  })
}

resource "aws_cloudwatch_event_rule" "composite_alarm_triggered" {
  count = local.is_primary_region ? 1 : 0

  name = "${local.name}-composite-alarm-triggered"

  event_pattern = jsonencode({
    source      = ["aws.cloudwatch"]
    detail-type = ["CloudWatch Alarm State Change"]
    resources   = [aws_cloudwatch_composite_alarm.site_down[0].arn]
    detail      = { state = { value = ["ALARM"] } }
  })
}

resource "aws_cloudwatch_event_target" "composite_alarm_dispatch" {
  count = local.is_primary_region ? 1 : 0

  rule      = aws_cloudwatch_event_rule.composite_alarm_triggered[0].name
  target_id = "${local.name}-composite-alarm-dispatch"
  arn       = aws_cloudwatch_event_api_destination.github_dispatch[0].arn
  role_arn  = aws_iam_role.eventbridge_dr_trigger[0].arn

  input = jsonencode({
    event_type = "dr-composite-alarm"
  })

  http_target {
    header_parameters = {
      "Accept"       = "application/vnd.github+json"
      "Content-Type" = "application/json"
    }
  }
}

# AWS Health events (region/service incidents CloudWatch metrics can't
# explain on their own) are a second, independent trigger for the same
# restore workflow — not folded into the composite alarm's boolean
# expression since they aren't CloudWatch alarms.
resource "aws_cloudwatch_event_rule" "aws_health_event" {
  count = local.is_primary_region ? 1 : 0

  name = "${local.name}-aws-health-event"

  event_pattern = jsonencode({
    source      = ["aws.health"]
    detail-type = ["AWS Health Event"]
    detail      = { service = ["EC2", "RDS"] }
  })
}

resource "aws_cloudwatch_event_target" "aws_health_event_dispatch" {
  count = local.is_primary_region ? 1 : 0

  rule      = aws_cloudwatch_event_rule.aws_health_event[0].name
  target_id = "${local.name}-aws-health-dispatch"
  arn       = aws_cloudwatch_event_api_destination.github_dispatch[0].arn
  role_arn  = aws_iam_role.eventbridge_dr_trigger[0].arn

  input = jsonencode({
    event_type = "dr-aws-health"
  })

  http_target {
    header_parameters = {
      "Accept"       = "application/vnd.github+json"
      "Content-Type" = "application/json"
    }
  }
}
