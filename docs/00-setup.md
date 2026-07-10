# 第0章 セットアップ

AWS リソースの作成と GitHub 側の設定を行います。CloudFront の作成に数分かかるので、
`terraform apply` を流している間に第1章の冒頭を読んでおくのがおすすめです。

## 0.1 前提条件

このリポジトリには devcontainer が入っています。**自分で用意するのは AWS アカウントと
認証情報だけ**で、Terraform / Docker / jq / gh / Node 22 / uv はコンテナ側に揃っています。

次のどちらかで開いてください。

- GitHub の **Code → Codespaces → Create codespace**
- 手元に clone して VS Code で開き、**Reopen in Container**

コンテナが立ち上がったら、ツールが揃っていることを確認します。

```bash
node -v            # v22.x
terraform version  # 1.7 以上
aws --version
uv --version
```

### AWS 認証情報を渡す

| 開き方 | 渡し方 |
|---|---|
| ローカルの VS Code | ホストの `~/.aws` が読み取り専用でマウントされます。何もしなくて OK |
| Codespaces | リポジトリの **Settings → Secrets and variables → Codespaces** に `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_REGION` を登録 (一時認証情報なら `AWS_SESSION_TOKEN` も) |

`aws sts get-caller-identity` が通れば準備完了です。

> [!IMPORTANT]
> Rulesets と Environment 保護ルールを無料プランで使うには、リポジトリを
> **パブリック**にする必要があります。プライベートで演習したい場合は
> GitHub Team 以上のプランの Organization を使ってください。

> [!WARNING]
> Codespaces に既定で入っている `gh` のトークンには Rulesets を作る権限がありません。
> 0.4 の `setup-github.sh` を実行する前に `gh auth login` でログインし直してください
> (Authenticate Git → はい、スコープは既定のままで構いません)。

<details>
<summary>▶ devcontainer を使わず、ローカルに直接そろえる場合</summary>

以下をインストールしてください。

- AWS アカウントと認証情報 (`aws sts get-caller-identity` が通ること)
- Terraform >= 1.7 / Docker / jq
- gh CLI (`gh auth status` でログイン済みであること)
- Node.js 22 / [uv](https://docs.astral.sh/uv/)

Node のバージョンは CI (`.github/workflows/ci.yml`) と揃えてください。ズレていると
「手元では通るのに CI で落ちる」が起きます。

</details>

## 0.2 リポジトリの作成

1. このテンプレートリポジトリの **Use this template → Create a new repository** で自分のリポジトリを作成
2. clone して作業ディレクトリへ移動

```bash
git clone https://github.com/<owner>/<repo>.git
cd <repo>
```

## 0.3 AWS リソースの作成

Lambda はコンテナイメージがないと作成できないため、「ECR だけ先に作る → 初期イメージを
push → 全体を apply」の 3 段階で進めます。

```bash
cd terraform
cat > terraform.tfvars <<EOF
github_repository = "<owner>/<repo>"
EOF

terraform init
terraform apply -target=aws_ecr_repository.backend   # ECR だけ先に作成
cd ..

./scripts/bootstrap-image.sh                          # :bootstrap イメージを push

terraform -chdir=terraform apply                      # 全体を作成 (数分かかる)
```

作成されるもの: ECR リポジトリ ×1、環境別 (dev / staging / production) に
IAM ロール・Lambda・S3 バケット・CloudFront ディストリビューション各 ×3。

> [!NOTE]
> IAM ロールは GitHub Actions の OIDC トークンでのみ assume でき、しかも
> `sub` クレームを `environment:<env>` に限定しています。つまり **GitHub Environments
> の保護ルールを通過しないと、その環境の AWS 権限が手に入らない**構造です。
> この意味は第3章で体感します。

## 0.4 GitHub 側の設定

演習モードを選んでスクリプトを実行します。

```bash
./scripts/setup-github.sh solo
```

<details>
<summary>▶ ペア/研修モードの場合</summary>

```bash
./scripts/setup-github.sh pair <レビュアーのGitHubログイン名>
```

pair モードは PR の必須承認数 1、production デプロイの承認者は指定した相手、
自己承認は不可、という**本来の運用どおり**の設定になります。

</details>

> [!WARNING]
> `solo` モードは一人で演習を完走するために 2 点を緩和しています。
> **本来の運用は pair モードの設定**です。
> - PR の必須承認数: 1 → 0 (GitHub では自分の PR を自己承認できないため)
> - production の必須レビュアー: 自分自身 + self-review 許可

このスクリプトが設定する内容:

| 設定 | 内容 | 守っているもの |
|---|---|---|
| マージ方式 | squash のみ、コミットタイトル = PR タイトル | main の履歴 1 PR = 1 コミット |
| Ruleset `tutorial-protect-main` | 直 push / force push / 削除禁止、PR + CI 必須 | トランクの健全性 |
| Ruleset `tutorial-protect-release-branches` | `release/**` に同上 | リリースブランチの健全性 |
| Ruleset `tutorial-protect-release-tags` | `v*` タグの削除・付け替え禁止 | 公開済みタグの不変性 |
| Environments | dev / staging / production (本番のみ承認必須) | 本番デプロイの承認ゲート |

続けて、Terraform の出力 (ロール ARN、関数名、バケット名など) を GitHub の
variables に流し込みます。

```bash
./scripts/sync-github-vars.sh
```

最後に各環境の URL が表示されます。**メモしておいてください** (以降の章で使います)。

## 0.5 初回デプロイの確認

ここまでの変更 (terraform.tfvars は .gitignore 済みなので何もなければ空コミット) を
main に直接 push ......はできません。第2章で確認するとして、まずは Actions を見ます。

1. リポジトリの **Actions** タブを開く
2. テンプレート作成時の初回 push で `CD (dev)` が動いていれば、それが初回デプロイです。
   動いていなければ、第1章の最初の PR がそのまま初回デプロイになります
3. dev の URL をブラウザで開き、「出荷検品票」が表示されることを確認
   (初回は CloudFront の伝播で数分かかることがあります)

検品票の backend 側に `version: dev` が出ていれば成功です。staging / production は
まだ `bootstrap` のままですが、それで正常です — **まだ何もリリースしていない**のだから。

---

← [目次](./README.md) | [第1章 フィーチャー開発 →](./01-feature-flow.md)
