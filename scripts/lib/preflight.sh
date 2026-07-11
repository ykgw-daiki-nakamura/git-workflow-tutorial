#!/usr/bin/env bash
# 各スクリプトが source して使う前提チェック。単体では実行しない。
#
# 前提が満たされないまま進むと、依存ツールの生のエラーが処理の途中で出る。
# 何を直せばよいかが分かるメッセージを、副作用が起きる前に出すのが目的。

# devcontainer の remoteEnv は、ホストで未設定の ${localEnv:X} を「空文字列」として
# 注入する (行が消えるわけではない)。空の AWS_PROFILE が残っていると aws / terraform は
# 空の名前をそのまま使い "The config profile () could not be found" で失敗する。
#
# 同じ除去を post-create.sh が ~/.bashrc にも仕込むが、あちらは対話シェル専用。
# Ubuntu の ~/.bashrc は冒頭で「非対話シェルなら return」するため、スクリプト実行時には
# 効かない。スクリプトは自分で面倒を見る必要がある。source した時点で実行する。
strip_empty_aws_env() {
  local v
  for v in AWS_PROFILE AWS_REGION AWS_SESSION_TOKEN AWS_SDK_LOAD_CONFIG \
           AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY; do
    if [[ -n ${!v+x} && -z ${!v} ]]; then
      unset "${v}"
    fi
  done
}
strip_empty_aws_env

# 必要なコマンドが PATH にあるか。足りないものをまとめて報告する。
require_cmd() {
  local missing=() cmd
  for cmd in "$@"; do
    command -v "${cmd}" > /dev/null 2>&1 || missing+=("${cmd}")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: 次のコマンドが見つかりません: ${missing[*]}" >&2
    echo "       docs/00-setup.md の前提ツールを確認してください" >&2
    return 1
  fi
}

# gh がログイン済みか (GH_TOKEN 等による認証も gh auth status が判定する)。
require_gh_auth() {
  if ! gh auth status > /dev/null 2>&1; then
    echo "ERROR: gh CLI が未ログインです" >&2
    echo "       'gh auth login' を実行してください" >&2
    return 1
  fi
}

# Docker daemon に接続できるか。docker build の直前に確認する。
require_docker_daemon() {
  if ! docker info > /dev/null 2>&1; then
    echo "ERROR: Docker daemon に接続できません" >&2
    echo "       Docker Desktop / dockerd が起動しているか確認してください" >&2
    return 1
  fi
}

# 指定した terraform 出力が取得できるか = 該当リソースが apply 済みか。
require_terraform_output() {
  local name="$1"
  if ! terraform -chdir=terraform output -raw "${name}" > /dev/null 2>&1; then
    echo "ERROR: terraform の出力 '${name}' を取得できません" >&2
    echo "       terraform apply は完了していますか?" >&2
    return 1
  fi
}
