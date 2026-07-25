# Site-down detection and the trigger for the automated restore workflow
# (Section 3.2/3.3). Used to be a composite alarm combining a Synthetics
# canary, ALB error/health alarms, and AWS Health events — all running in
# the primary region, which meant a real primary-region outage could kill
# the detector along with the workload it was watching.
#
# A Route 53 health check is evaluated by AWS's own distributed checker
# fleet from outside any single region, over the public internet — not
# through the primary region's internal control plane — so it keeps
# reporting status even if the primary region's CloudWatch/EventBridge are
# themselves impaired. Its CloudWatch metric is only ever published to
# us-east-1 (see providers.tf), so the alarm and dispatch below live there
# too, deliberately outside both the primary and DR regions.

resource "aws_route53_health_check" "storefront" {
  provider = aws.health_check

  fqdn              = var.app_domain_name
  port              = 443
  type              = "HTTPS"
  resource_path     = "/"
  failure_threshold = 3
  request_interval  = 30

  tags = { Name = "${local.name}-storefront-health-check" }
}

resource "aws_sns_topic" "alerts_health_check" {
  provider = aws.health_check
  name     = "${local.name}-site-down-alerts"
}

resource "aws_sns_topic_subscription" "alerts_health_check_email" {
  provider  = aws.health_check
  topic_arn = aws_sns_topic.alerts_health_check.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_sns_topic_policy" "allow_eventbridge_health_check" {
  provider = aws.health_check
  arn      = aws_sns_topic.alerts_health_check.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEventBridgePublish"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "SNS:Publish"
      Resource  = aws_sns_topic.alerts_health_check.arn
    }]
  })
}

resource "aws_cloudwatch_metric_alarm" "site_down" {
  provider = aws.health_check

  alarm_name          = "${local.name}-site-down"
  namespace           = "AWS/Route53"
  metric_name         = "HealthCheckStatus"
  statistic           = "Minimum"
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  period              = 60
  evaluation_periods  = 3
  treat_missing_data  = "breaching"
  alarm_description   = "CraftHaven storefront confirmed unreachable from outside AWS: triggers the automated restore workflow"
  alarm_actions       = [aws_sns_topic.alerts_health_check.arn]
  ok_actions          = [aws_sns_topic.alerts_health_check.arn]

  dimensions = {
    HealthCheckId = aws_route53_health_check.storefront.id
  }
}

# Authenticates to the GitHub REST API with a fine-grained PAT so the rule
# below can call repository_dispatch and start the restore workflow without
# a human noticing the outage first.
resource "aws_cloudwatch_event_connection" "github" {
  provider = aws.health_check

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
  provider = aws.health_check

  name                = "${local.name}-github-dispatch"
  connection_arn      = aws_cloudwatch_event_connection.github.arn
  invocation_endpoint = "https://api.github.com/repos/${var.github_owner}/${var.github_repo}/dispatches"
  http_method         = "POST"
}

resource "aws_iam_role" "eventbridge_dr_trigger" {
  provider = aws.health_check

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
  provider = aws.health_check

  name = "${local.name}-eventbridge-dr-trigger"
  role = aws_iam_role.eventbridge_dr_trigger.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "events:InvokeApiDestination"
      Resource = aws_cloudwatch_event_api_destination.github_dispatch.arn
    }]
  })
}

resource "aws_cloudwatch_event_rule" "site_down_triggered" {
  provider = aws.health_check

  name = "${local.name}-site-down-triggered"

  event_pattern = jsonencode({
    source      = ["aws.cloudwatch"]
    detail-type = ["CloudWatch Alarm State Change"]
    resources   = [aws_cloudwatch_metric_alarm.site_down.arn]
    detail      = { state = { value = ["ALARM"] } }
  })
}

resource "aws_cloudwatch_event_target" "site_down_dispatch" {
  provider = aws.health_check

  rule      = aws_cloudwatch_event_rule.site_down_triggered.name
  target_id = "${local.name}-site-down-dispatch"
  arn       = aws_cloudwatch_event_api_destination.github_dispatch.arn
  role_arn  = aws_iam_role.eventbridge_dr_trigger.arn

  input = jsonencode({
    event_type = "dr-route53-health-check"
  })

  http_target {
    header_parameters = {
      "Accept"       = "application/vnd.github+json"
      "Content-Type" = "application/json"
    }
  }
}
