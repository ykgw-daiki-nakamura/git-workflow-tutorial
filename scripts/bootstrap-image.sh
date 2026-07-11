#!/usr/bin/env bash
# 初回セットアップ用: Lambda 作成前に必要な :bootstrap イメージを ECR へ push する。
#
# 前提 (実行時に検証する): terraform apply -target=aws_ecr_repository.backend が完了していること
# 使い方: ./scripts/bootstrap-image.sh
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/preflight.sh
source "${SCRIPT_DIR}/lib/preflight.sh"
cd "${SCRIPT_DIR}/.."

require_cmd terraform docker aws
require_docker_daemon
require_terraform_output ecr_repository_url

REPO_URL=$(terraform -chdir=terraform output -raw ecr_repository_url)
REGISTRY=${REPO_URL%%/*}
# リージョンは aws_region 出力からは取らない。このスクリプトを実行する時点では
# terraform apply -target=aws_ecr_repository.backend しか終わっておらず、
# -target したリソースに依存しない出力 (aws_region) は state に書かれないため。
# レジストリ名 <account>.dkr.ecr.<region>.amazonaws.com から取り出す。
REGION=$(echo "${REGISTRY}" | awk -F. '{print $4}')
if [[ -z ${REGION} ]]; then
  echo "ERROR: ECR URL からリージョンを判定できません: ${REPO_URL}" >&2
  exit 1
fi

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
