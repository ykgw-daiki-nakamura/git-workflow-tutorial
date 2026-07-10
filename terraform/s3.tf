resource "aws_s3_bucket" "frontend" {
  for_each = local.environments

  # バケット名はグローバル一意のため account_id を付与
  bucket        = "${var.project_name}-${each.key}-frontend-${local.account_id}"
  force_destroy = true # チュートリアル用
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  for_each = local.environments

  bucket                  = aws_s3_bucket.frontend[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudFront (OAC) からのみ読み取りを許可
data "aws_iam_policy_document" "frontend_bucket" {
  for_each = local.environments

  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.frontend[each.key].arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.app[each.key].arn]
    }
  }
}

resource "aws_s3_bucket_policy" "frontend" {
  for_each = local.environments

  bucket = aws_s3_bucket.frontend[each.key].id
  policy = data.aws_iam_policy_document.frontend_bucket[each.key].json
}
