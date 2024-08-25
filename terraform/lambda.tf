module "lambda_role" {
  source                  = "./modules/iam"
  name                    = "lambda-role"
  assume_role_identifiers = ["lambda.amazonaws.com"]
  policy_arn              = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_cloudwatch_log_group" "lambda_function_log" {
  for_each          = toset(local.function_names)
  retention_in_days = 1
  name              = "/aws/lambda/${aws_lambda_function.lambda[each.key].function_name}"
  kms_key_id        = aws_kms_key.log_group_key.arn
}

resource "aws_lambda_function" "lambda" {
  for_each         = toset(local.function_names)
  function_name    = each.key
  s3_bucket        = aws_s3_bucket.lambda_assets.bucket
  s3_key           = data.aws_s3_object.package[each.key].key
  role             = module.lambda_role.role_arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  source_code_hash = data.aws_s3_object.package_hash[each.key].body
  timeout          = "10"
}
