#!/usr/bin/env bash
# 初回セットアップ用: Lambda 作成前に必要な :bootstrap イメージを ECR へ push する。
#
# 前提: terraform apply -target=aws_ecr_repository.backend が完了していること
# 使い方: ./scripts/bootstrap-image.sh
set -euo pipefail

cd "$(dirname "$0")/.."

REPO_URL=$(terraform -chdir=terraform output -raw ecr_repository_url)
REGION=$(terraform -chdir=terraform output -raw aws_region)
REGISTRY=${REPO_URL%%/*}

echo "==> login to ${REGISTRY}"
aws ecr get-login-password --region "${REGION}" \
  | docker login --username AWS --password-stdin "${REGISTRY}"

echo "==> build & push ${REPO_URL}:bootstrap"
# Lambda は x86_64 固定 (terraform/lambda.tf) なので、Apple Silicon などの
# arm64 ホストでも amd64 イメージを作る。外すと Lambda が起動しない。
docker build \
  --platform linux/amd64 \
  --build-arg APP_VERSION=bootstrap \
  --build-arg GIT_SHA=bootstrap \
  -t "${REPO_URL}:bootstrap" backend
docker push "${REPO_URL}:bootstrap"

echo "==> done. 続けて terraform apply を実行してください"
