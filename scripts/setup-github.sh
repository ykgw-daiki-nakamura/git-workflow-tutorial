#!/usr/bin/env bash
# GitHub 側の規約準拠設定 (マージ方式 / Environments / Rulesets) を一括適用する。
#
# 使い方:
#   ./scripts/setup-github.sh solo                # 一人で演習するモード
#   ./scripts/setup-github.sh pair <reviewer>     # ペア/研修モード (規約どおり承認1名)
#
# solo モードの緩和点 (本来の規約との差分):
#   - PR の必須承認数: 1 -> 0 (自分の PR は自己承認できないため)
#   - production Environment: 自分を必須レビュアーにし self-review を許可
# ペアモードでは規約どおりの設定になる。
#
# 前提: gh CLI ログイン済み
#
# 対象リポジトリは既定でこのスクリプトを含むリポジトリ。GH_REPO で上書きできる。
# 非対話実行では確認プロンプトを省略する (SETUP_GITHUB_YES=1 でも省略可)。
set -euo pipefail

# gh repo view は cwd の git remote から対象を決めるため、呼び出し元の
# ディレクトリに引きずられないようリポジトリルートへ移動する。
cd "$(dirname "$0")/.."

MODE="${1:?usage: setup-github.sh solo | pair <reviewer-login>}"
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)

# main / release/* の Ruleset が要求する必須ステータスチェック。
# .github/workflows/ci.yml のジョブ名と一致させること。ここが唯一の定義元。
STATUS_CHECK_CONTEXTS=(pr-title frontend backend)

# ("a" "b") -> [{ "context": "a" }, { "context": "b" }]
STATUS_CHECKS_JSON="[$(printf '{ "context": "%s" }, ' "${STATUS_CHECK_CONTEXTS[@]}" | sed 's/, $//')]"

case "${MODE}" in
  solo)
    APPROVALS=0
    REVIEWER_LOGIN=$(gh api user -q .login)
    PREVENT_SELF_REVIEW=false
    ;;
  pair)
    APPROVALS=1
    REVIEWER_LOGIN="${2:?pair モードではレビュアーの GitHub ログイン名を指定してください}"
    PREVENT_SELF_REVIEW=true
    ;;
  *)
    echo "unknown mode: ${MODE}" >&2
    exit 1
    ;;
esac

REVIEWER_ID=$(gh api "users/${REVIEWER_LOGIN}" -q .id)

# [3/4] で Ruleset を削除するため、対象を取り違えていないか事前に確認させる。
echo "対象リポジトリ: ${REPO} (mode=${MODE}, reviewer=${REVIEWER_LOGIN})"
if [[ -t 0 && "${SETUP_GITHUB_YES:-}" != "1" ]]; then
  read -rp "この内容で適用しますか? [y/N] " ANSWER
  [[ "${ANSWER}" == [yY] ]] || { echo "中止しました" >&2; exit 1; }
fi

echo "==> [1/4] マージ方式: squash merge のみ・タイトル=PRタイトル"
gh api -X PATCH "repos/${REPO}" \
  -F allow_merge_commit=false \
  -F allow_rebase_merge=false \
  -F allow_squash_merge=true \
  -f squash_merge_commit_title=PR_TITLE \
  -f squash_merge_commit_message=PR_BODY \
  -F delete_branch_on_merge=true > /dev/null

echo "==> [2/4] Environments: dev / staging / production"
gh api -X PUT "repos/${REPO}/environments/dev" > /dev/null
gh api -X PUT "repos/${REPO}/environments/staging" > /dev/null
# production のみ必須レビュアー承認を要求 (GA デプロイの承認ゲート)
gh api -X PUT "repos/${REPO}/environments/production" \
  --input - > /dev/null <<EOF
{
  "prevent_self_review": ${PREVENT_SELF_REVIEW},
  "reviewers": [{ "type": "User", "id": ${REVIEWER_ID} }]
}
EOF

echo "==> [3/4] 既存の同名 Rulesets を削除 (再実行時の重複防止)"
for ID in $(gh api "repos/${REPO}/rulesets" \
  -q '.[] | select(.name | startswith("tutorial-")) | .id'); do
  gh api -X DELETE "repos/${REPO}/rulesets/${ID}" > /dev/null
  echo "    deleted ruleset ${ID}"
done

echo "==> [4/4] Rulesets を作成"

# main と release/* に同一の保護をかける。ブランチ条件だけが異なる。
create_branch_ruleset() {
  local name="$1" include="$2"
  gh api -X POST "repos/${REPO}/rulesets" --input - > /dev/null <<EOF
{
  "name": "${name}",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": [${include}], "exclude": [] } },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": ${APPROVALS},
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false,
        "allowed_merge_methods": ["squash"]
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": true,
        "required_status_checks": ${STATUS_CHECKS_JSON}
      }
    }
  ]
}
EOF
  echo "    ${name}"
}

# PR 必須 + squash のみ + 必須ステータスチェック + 削除/force push 禁止
create_branch_ruleset "tutorial-protect-main" '"~DEFAULT_BRANCH"'
# release/*: main と同等の保護 (バックポートも PR 経由を強制)
create_branch_ruleset "tutorial-protect-release-branches" '"refs/heads/release/**"'

# v* タグ: 公開済みタグの削除・付け替えを禁止
gh api -X POST "repos/${REPO}/rulesets" --input - > /dev/null <<EOF
{
  "name": "tutorial-protect-release-tags",
  "target": "tag",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/tags/v*"], "exclude": [] } },
  "rules": [
    { "type": "deletion" },
    { "type": "update" }
  ]
}
EOF
echo "    tutorial-protect-release-tags"

echo ""
echo "完了 (mode=${MODE}, repo=${REPO})"
echo "次: ./scripts/sync-github-vars.sh で Terraform の出力を GitHub variables へ同期"
