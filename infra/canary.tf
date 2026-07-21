# CloudWatch Synthetics canary: the failure-detection layer's first signal
# (Section 3.2/3.3). Runs the storefront/checkout journey on a fixed
# schedule so an outage is caught even at zero real customer traffic.

resource "aws_s3_bucket" "canary_artifacts" {
  count = local.is_primary_region ? 1 : 0

  bucket = "${local.name}-canary-artifacts-${data.aws_caller_identity.current.account_id}"

  tags = { Name = "${local.name}-canary-artifacts" }
}

resource "aws_s3_bucket_public_access_block" "canary_artifacts" {
  count = local.is_primary_region ? 1 : 0

  bucket = aws_s3_bucket.canary_artifacts[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "canary_artifacts" {
  count = local.is_primary_region ? 1 : 0

  bucket = aws_s3_bucket.canary_artifacts[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_iam_role" "canary" {
  count = local.is_primary_region ? 1 : 0

  name = "${local.name}-canary-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# Minimal permission set documented by AWS for a Synthetics canary execution
# role: write its own artifacts, publish its own metric namespace, and log.
resource "aws_iam_role_policy" "canary" {
  count = local.is_primary_region ? 1 : 0

  name = "${local.name}-canary-policy"
  role = aws_iam_role.canary[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetBucketLocation"]
        Resource = "${aws_s3_bucket.canary_artifacts[0].arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = "s3:ListAllMyBuckets"
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = "cloudwatch:PutMetricData"
        Resource = "*"
        Condition = {
          StringEquals = { "cloudwatch:namespace" = "CloudWatchSynthetics" }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:log-group:/aws/lambda/cwsyn-*"
      }
    ]
  })
}

data "archive_file" "canary" {
  type        = "zip"
  source_dir  = "${path.module}/canary_src"
  output_path = "${path.module}/canary.zip"
}

resource "aws_synthetics_canary" "storefront" {
  count = local.is_primary_region ? 1 : 0

  name                 = "${local.name}-canary"
  artifact_s3_location = "s3://${aws_s3_bucket.canary_artifacts[0].id}/canary"
  execution_role_arn   = aws_iam_role.canary[0].arn
  handler              = "canary.handler"
  zip_file             = data.archive_file.canary.output_path
  runtime_version      = "syn-nodejs-puppeteer-9.1"
  start_canary         = true

  schedule {
    expression = "rate(5 minutes)"
  }

  run_config {
    timeout_in_seconds = 30
    environment_variables = {
      TARGET_URL = "http://${aws_lb.web.dns_name}"
    }
  }
}
