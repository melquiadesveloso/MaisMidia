terraform {
  required_version = ">= 1.4.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4.0"
    }
  }
}

provider "aws" {
  region = var.region
}

resource "aws_s3_bucket" "media_bucket" {
  bucket = var.bucket_name
  tags = { Project = var.project_name, Environment = var.environment }
}

resource "aws_cloudfront_origin_access_identity" "oai" {
  comment = "OAI for media bucket"
}

resource "aws_s3_bucket_public_access_block" "pab" {
  bucket                  = aws_s3_bucket.media_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "s3_policy" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.media_bucket.arn}/*"]
    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.oai.iam_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "bucket_policy" {
  bucket = aws_s3_bucket.media_bucket.id
  policy = data.aws_iam_policy_document.s3_policy.json
}

resource "aws_cloudfront_distribution" "cdn" {
  enabled         = true
  is_ipv6_enabled = true
  default_root_object = "index.html"

  origin {
    domain_name = aws_s3_bucket.media_bucket.bucket_regional_domain_name
    origin_id   = "s3-media"
    s3_origin_config { origin_access_identity = aws_cloudfront_origin_access_identity.oai.cloudfront_access_identity_path }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "s3-media"
    viewer_protocol_policy = "redirect-to-https"
    forwarded_values { query_string = false }
    default_ttl = 3600
    max_ttl     = 86400
    min_ttl     = 0
  }

  price_class = "PriceClass_100"

  restrictions { geo_restriction { restriction_type = "none" } }

  viewer_certificate { cloudfront_default_certificate = true }
}

resource "aws_dynamodb_table" "academies" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "academy_id"

  attribute { name = "academy_id" type = "S" }
  tags = { Project = var.project_name, Environment = var.environment }
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambda"
  output_path = "${path.module}/../../lambda.zip"
}

resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-${var.environment}-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy" "lambda_inline" {
  name = "${var.project_name}-${var.environment}-lambda-policy"
  role = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { Effect = "Allow", Action = ["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents"], Resource = "arn:aws:logs:*:*:*" },
      { Effect = "Allow", Action = ["s3:GetObject","s3:ListBucket"], Resource = [aws_s3_bucket.media_bucket.arn, "${aws_s3_bucket.media_bucket.arn}/*"] },
      { Effect = "Allow", Action = ["dynamodb:GetItem","dynamodb:Query","dynamodb:Scan"], Resource = aws_dynamodb_table.academies.arn }
    ]
  })
}

resource "aws_lambda_function" "api" {
  function_name = "${var.project_name}-${var.environment}-media-api"
  role          = aws_iam_role.lambda_role.arn
  handler       = "app.lambda_handler"
  runtime       = "python3.11"
  filename      = data.archive_file.lambda_zip.output_path
  timeout       = 30
  memory_size   = 512

  environment {
    variables = {
      S3_BUCKET_NAME           = aws_s3_bucket.media_bucket.bucket
      CLOUDFRONT_DOMAIN        = aws_cloudfront_distribution.cdn.domain_name
      DYNAMODB_TABLE           = aws_dynamodb_table.academies.name
      DEFAULT_INTERVAL_SECONDS = 10
    }
  }
}

resource "aws_api_gateway_rest_api" "api" { name = "${var.project_name}-${var.environment}-api" }
resource "aws_api_gateway_resource" "academies" { rest_api_id = aws_api_gateway_rest_api.api.id parent_id = aws_api_gateway_rest_api.api.root_resource_id path_part = "academies" }
resource "aws_api_gateway_resource" "academy_id" { rest_api_id = aws_api_gateway_rest_api.api.id parent_id = aws_api_gateway_resource.academies.id path_part = "{academy_id}" }
resource "aws_api_gateway_resource" "playlist" { rest_api_id = aws_api_gateway_rest_api.api.id parent_id = aws_api_gateway_resource.academy_id.id path_part = "playlist" }

resource "aws_api_gateway_method" "get_playlist" { rest_api_id = aws_api_gateway_rest_api.api.id resource_id = aws_api_gateway_resource.playlist.id http_method = "GET" authorization = "NONE" }
resource "aws_api_gateway_integration" "get_playlist" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.playlist.id
  http_method = aws_api_gateway_method.get_playlist.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.api.arn}/invocations"
}

resource "aws_api_gateway_method" "get_academy" { rest_api_id = aws_api_gateway_rest_api.api.id resource_id = aws_api_gateway_resource.academy_id.id http_method = "GET" authorization = "NONE" }
resource "aws_api_gateway_integration" "get_academy" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.academy_id.id
  http_method = aws_api_gateway_method.get_academy.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.api.arn}/invocations"
}

resource "aws_lambda_permission" "allow_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "deploy" {
  depends_on = [
    aws_api_gateway_integration.get_playlist,
    aws_api_gateway_integration.get_academy,
  ]
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "prod"
}




