data "aws_region" "current" {}
resource "aws_s3_bucket" "assets" {
  bucket = "${local.name}-assets-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"

  # The scheduled destroy workflow tears this bucket down every couple of
  # hours; without force_destroy, terraform destroy fails the moment the
  # bucket holds any object (or, since versioning is on below, any object
  # version/delete marker) instead of emptying it first.
  force_destroy = true

  tags = {
    Name = "${local.name}-assets"
  }
}

resource "aws_s3_bucket_versioning" "assets" {
  bucket = aws_s3_bucket.assets.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket = aws_s3_bucket.assets.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_website_configuration" "asset" {
  bucket = aws_s3_bucket.assets.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}
resource "aws_s3_bucket_ownership_controls" "static" {
  bucket = aws_s3_bucket.assets.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_object" "site_index" {
  bucket       = aws_s3_bucket.assets.id
  key          = "index.html"
  source       = "${path.module}/site_src/index.html"
  etag         = filemd5("${path.module}/site_src/index.html")
  content_type = "text/html"
}

resource "aws_s3_object" "site_error" {
  bucket       = aws_s3_bucket.assets.id
  key          = "error.html"
  source       = "${path.module}/site_src/error.html"
  etag         = filemd5("${path.module}/site_src/error.html")
  content_type = "text/html"
}

resource "aws_s3_object" "site_db_php" {
  bucket       = aws_s3_bucket.assets.id
  key          = "db.php"
  source       = "${path.module}/site_src/db.php"
  etag         = filemd5("${path.module}/site_src/db.php")
  content_type = "application/x-httpd-php"
}

resource "aws_s3_object" "site_signup_php" {
  bucket       = aws_s3_bucket.assets.id
  key          = "signup.php"
  source       = "${path.module}/site_src/signup.php"
  etag         = filemd5("${path.module}/site_src/signup.php")
  content_type = "application/x-httpd-php"
}

resource "aws_s3_object" "site_signups_php" {
  bucket       = aws_s3_bucket.assets.id
  key          = "signups.php"
  source       = "${path.module}/site_src/signups.php"
  etag         = filemd5("${path.module}/site_src/signups.php")
  content_type = "application/x-httpd-php"
}

# CLI-only seeder for realistic DR-drill data (see seed_data.yml), synced
# onto the instance the same way as the other PHP files even though it's
# never served over HTTP.
resource "aws_s3_object" "site_seed_php" {
  bucket       = aws_s3_bucket.assets.id
  key          = "seed.php"
  source       = "${path.module}/site_src/seed.php"
  etag         = filemd5("${path.module}/site_src/seed.php")
  content_type = "application/x-httpd-php"
}
# Separate bucket for CloudTrail logs (monitoring.tf) so trail delivery isn't
# tangled with product-asset lifecycle rules or bucket policy.
resource "aws_s3_bucket" "cloudtrail" {
  bucket = "${local.name}-cloudtrail-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"

  # Same reasoning as the assets bucket above: CloudTrail keeps delivering
  # log objects into this bucket, so it's never empty by the time the
  # scheduled destroy runs.
  force_destroy = true

  tags = { Name = "${local.name}-cloudtrail" }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.cloudtrail.arn
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      }
    ]
  })
}
