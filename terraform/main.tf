terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }
  # チュートリアル用途のためローカル state。実務では S3 backend を使うこと。
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
      Purpose   = "git-workflow-tutorial"
    }
  }

  # 組織のタグポリシーが自動付与するガバナンスタグ。設定には書かないため、
  # 放っておくと Terraform が毎回「設定に無い = 削除」と判断し、組織側が再付与し、
  # plan が永久に汚れ続ける (かつタグガバナンスにも反する)。管理対象外として無視する。
  # 自前の AWS アカウントではこれらのタグは付かないので、指定しても実害はない。
  ignore_tags {
    keys = [
      "App",
      "Application",
      "Company",
      "CostCenter",
      "Department",
      "Division",
      "Environment",
      "IntraConnected",
      "PrimaryOwner",
      "SecondaryOwner",
      "System",
      "UsageScope",
    ]
  }
}

data "aws_caller_identity" "current" {}

locals {
  account_id   = data.aws_caller_identity.current.account_id
  environments = toset(["dev", "staging", "production"])
}
