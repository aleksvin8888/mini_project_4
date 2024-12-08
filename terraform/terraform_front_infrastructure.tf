terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.35.0"
    }
  }
}
provider "aws" {
  region = var.region
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

locals {
  s3_bucket_name = "s3-${var.frontend_subdomain}.${var.main_domain_name}"
}

resource "aws_s3_bucket" "frontend_bucket" {
  bucket        = local.s3_bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_policy" "frontend_policy" {
  bucket = aws_s3_bucket.frontend_bucket.id

  policy = jsonencode({
    Version = "2012-10-17",
     Statement = [
      {
        Sid       = "AllowCloudFrontAccess",
        Effect    = "Allow",
        Principal = {
          AWS = aws_cloudfront_origin_access_identity.s3_access.iam_arn
        },
        Action    = "s3:GetObject",
        Resource  = "${aws_s3_bucket.frontend_bucket.arn}/*"
      }
    ]
  })
}

resource "aws_cloudfront_origin_access_identity" "s3_access" {
  comment = "Access Identity for S3 frontend bucket"
}

resource "aws_cloudfront_distribution" "frontend_distribution" {
  depends_on = [
    aws_s3_bucket_policy.frontend_policy,
    aws_cloudfront_origin_access_identity.s3_access,
    aws_acm_certificate_validation.frontend_cert_validation
  ]

  default_root_object = "index.html"

  // origin Визначає джерело контенту, яке CloudFront обслуговуватиме.
  origin {
    //   динамічно отримуємо доменне ім'я S3-бакета.
    domain_name = aws_s3_bucket.frontend_bucket.bucket_regional_domain_name
    origin_id   = "frontendS3Origin"

    // Налаштування для підключення до S3.
   s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.s3_access.cloudfront_access_identity_path
    }
  }
  // Вмикає CloudFront Distribution.
  enabled = true

  // Визначає поведінку кешування для CloudFront.
  default_cache_behavior {
    // Кешуються тільки GET і HEAD (вони відповідають за статичний контент).
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "frontendS3Origin"

    // Налаштування для пересилання запитів
    forwarded_values {
      // Не пересилає параметри запиту (наприклад, ?key=value)
      query_string = false
      // Не пересилає куки.
      cookies {
        forward = "none"
      }
    }
   // Примусово перенаправляє всі запити HTTP на HTTPS.
    viewer_protocol_policy = "redirect-to-https"
  }
  // Налаштування SSL-сертифіката для CloudFront.
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.frontend_cert_validation.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

   aliases = ["${var.frontend_subdomain}.${var.main_domain_name}"]

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name = "CloudFrontFrontend"
  }
}

output "cloud_front_distribution_id" {
  value = aws_cloudfront_distribution.frontend_distribution.id
}
