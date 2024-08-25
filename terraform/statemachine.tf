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
    resources = [for lambda in aws_lambda_function.lambda : "${lambda.arn}"]
  }
}

resource "aws_iam_policy" "StateMachinePolicy" {
  policy = data.aws_iam_policy_document.state_machine_role_policy.json
}

module "state_machine_role" {
  source = "./modules/iam"

  name                    = "StateMachineRole-Terraform-${random_string.random.id}"
  policy_arn              = aws_iam_policy.StateMachinePolicy.arn
  assume_role_identifiers = ["states.amazonaws.com"]
}

resource "aws_cloudwatch_log_group" "MySFNLogGroup" {
  name_prefix       = "/aws/vendedlogs/states/MyStateMachine-"
  retention_in_days = 1
  kms_key_id        = aws_kms_key.log_group_key.arn
}

resource "aws_sfn_state_machine" "sfn_state_machine" {
  name     = "StepFunctions-Terraform-${random_string.random.id}"
  role_arn = module.state_machine_role.role_arn
  definition = templatefile("${path.module}/../statemachine/statemachine.asl.json", {
    for name, lambda in aws_lambda_function.lambda
    : name => lambda.arn
    }
  )
  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.MySFNLogGroup.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }
}
