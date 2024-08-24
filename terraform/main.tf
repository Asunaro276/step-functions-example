terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>5.0"
    }
  }
}

provider "aws" {}

provider "random" {}

data "aws_caller_identity" "current_account" {}

data "aws_region" "current_region" {}

resource "random_string" "random" {
  length  = 4
  special = false
}

data "aws_iam_policy_document" "lambda_assume_role_policy" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = [
      "sts:AssumeRole",
    ]
  }
}

resource "aws_iam_role" "function_role" {
  assume_role_policy  = data.aws_iam_policy_document.lambda_assume_role_policy.json
  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"]
}

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

resource "aws_lambda_function" "test_lambda" {
  function_name    = "HelloFunction-${random_string.random.id}"
  s3_bucket        = aws_s3_bucket.lambda_assets.bucket
  s3_key           = data.aws_s3_object.package.key
  role             = aws_iam_role.function_role.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  source_code_hash = data.aws_s3_object.package_hash.body
  timeout          = "10"
}

# Explicitly create the function’s log group to set retention and allow auto-cleanup
resource "aws_cloudwatch_log_group" "lambda_function_log" {
  retention_in_days = 1
  name              = "/aws/lambda/${aws_lambda_function.test_lambda.function_name}"
  kms_key_id        = aws_kms_key.log_group_key.arn
}

# Create an IAM role for the Step Functions state machine
data "aws_iam_policy_document" "state_machine_assume_role_policy" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }

    actions = [
      "sts:AssumeRole",
    ]
  }
}

resource "aws_iam_role" "StateMachineRole" {
  name               = "StepFunctions-Terraform-Role-${random_string.random.id}"
  assume_role_policy = data.aws_iam_policy_document.state_machine_assume_role_policy.json
}

data "aws_iam_policy_document" "state_machine_role_policy" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams"
    ]
    resources = ["${aws_cloudwatch_log_group.MySFNLogGroup.arn}:*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "logs:*",
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "lambda:InvokeFunction"
    ]
    resources = ["${aws_lambda_function.test_lambda.arn}"]
  }

}

# Create an IAM policy for the Step Functions state machine
resource "aws_iam_role_policy" "StateMachinePolicy" {
  role   = aws_iam_role.StateMachineRole.id
  policy = data.aws_iam_policy_document.state_machine_role_policy.json
}

# Create a Log group for the state machine
resource "aws_cloudwatch_log_group" "MySFNLogGroup" {
  name_prefix       = "/aws/vendedlogs/states/MyStateMachine-"
  retention_in_days = 1
  kms_key_id        = aws_kms_key.log_group_key.arn
}

resource "aws_sfn_state_machine" "sfn_state_machine" {
  name     = "MyStateMachine-${random_string.random.id}"
  role_arn = aws_iam_role.StateMachineRole.arn
  definition = templatefile("${path.module}/../statemachine/statemachine.asl.json", {
    ProcessingLambda = aws_lambda_function.test_lambda.arn
    }
  )
  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.MySFNLogGroup.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }
}

locals {
  functions_codedir_local_path                        = "${path.module}/../functions"
  helloworld_function_dir_local_path                  = "${local.functions_codedir_local_path}/first-function"
  helloworld_function_package_local_path              = "${local.helloworld_function_dir_local_path}/dist/index.zip"
  helloworld_function_package_base64sha256_local_path = "${local.helloworld_function_package_local_path}.base64sha256"
  helloworld_function_package_s3_key                  = "first-function/index.zip"
  helloworld_function_package_base64sha256_s3_key     = "${local.helloworld_function_package_s3_key}.base64sha256.txt"
}

resource "null_resource" "lambda_build" {
  depends_on = [aws_s3_bucket.lambda_assets]

  provisioner "local-exec" {
    command = "cd ${local.helloworld_function_dir_local_path} && pnpm install"
  }
  provisioner "local-exec" {
    command = "cd ${local.helloworld_function_dir_local_path} && pnpm run build"
  }
  provisioner "local-exec" {
    command = "aws s3 cp ${local.helloworld_function_package_local_path} s3://${aws_s3_bucket.lambda_assets.bucket}/${local.helloworld_function_package_s3_key}"
  }
  provisioner "local-exec" {
    command = "openssl dgst -sha256 -binary ${local.helloworld_function_package_local_path} | openssl enc -base64 | tr -d \"\n\" > ${local.helloworld_function_package_base64sha256_local_path}"
  }
  provisioner "local-exec" {
    command = "aws s3 cp ${local.helloworld_function_package_base64sha256_local_path} s3://${aws_s3_bucket.lambda_assets.bucket}/${local.helloworld_function_package_base64sha256_s3_key} --content-type \"text/plain\""
  }

  triggers = {
    code_diff = join("", [
      for file in fileset(local.helloworld_function_dir_local_path, "{*.ts, package*.json}")
      : filebase64("${local.helloworld_function_dir_local_path}/${file}")
    ])
  }
}

resource "aws_s3_bucket" "lambda_assets" {}
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
  depends_on = [null_resource.lambda_build]

  bucket = aws_s3_bucket.lambda_assets.bucket
  key    = local.helloworld_function_package_s3_key
}
data "aws_s3_object" "package_hash" {
  depends_on = [null_resource.lambda_build]

  bucket = aws_s3_bucket.lambda_assets.bucket
  key    = local.helloworld_function_package_base64sha256_s3_key
}
