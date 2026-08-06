data "aws_ssm_parameter" "al2023_ami" {
  count = var.ec2_ami_id == null ? 1 : 0
  name  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  ec2_ami_id = coalesce(var.ec2_ami_id, try(data.aws_ssm_parameter.al2023_ami[0].value, null))
}

resource "aws_security_group" "alb" {
  name        = "${local.name}-alb-sg"
  description = "CraftHaven storefront load balancer, public entry point"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name}-alb-sg" }
}

# The web tier only ever hears from the load balancer, per the dissertation's
# "EC2 behind an Application Load Balancer" design (Section 3.2) — nothing
# reaches the instance directly from the internet.
resource "aws_security_group" "web" {
  name        = "${local.name}-web-sg"
  description = "CraftHaven storefront web tier, reachable only via the ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from the load balancer only"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name}-web-sg" }
}

resource "aws_lb" "web" {
  name               = "${local.name}-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = { Name = "${local.name}-alb" }
}

resource "aws_lb_target_group" "web" {
  name     = "${local.name}-web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    matcher             = "200-399"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = { Name = "${local.name}-web-tg" }
}

resource "aws_lb_listener" "web_http" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "web_https" {
  load_balancer_arn = aws_lb.web.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.web.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

resource "aws_lb_target_group_attachment" "web" {
  target_group_arn = aws_lb_target_group.web.arn
  target_id        = aws_instance.crafthavens.id
  port             = 80
}

resource "aws_iam_role" "ec2" {
  name = "${local.name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# Session Manager instead of SSH keys/bastion hosts — no dedicated infra
# engineer to manage key distribution, per the dissertation's staffing constraint.
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "ec2_s3_assets" {
  name = "${local.name}-ec2-s3-assets"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
      Resource = [aws_s3_bucket.assets.arn, "${aws_s3_bucket.assets.arn}/*"]
    }]
  })
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${local.name}-ec2-profile"
  role = aws_iam_role.ec2.name
}

resource "aws_instance" "crafthavens" {
  ami                    = local.ec2_ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private[0].id
  vpc_security_group_ids = [aws_security_group.web.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  # nginx comes up before PHP-FPM is even attempted, and a PHP-FPM failure
  # is caught rather than left to `set -e`: the ALB health check and static
  # homepage only need nginx, so a broken PHP install must degrade the
  # waitlist form (/signup.php) rather than take the whole site down.
  user_data = <<EOF
#!/bin/bash
set -euxo pipefail
dnf install -y nginx

rm -rf /usr/share/nginx/html/*
aws s3 sync "s3://${aws_s3_bucket.assets.id}" /usr/share/nginx/html

cat > /etc/nginx/nginx.conf <<'NGINXCONF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    sendfile      on;
    keepalive_timeout 65;

    server {
        listen 80 default_server;
        server_name _;
        root /usr/share/nginx/html;
        index index.html index.php;

        error_page 404 /error.html;

        location / {
            try_files $uri $uri/ =404;
        }

        location ~ \.php$ {
            fastcgi_pass 127.0.0.1:9000;
            fastcgi_index index.php;
            fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
            include fastcgi_params;
            fastcgi_intercept_errors on;
            error_page 502 503 504 = @php_unavailable;
        }

        # PHP-FPM being down (failed install, crashed pool) must not surface
        # nginx's raw HTML error page to signup.php's fetch() caller, which
        # expects JSON and throws a confusing parse error on HTML.
        location @php_unavailable {
            default_type application/json;
            return 503 '{"error":"Signup is temporarily unavailable, please try again shortly."}';
        }
    }
}
NGINXCONF

systemctl enable --now nginx

if dnf install -y php php-fpm php-pdo php-mysqlnd; then
  # DB_PASSWORD is base64-encoded here and decoded in db.php: it may contain
  # ini-special characters (e.g. ~, ", ;) that would otherwise break parsing
  # of this whole file if the raw password were interpolated unquoted.
  cat >> /etc/php-fpm.d/www.conf <<'PHPENV'

env[DB_HOST] = ${aws_db_instance.main.address}
env[DB_NAME] = ${var.db_name}
env[DB_USER] = ${var.db_username}
env[DB_PASSWORD_B64] = ${base64encode(var.db_password)}
PHPENV
  sed -i 's/^listen = .*/listen = 127.0.0.1:9000/' /etc/php-fpm.d/www.conf
  systemctl enable --now php-fpm
  systemctl reload nginx
else
  echo "PHP package install failed; waitlist form will be unavailable but the storefront stays up" >&2
fi
EOF

  depends_on = [
    aws_s3_object.site_index,
    aws_s3_object.site_error,
    aws_s3_object.site_db_php,
    aws_s3_object.site_signup_php,
    aws_s3_object.site_signups_php,
  ]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "${local.name}-web"
  }
}