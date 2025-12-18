resource "aws_iam_role" "lab_role" {
  name = "devops-lab-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.oidc_provider.arn
      }
      Condition = {
        StringEquals = {
          "${replace(aws_iam_openid_connect_provider.oidc_provider.url, "https://", "")}:sub" : "system:serviceaccount:bookinfo:bookinfo-sa"
        }
      }
    }]
  })
}

# Test permission policy to validate IRSA
resource "aws_iam_role_policy" "s3_read" {
  name = "s3-read-access"
  role = aws_iam_role.lab_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = ["s3:ListAllMyBuckets", "s3:GetBucketLocation"]
      Effect   = "Allow"
      Resource = "*"
    }]
  })
}

output "role_arn" {
  value = aws_iam_role.lab_role.arn
}
