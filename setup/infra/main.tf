provider "aws" {}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "oidc_bucket" {
  bucket_prefix = "${data.aws_caller_identity.current.account_id}-kind-oidc-"
}

resource "aws_s3_bucket_public_access_block" "oidc_bucket_access" {
  bucket = aws_s3_bucket.oidc_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "allow_public_read" {
  depends_on = [aws_s3_bucket_public_access_block.oidc_bucket_access]
  bucket     = aws_s3_bucket.oidc_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.oidc_bucket.arn}/*"
      },
    ]
  })
}

resource "aws_s3_object" "discovery_json" {
  bucket       = aws_s3_bucket.oidc_bucket.id
  key          = ".well-known/openid-configuration"
  content_type = "application/json"

  content = jsonencode({
    issuer                                = "https://s3.${data.aws_region.current.region}.amazonaws.com/${aws_s3_bucket.oidc_bucket.id}"
    jwks_uri                              = "https://s3.${data.aws_region.current.region}.amazonaws.com/${aws_s3_bucket.oidc_bucket.id}/keys.json"
    authorization_endpoint                = "urn:kubernetes:programmatic_authorization"
    response_types_supported              = ["id_token"]
    subject_types_supported               = ["public"]
    id_token_signing_alg_values_supported = ["RS256"]
    claims_supported                      = ["sub", "iss"]
  })
}

resource "aws_s3_object" "keys_json" {
  bucket       = aws_s3_bucket.oidc_bucket.id
  key          = "keys.json"
  source       = "../../keys.json"
  content_type = "application/json"
  etag         = filemd5("../../keys.json")
}

data "tls_certificate" "s3" {
  url = "https://s3.${data.aws_region.current.region}.amazonaws.com"
}

resource "aws_iam_openid_connect_provider" "oidc_provider" {
  depends_on = [aws_s3_object.discovery_json, aws_s3_object.keys_json]

  url             = "https://s3.${data.aws_region.current.region}.amazonaws.com/${aws_s3_bucket.oidc_bucket.bucket}"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = data.tls_certificate.s3.certificates[*].sha1_fingerprint
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.oidc_provider.arn
}

output "oidc_bucket_name" {
  value = aws_s3_bucket.oidc_bucket.id
}
