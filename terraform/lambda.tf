# バックエンド API (コンテナイメージ Lambda + Function URL)。
# 初回 apply の前に scripts/bootstrap-image.sh で :bootstrap タグを
# push しておく必要がある (README のセットアップ手順を参照)。
resource "aws_iam_role" "lambda_exec" {
  name = "${var.project_name}-lambda-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "api" {
  for_each = local.environments

  function_name = "${var.project_name}-${each.key}-api"
  role          = aws_iam_role.lambda_exec.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.backend.repository_url}:bootstrap"
  architectures = ["x86_64"] # GitHub ホステッドランナーでのビルドに合わせる
  timeout       = 10
  memory_size   = 256

  environment {
    variables = {
      APP_ENV = each.key
    }
  }

  # デプロイは GitHub Actions が担う。Terraform は初期状態のみ管理し、
  # 以後の image_uri / 環境変数の変更は無視する (デプロイと衝突させない)。
  lifecycle {
    ignore_changes = [image_uri, environment]
  }
}

resource "aws_lambda_function_url" "api" {
  for_each = local.environments

  function_name      = aws_lambda_function.api[each.key].function_name
  authorization_type = "NONE" # チュートリアル用。CloudFront 経由アクセスが前提
}

resource "aws_lambda_permission" "function_url" {
  for_each = local.environments

  statement_id           = "AllowPublicFunctionUrl"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.api[each.key].function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}
