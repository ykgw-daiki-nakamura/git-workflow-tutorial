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

echo "==> done. docs/00-setup.md から始めてください"
