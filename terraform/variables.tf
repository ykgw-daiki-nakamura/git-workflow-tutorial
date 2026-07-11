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

# GitHub の OIDC プロバイダは URL ごとに AWS アカウントで 1 つしか作れない、
# アカウント全体で共有されるリソース。プロジェクト単位のリソースとは寿命が違う。
#
# 既に他プロジェクトが作っているアカウントで true にすると apply が 409 で落ちる。
# さらに厄介なのは destroy 側で、うっかり管理下に置くと、このチュートリアルの
# 後片付けで他プロジェクトの OIDC 連携ごと消してしまう。
# そのため既定は false = 「既存を参照するだけ。作りも消しもしない」にしてある。
#
# 自分専用のまっさらな AWS アカウントで、まだプロバイダが無い場合だけ true にする。
variable "create_oidc_provider" {
  description = "GitHub OIDC プロバイダを新規作成するか (false = 既存のものを参照する)"
  type        = bool
  default     = false
}
