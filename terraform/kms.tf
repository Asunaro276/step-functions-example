resource "aws_kms_key" "log_group_key" {}

resource "aws_kms_key_policy" "log_group_key_policy" {
  key_id = aws_kms_key.log_group_key.id
  policy = jsonencode({
    Id = "log_group_key_policy"
    Statement = [
      {
        Action = "kms:*"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current_account.account_id}:root"
        }

        Resource = "*"
        Sid      = "Enable IAM User Permissions"
      },
      {
        Effect = "Allow",
        Principal = {
          Service : "logs.${data.aws_region.current_region.name}.amazonaws.com"
        },
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*"
        ],
        Resource = "*"
      }
    ]
    Version = "2012-10-17"
  })
}
