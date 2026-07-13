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

### AWS 認証情報を設定する

**研修などで演習する場合、管理者から次の 4 つを受け取ります。** AWS の画面を触る必要は
ありません。

| 受け取るもの | 例 |
|---|---|
| `AWS_ACCESS_KEY_ID` | `AKIA...` (20 文字) |
| `AWS_SECRET_ACCESS_KEY` | 40 文字 |
| `AWS_REGION` | `ap-northeast-1` |
| `owner` | `alice` (あなた専用の目印。[0.3](#03-aws-リソースの作成) で使います) |

上の 3 つ (`AWS_` で始まるもの) をコンテナに渡します。`owner` は [0.3](#03-aws-リソースの作成)
で `terraform.tfvars` に書くので、ここでは使いません。

| 開き方 | 渡し方 |
|---|---|
| **Codespaces** | リポジトリの **Settings → Secrets and variables → Codespaces** に登録する (一時認証情報を渡された場合は `AWS_SESSION_TOKEN` も) |
| ローカルの VS Code | ホストの `~/.aws` が読み取り専用でマウントされます。ホスト側で `aws configure` を済ませてあれば、何もしなくて OK |

> [!NOTE]
> Codespaces secrets は起動時に環境変数として注入されます。**すでに起動している
> Codespace には反映されない**ので、登録後に再起動してください。

設定できたか確認します。

```bash
aws sts get-caller-identity   # Account / Arn が返れば OK
```

次に、その認証情報で `terraform apply` に必要な権限が揃っているかを確かめます (読み取り
だけで、何も作りません)。`<owner>` は管理者から伝えられた値に置き換えてください。

```bash
./scripts/check-aws-permissions.sh <owner>
```

ここで `権限なし` が出たら、先に進んでも apply の途中で `AccessDenied` になるだけです。
表示された内容を管理者に伝えてください。

`InvalidClientTokenId` や `ExpiredToken` が返る場合は、キーの貼り間違いか、一時認証情報の
期限切れです。

> [!CAUTION]
> アクセスキーはパスワードと同じです。リポジトリにコミットしない (`.gitignore` 済みの
> `terraform.tfvars` にも書かない)、Slack やメールに貼らない。演習が終わったら
> [終章](./99-cleanup.md) で削除します。

<details>
<summary>▶ <b>自分の AWS アカウントで演習する場合 / 演習環境を用意する側の場合</b></summary>

IAM ユーザーの作り方、必要な権限、1 つの AWS アカウントを複数人で共有する方法は
**[管理者ガイド](./90-admin.md)** にまとめました。

- 自分のアカウントで一人で演習する → [一人で演習する場合](./90-admin.md#一人で演習する場合)
- 研修環境を用意する → [管理者ガイド](./90-admin.md) 全体
- IAM Identity Center (AWS SSO) を使っている → [該当節](./90-admin.md#iam-identity-center-aws-sso-を使っている組織の場合)

用意ができたら、上と同じように認証情報をコンテナに渡してください。

</details>

<details>
<summary>▶ <code>config profile ()</code> や <code>sts..amazonaws.com</code> というエラーが出る場合</summary>

キーは正しいのに、次のようなエラーが出ることがあります。

```
aws: [ERROR]: The config profile () could not be found
aws: [ERROR]: Invalid endpoint: https://sts..amazonaws.com
```

どちらも**空の環境変数**が原因です。括弧の中とホスト名の途中が空欄になっているのが
その印で、AWS CLI は「空のプロファイル名」「空のリージョン名」をそのまま使おうとして
失敗しています。

`.devcontainer/devcontainer.json` の `remoteEnv` はホストの値をコンテナへ引き渡しますが、
**ホスト側でその変数が未設定だと `${localEnv:...}` は空文字列に展開されます** (未設定の
まま素通しにはなりません)。結果、コンテナ内では「セットされているが中身が空」という
状態になります。`AWS_PROFILE` を使わず環境変数だけで認証する Codespaces で起きがちです。

これは `.devcontainer/shell-env.sh` が自動で取り除くので、**通常は起きません**。
それでも出る場合は、コンテナ作成時の `post-create.sh` が最後まで走らなかった可能性が
高いです。コマンドパレットから **Rebuild Container** を実行してください。

急ぐ場合は、開いているシェルで直接消しても通ります。

```bash
unset AWS_PROFILE AWS_SESSION_TOKEN     # B の恒久キーなら SESSION_TOKEN は不要
export AWS_REGION=ap-northeast-1        # terraform/variables.tf の既定値
aws sts get-caller-identity
```

どの変数が空かは、値を表示せずに長さだけで確認できます。

```bash
for v in AWS_PROFILE AWS_REGION AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN; do
  val="${!v}"
  if   [ -z "${!v+x}" ]; then echo "$v: 未設定 (OK)"
  elif [ -z "$val"    ]; then echo "$v: 空 <-- これが原因"
  else echo "$v: 設定あり (${#val} 文字)"; fi
done
```

`AWS_ACCESS_KEY_ID` が 20 文字、`AWS_SECRET_ACCESS_KEY` が 40 文字あれば認証情報そのものは
正しく渡っています。

</details>

> [!IMPORTANT]
> Rulesets と Environment 保護ルールを無料プランで使うには、リポジトリを
> **パブリック**にする必要があります。プライベートで演習したい場合は
> GitHub Team 以上のプランの Organization を使ってください。

> [!WARNING]
> Codespaces に既定で入っている `gh` のトークン (環境変数 `GITHUB_TOKEN`) には
> Rulesets を作る権限がありません。`gh` は保存済みの認証情報より環境変数を優先するため、
> `gh auth login` の前に `unset GITHUB_TOKEN` が必要です。手順は 0.4 に書いています。
> 外し忘れると `Resource not accessible by integration (HTTP 403)` で失敗します。

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
git clone https://github.com/<GitHubアカウント>/<リポジトリ名>.git
cd <repo>
```

## 0.3 AWS リソースの作成

Lambda はコンテナイメージがないと作成できないため、「ECR だけ先に作る → 初期イメージを
push → 全体を apply」の 3 段階で進めます。**1 つずつ、順番に実行してください** (`terraform`
は数分かかるものがあります)。

**1. Terraform の変数を書く**

```bash
cat > terraform/terraform.tfvars <<EOF
github_repository = "<GitHubアカウント>/<リポジトリ名>"
owner             = "<自分の識別子>"
EOF
```

`owner` は作られるリソースの名前とタグに入る、あなた専用の目印です (英小文字・数字・
ハイフン、13 文字以内)。**管理者から `owner` を伝えられている場合は、その値を一字一句
同じに書いてください。**ズレていると、名前もタグも許可範囲の外に出るため `terraform apply`
が `AccessDenied` で落ちます。自分のアカウントで一人で演習するなら好きな値で構いません。

**2. 権限が揃っているか確かめる** (読み取りだけ。何も作りません)

```bash
./scripts/check-aws-permissions.sh
```

ここで `権限なし` が出たら、先に進んでも `terraform apply` の途中で `AccessDenied` になる
だけです。表示された内容に従うか、管理者に伝えてください。

**3. Terraform を初期化する**

```bash
terraform -chdir=terraform init
```

**4. ECR リポジトリだけ先に作る**

```bash
terraform -chdir=terraform apply -target=aws_ecr_repository.backend
```

**5. 初期イメージ (`:bootstrap`) を push する**

```bash
./scripts/bootstrap-image.sh
```

**6. 残り全体を作る** (CloudFront の作成に数分かかります)

```bash
terraform -chdir=terraform apply
```

作成されるもの: ECR リポジトリ ×1、環境別 (dev / staging / production) に
IAM ロール・Lambda・S3 バケット・CloudFront ディストリビューション各 ×3。すべて
`gitflow-tutorial-<owner>-...` という名前で、`Owner=<owner>` タグが付きます。

> [!IMPORTANT]
> GitHub の OIDC プロバイダ (`token.actions.githubusercontent.com`) は、URL ごとに
> AWS アカウントで 1 つしか作れない**アカウント共有リソース**です。プロジェクト単位の
> リソースとは寿命が違うため、既定 (`create_oidc_provider = false`) では Terraform は
> **既存のものを参照するだけ**で、作成も削除もしません。うっかり管理下に置くと、
> 演習後の `terraform destroy` で他プロジェクトの OIDC 連携ごと消してしまうためです。
>
> 誰かと共用している AWS アカウントで受講するなら、既定のままで OK です。
> **自分専用のまっさらなアカウント**で、まだプロバイダが無い場合だけ `terraform.tfvars` に
> `create_oidc_provider = true` を足してください。判断に迷ったら、まず既定のまま apply して
> エラーメッセージで判断できます。
>
> | 状況 | 設定 | 間違えると |
> |---|---|---|
> | プロバイダが既にある | `false` (既定) | `true` にすると `EntityAlreadyExists` (409) |
> | プロバイダが無い | `true` | `false` のままだと `NoSuchEntity` |

> [!NOTE]
> IAM ロールは GitHub Actions の OIDC トークンでのみ assume でき、しかも
> `sub` クレームを `environment:<env>` に限定しています。つまり **GitHub Environments
> の保護ルールを通過しないと、その環境の AWS 権限が手に入らない**構造です。
> この意味は第3章で体感します。

## 0.4 GitHub 側の設定

Codespaces では、まず `gh` を自分のアカウントでログインし直します。環境変数を先に外さないと、
`gh` はそちらを優先し続けます。

```bash
unset GITHUB_TOKEN
gh auth login   # GitHub.com → HTTPS → Authenticate Git: Yes → スコープは既定のまま
gh auth status  # 末尾が (GITHUB_TOKEN) 以外になっていれば成功
```

`unset` はそのターミナルにだけ効きます。別のターミナルを開くと `GITHUB_TOKEN` が復活するので、
その場合は下のコマンドを `env -u GITHUB_TOKEN ./scripts/setup-github.sh solo` の形で実行してください。

次に、演習モードを選んでスクリプトを実行します。

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
| ラベル | `type: feat` / `type: fix` など (Conventional Commits の type と 1:1) | PR タイトルからの自動付与 → リリースノートのカテゴリ分け |

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
