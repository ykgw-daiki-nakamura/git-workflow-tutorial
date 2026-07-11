# GitHub Actions からの OIDC フェデレーション。
# ポイント: sub 条件を "environment:<env>" に限定しているため、
# GitHub Environments の保護ルール (production の必須レビュアー承認など) を
# 通過しない限り、対応する AWS ロールを assume できない。

# OIDC プロバイダはアカウント共有リソースなので、作成するかどうかを
# var.create_oidc_provider で選ぶ (既定は false = 既存を参照。理由は variables.tf)。
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

# url ではなく arn で引くこと。url 指定だと provider は内部で
# ListOpenIDConnectProviders を呼ぶが、docs/00-setup.md の最小権限ポリシーは
# この API を許可していない (許可しているのは GetOpenIDConnectProvider だけ)。
# arn 指定なら Get だけで解決できる。
data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1

  arn = "arn:aws:iam::${local.account_id}:oidc-provider/token.actions.githubusercontent.com"
}

locals {
  github_oidc_provider_arn = (
    var.create_oidc_provider
    ? aws_iam_openid_connect_provider.github[0].arn
    : data.aws_iam_openid_connect_provider.github[0].arn
  )
}

data "aws_iam_policy_document" "assume" {
  for_each = local.environments

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:environment:${each.key}"]
    }
  }
}

data "aws_iam_policy_document" "deploy" {
  for_each = local.environments

  # ECR: リポジトリスコープの push/pull (RC ビルドと GA の crane tag に必要)
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:DescribeImages",
    ]
    resources = [aws_ecr_repository.backend.arn]
  }

  # Lambda: 自環境の関数のみ更新可能
  statement {
    actions = [
      "lambda:UpdateFunctionCode",
      "lambda:UpdateFunctionConfiguration",
      "lambda:GetFunction",
      "lambda:GetFunctionConfiguration",
    ]
    resources = [aws_lambda_function.api[each.key].arn]
  }

  # S3: 自環境のフロントエンドバケットのみ
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.frontend[each.key].arn]
  }
  statement {
    actions   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.frontend[each.key].arn}/*"]
  }

  # CloudFront: 自環境のディストリビューションの invalidation のみ
  statement {
    actions   = ["cloudfront:CreateInvalidation"]
    resources = [aws_cloudfront_distribution.app[each.key].arn]
  }
}

resource "aws_iam_role" "deploy" {
  for_each           = local.environments
  name               = "${local.name_prefix}-${each.key}-deploy"
  assume_role_policy = data.aws_iam_policy_document.assume[each.key].json
}

resource "aws_iam_role_policy" "deploy" {
  for_each = local.environments
  name     = "deploy"
  role     = aws_iam_role.deploy[each.key].id
  policy   = data.aws_iam_policy_document.deploy[each.key].json
}
