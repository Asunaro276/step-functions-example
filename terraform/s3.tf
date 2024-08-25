resource "aws_s3_bucket" "lambda_assets" {
  bucket = "lambda-assets-${random_string.random.id}"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lambda_assets" {
  bucket = aws_s3_bucket.lambda_assets.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "lambda_assets" {
  bucket = aws_s3_bucket.lambda_assets.bucket

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_s3_object" "package" {
  for_each   = local.function_package_s3_keys
  depends_on = [null_resource.lambda_build]

  bucket = aws_s3_bucket.lambda_assets.bucket
  key    = each.value
}
data "aws_s3_object" "package_hash" {
  for_each   = local.function_package_base64sha256_s3_keys
  depends_on = [null_resource.lambda_build]

  bucket = aws_s3_bucket.lambda_assets.bucket
  key    = each.value
}

resource "null_resource" "bucket_empty" {
  triggers = {
    bucket = aws_s3_bucket.lambda_assets.bucket
  }
  depends_on = [
    aws_s3_bucket.lambda_assets
  ]
  provisioner "local-exec" {
    when    = destroy
    command = "aws s3 rm s3://${self.triggers.bucket} --recursive"
  }
}
