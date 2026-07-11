#!/usr/bin/env bash
# devcontainer 作成後の初期化。再実行しても安全なように書くこと。
set -euo pipefail

cd "$(dirname "$0")/.."

# jq はベースイメージに含まれる。terraform / aws / gh / docker は feature 側。

if ! command -v uv >/dev/null 2>&1; then
  echo "==> install uv"
  # /usr/local/bin に入れて PATH の追加設定を不要にする
  curl -LsSf https://astral.sh/uv/install.sh \
    | sudo env UV_INSTALL_DIR=/usr/local/bin sh
fi

echo "==> backend: uv sync"
(cd backend && uv sync)

echo "==> frontend: npm ci"
(cd frontend && npm ci --no-audit --no-fund)

# devcontainer.json の remoteEnv は ${localEnv:...} でホストの値を引き渡すが、
# ホスト側で未設定の変数は「空文字列」として注入される (素通しにはならない)。
# 空の AWS_PROFILE / AWS_REGION があると AWS CLI は空の名前をそのまま使おうとして
# "The config profile () could not be found" / "https://sts..amazonaws.com" で失敗する。
# 詳細と手動での回避手順は docs/00-setup.md の 0.1 を参照。
marker="# >>> devcontainer: strip empty AWS_* >>>"
if ! grep -qF "$marker" ~/.bashrc; then
  echo "==> shell: 空の AWS_* 環境変数を取り除く設定を ~/.bashrc に追加"
  # 'EOF' をクォートして、以下は展開せずそのまま ~/.bashrc へ書き出す
  cat >> ~/.bashrc <<'EOF'

# >>> devcontainer: strip empty AWS_* >>>
# devcontainer の remoteEnv が注入する「空の」AWS_* を取り除く (詳細: docs/00-setup.md)。
# 値が入っているものはそのまま残すので、ホストで AWS_PROFILE を使う運用は壊さない。
for __v in AWS_PROFILE AWS_REGION AWS_SESSION_TOKEN AWS_SDK_LOAD_CONFIG \
           AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY; do
  [ -n "${!__v+x}" ] && [ -z "${!__v}" ] && unset "$__v"
done
unset __v
# リージョン未指定なら terraform/variables.tf の既定値に合わせる
export AWS_REGION="${AWS_REGION:-ap-northeast-1}"
# <<< devcontainer: strip empty AWS_* <<<
EOF
fi

echo "==> done. docs/00-setup.md から始めてください"
