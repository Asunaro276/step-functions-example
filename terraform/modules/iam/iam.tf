resource "aws_iam_role" "default" {
  name = var.name
  assume_role_policy  = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "policy_attach" {
  role = aws_iam_role.default.name
  policy_arn = var.policy_arn
}

data "aws_iam_policy_document" "lambda_assume_role_policy" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = var.assume_role_identifiers
    }

    actions = [
      "sts:AssumeRole",
    ]
  }
}
