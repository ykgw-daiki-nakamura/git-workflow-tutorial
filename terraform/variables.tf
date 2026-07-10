variable "project_name" {
  description = "リソース名のプレフィックス"
  type        = string
  default     = "gitflow-tutorial"
}

variable "aws_region" {
  description = "デプロイ先リージョン"
  type        = string
  default     = "ap-northeast-1"
}

variable "github_repository" {
  description = "OIDC 信頼対象の GitHub リポジトリ (owner/repo 形式)"
  type        = string
  # 例: "ykgw-daiki-nakamura/gitflow-tutorial-handson"
}
