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
  length  = 8
  special = false
  upper   = false
}

resource "null_resource" "lambda_build" {
  for_each   = toset(local.function_names)
  depends_on = [aws_s3_bucket.lambda_assets]

  provisioner "local-exec" {
    command = "cd ${local.function_dir_local_paths[each.key]} && pnpm install"
  }
  provisioner "local-exec" {
    command = "cd ${local.function_dir_local_paths[each.key]} && pnpm run build"
  }
  provisioner "local-exec" {
    command = "aws s3 cp ${local.function_package_local_paths[each.key]} s3://${aws_s3_bucket.lambda_assets.bucket}/${local.function_package_s3_keys[each.key]}"
  }
  provisioner "local-exec" {
    command = "openssl dgst -sha256 -binary ${local.function_package_local_paths[each.key]} | openssl enc -base64 | tr -d \"\n\" > ${local.function_package_base64sha256_local_paths[each.key]}"
  }
  provisioner "local-exec" {
    command = "aws s3 cp ${local.function_package_base64sha256_local_paths[each.key]} s3://${aws_s3_bucket.lambda_assets.bucket}/${local.function_package_base64sha256_s3_keys[each.key]} --content-type \"text/plain\""
  }

  triggers = {
    code_diff = join("", [
      for file in fileset(local.function_dir_local_paths[each.key], "{*.ts, package*.json}")
      : filebase64("${local.function_dir_local_paths[each.key]}/${file}")
    ])
  }
}
terraform {
  backend "s3" {
    bucket = "tfstate-nakano"
    key    = "step-functions-example/terraform.tfstate"
    region = "ap-northeast-1"
  }
}
