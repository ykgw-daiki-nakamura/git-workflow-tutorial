#!/usr/bin/env bash
# 参加者ごとの最小権限ポリシー (IAM ポリシー JSON) を生成し、標準出力に書く。
#
# 1 つの AWS アカウントを複数人で共有して演習するとき、参加者ごとに owner を変えて
# 実行すれば、「自分のリソースにしか触れない」IAM ユーザー用のポリシーが手に入る。
# 許可範囲を絞る手掛かりは 2 つ:
#   - リソース名のプレフィックス <project_name>-<owner>-  (ECR / S3 / Lambda / IAM / Logs)
#   - Owner タグ                                          (CloudFront。名前で絞れないため)
# どちらも terraform 側 (local.name_prefix と provider の default_tags) と対になっている。
#
# 使い方:
#   ./scripts/gen-setup-policy.sh <owner> [project_name] > setup-policy.json
#
# 生成物の登録方法と、絞りきれない箇所については docs/00-setup.md の「必要な権限」を参照。
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/preflight.sh
source "${SCRIPT_DIR}/lib/preflight.sh"
cd "${SCRIPT_DIR}/.."

require_cmd jq

TEMPLATE="docs/assets/setup-policy.template.json"
VARIABLES_TF="terraform/variables.tf"

usage() {
  cat >&2 <<'EOF'
使い方: ./scripts/gen-setup-policy.sh <owner> [project_name]

  owner        リソースの所有者を表す識別子。terraform.tfvars の owner と同じ値にすること
               (英小文字・数字・ハイフン、13 文字以内)
  project_name 省略時は terraform/variables.tf の既定値。
               terraform.tfvars で project_name を上書きした場合だけ、その値を渡す

例:
  ./scripts/gen-setup-policy.sh alice > /tmp/setup-policy-alice.json
EOF
}

OWNER=${1:-}
if [[ -z ${OWNER} ]]; then
  usage
  exit 1
fi

# owner の書式は terraform 側の variable "owner" の validation と同じ規則。
# ここで弾いておかないと、ポリシーだけ先に作れて apply で初めて落ちる。
if ! [[ ${OWNER} =~ ^[a-z0-9]([a-z0-9-]{0,11}[a-z0-9])?$ ]]; then
  echo "ERROR: owner が不正です: '${OWNER}'" >&2
  echo "       英小文字・数字・ハイフンのみ、1〜13 文字 (先頭と末尾はハイフン不可)" >&2
  exit 1
fi

# project_name の既定値は terraform/variables.tf を唯一の定義元とする。
# ここに独自の既定値を書くと、terraform 側を変えたときに黙ってズレ、
# 「ポリシーは gitflow-tutorial-*、実際のリソースは別名」で AccessDenied になる。
default_project_name() {
  awk '
    /^variable "project_name"/ { in_block = 1; next }
    in_block && $1 == "default" { gsub(/"/, "", $3); print $3; exit }
    in_block && /^}/            { exit }
  ' "${VARIABLES_TF}"
}

PROJECT_NAME=${2:-$(default_project_name)}
if [[ -z ${PROJECT_NAME} ]]; then
  echo "ERROR: ${VARIABLES_TF} から project_name の既定値を読み取れません" >&2
  echo "       第 2 引数で明示してください: ./scripts/gen-setup-policy.sh ${OWNER} <project_name>" >&2
  exit 1
fi

# owner と同じ文字種に制限する。ECR / S3 / Lambda の名前に入る以上どのみち必要な制約だが、
# ここでは sed の安全性も兼ねている: '/' は区切り文字と衝突し、'&' は置換先で
# 「マッチ全体」に化けるため、素通しにすると黙って壊れたポリシーが出来上がる。
if ! [[ ${PROJECT_NAME} =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
  echo "ERROR: project_name が不正です: '${PROJECT_NAME}'" >&2
  echo "       英小文字・数字・ハイフンのみ (先頭と末尾はハイフン不可)" >&2
  exit 1
fi

PREFIX="${PROJECT_NAME}-${OWNER}"

# S3 バケット名 (63 文字) が最も厳しい制約。terraform の s3.tf も同じ検査をするが、
# あちらは apply 時。ポリシーを配る前に気付けるよう、ここでも見る。
# 末尾はグローバル一意化のためのアカウント ID 12 桁。
BUCKET_SUFFIX="-production-frontend-" # 環境名は production が最長
LONGEST_BUCKET_LEN=$(( ${#PREFIX} + ${#BUCKET_SUFFIX} + 12 ))
if (( LONGEST_BUCKET_LEN > 63 )); then
  echo "ERROR: S3 バケット名が ${LONGEST_BUCKET_LEN} 文字になり、63 文字を超えます" >&2
  echo "       ('${PREFIX}-production-frontend-<アカウントID>')" >&2
  echo "       owner か project_name を短くしてください" >&2
  exit 1
fi

if [[ ! -f ${TEMPLATE} ]]; then
  echo "ERROR: テンプレートが見つかりません: ${TEMPLATE}" >&2
  exit 1
fi

# _comment はテンプレートの読み手向け。IAM は不明なトップレベルキーを拒否するため落とす。
# owner / project_name は上で書式検証済みなので、sed を壊す文字は入らない。
POLICY=$(
  sed -e "s/__PREFIX__/${PREFIX}/g" -e "s/__OWNER__/${OWNER}/g" "${TEMPLATE}" \
    | jq 'del(._comment)'
)

# 置換漏れ = テンプレートに新しいプレースホルダが増えたのに、こちらが追随していない。
# 気付かずに登録すると、リテラル "__FOO__" という名前にしか許可が出ないポリシーになる。
if grep -q '__[A-Z_]\+__' <<< "${POLICY}"; then
  echo "ERROR: 置換されなかったプレースホルダが残っています:" >&2
  grep -o '__[A-Z_]\+__' <<< "${POLICY}" | sort -u >&2
  exit 1
fi

printf '%s\n' "${POLICY}"

cat >&2 <<EOF

生成しました (owner=${OWNER}, リソース名のプレフィックス=${PREFIX}-)
このポリシーで触れるのは ${PREFIX}-* という名前のリソースと、
Owner=${OWNER} タグの付いた CloudFront ディストリビューションだけです。

登録するには、管理者権限のある認証情報で:

  aws iam create-policy \\
    --policy-name ${PREFIX}-setup \\
    --policy-document file://<このスクリプトの出力を保存したファイル>

  aws iam attach-user-policy \\
    --user-name <IAM ユーザー名> \\
    --policy-arn arn:aws:iam::<アカウントID>:policy/${PREFIX}-setup

参加者側の terraform.tfvars には owner = "${OWNER}" を書いてください。
EOF
