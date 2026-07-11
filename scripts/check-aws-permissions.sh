#!/usr/bin/env bash
# terraform apply の前に、いまの AWS 認証情報で必要な権限があるかを確かめる。
# 何も作らない (読み取り専用)。
#
# 権限が足りないことに apply の途中で気付くと、生の AccessDenied が出るだけで
# 何を直せばいいのか分からない。ポリシーが古いだけ、というのが実際に起きている
# (Issue #28: リソース名に owner が入った際、旧ポリシーの ECR 許可が外れた)。
#
# 判定のからくり: AWS は「リソースが在るか」より先に「認可されているか」を評価する。
# そのため存在しないリソースを指定して叩けば、
#   AccessDenied         -> 権限が無い
#   NotFound などの別エラー -> 権限はある (まだ作っていないだけ)
# と切り分けられる。
#
# 使い方:
#   ./scripts/check-aws-permissions.sh [owner]     # 省略時は terraform.tfvars の owner
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/preflight.sh
source "${SCRIPT_DIR}/lib/preflight.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/naming.sh
source "${SCRIPT_DIR}/lib/naming.sh"
cd "${SCRIPT_DIR}/.."

require_cmd aws

OWNER_ARG=${1:-$(naming_owner_from_tfvars)}
if [[ -z ${OWNER_ARG} ]]; then
  echo "ERROR: owner が分かりません" >&2
  echo "       terraform/terraform.tfvars に owner を書くか、引数で渡してください:" >&2
  echo "         ./scripts/check-aws-permissions.sh <owner>" >&2
  exit 1
fi
resolve_naming "${OWNER_ARG}"

if ! CALLER=$(aws sts get-caller-identity --query 'Arn' --output text 2>&1); then
  echo "ERROR: AWS の認証情報が使えません" >&2
  echo "       docs/00-setup.md の 0.1 (AWS 認証情報) を確認してください" >&2
  printf '%s\n' "${CALLER}" >&2
  exit 1
fi
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)

echo "認証情報 : ${CALLER}"
echo "owner    : ${OWNER}"
echo "リソース名: ${PREFIX}-*"
echo

DENIED=()

# 存在しないリソースを 1 つ叩いて、AccessDenied かどうかだけを見る。
check() {
  local label=$1 action=$2
  shift 2
  local out
  printf '  %-32s ' "${action}"
  if out=$("$@" 2>&1); then
    echo "OK"
  elif grep -qE 'AccessDenied|not authorized' <<< "${out}"; then
    echo "権限なし"
    DENIED+=("${action} (${label})")
  else
    # NotFound / NoSuchEntity など。認可は通っている。
    echo "OK"
  fi
}

check "ECR への docker push" \
  "ecr:GetAuthorizationToken" aws ecr get-authorization-token
check "ECR リポジトリ ${PREFIX}-backend の作成" \
  "ecr:DescribeRepositories" aws ecr describe-repositories --repository-names "${PREFIX}-backend"
check "Lambda 関数の作成" \
  "lambda:GetFunction" aws lambda get-function --function-name "${PREFIX}-dev-api"
check "Lambda 実行ロールの作成" \
  "iam:GetRole" aws iam get-role --role-name "${PREFIX}-lambda-exec"
check "GitHub OIDC 連携" \
  "iam:GetOpenIDConnectProvider" aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn \
  "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
check "CloudFront ディストリビューションの作成" \
  "cloudfront:ListDistributions" aws cloudfront list-distributions
check "終章での後片付け" \
  "logs:DescribeLogGroups" aws logs describe-log-groups

echo

# S3 と CloudFront の作成系は読み取りだけでは確かめられない。S3 は存在しないバケットに
# 対して権限の有無によらず NoSuchBucket を返すし、cloudfront:CreateDistribution は
# タグ条件つきなので実際に作るまで分からない。ここで OK でも apply が落ちる余地は残る。
if ((${#DENIED[@]} > 0)); then
  echo "ERROR: 次の権限が足りません" >&2
  printf '  - %s\n' "${DENIED[@]}" >&2
  cat >&2 <<EOF

ポリシーが古い可能性があります (リソース名の付け方が変わると、古いポリシーの許可は
名前が変わったリソースに届かなくなります)。管理者に、リポジトリを最新にした上で
次の再実行を依頼してください。

  ./scripts/apply-setup-policy.sh ${OWNER}

自分の AWS アカウントで一人で演習しているなら、上を自分で実行してください。
EOF
  exit 1
fi

echo "必要な権限は揃っています。docs/00-setup.md の 0.3 へ進んでください。"
