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

### AWS 認証情報を取得する

まだ AWS の認証情報を持っていない場合は、ここで発行します。**すでに
`aws sts get-caller-identity` が通る環境がある人は、この節を飛ばして
「AWS 認証情報を渡す」へ進んでください。**

発行元は、所属組織が AWS IAM Identity Center (旧 AWS SSO) を使っているかどうかで
決まります。会社から「AWS のアクセスポータル」の URL を渡されているなら A、
個人アカウントで演習するなら B です。

<details>
<summary>▶ <b>A. IAM Identity Center (組織のアカウントを使う場合)</b></summary>

こちらは**有効期限つきの一時認証情報**なので、`AWS_SESSION_TOKEN` がセットで必要です。

1. 組織のアクセスポータル (`https://<組織名>.awsapps.com/start`) にログイン
2. 演習に使う AWS アカウント → 権限セットの行を開く
3. **Access keys** をクリックすると、`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` /
   `AWS_SESSION_TOKEN` の 3 つが表示されます。これをコピーして使います

ローカルで開く場合は、コピーする代わりにプロファイルを作っておくほうが
期限切れのたびに貼り直さずに済みます。

```bash
aws configure sso          # SSO start URL / リージョン / アカウント / 権限セットを対話で選ぶ
aws sso login --profile <作ったプロファイル名>
export AWS_PROFILE=<作ったプロファイル名>
```

</details>

<details>
<summary>▶ <b>B. IAM ユーザーのアクセスキー (個人の AWS アカウントで演習する場合)</b></summary>

1. AWS マネジメントコンソール → **IAM** → **ユーザー** → **ユーザーを作成**
2. ユーザー名は任意 (例: `gitflow-tutorial`)。コンソールへのアクセスは不要
3. 許可のオプションで **ポリシーを直接アタッチする** を選び、権限を付ける
   (下の「必要な権限」を参照)
4. 作成後、そのユーザーの **セキュリティ認証情報** タブ → **アクセスキーを作成**
5. ユースケースは **コマンドラインインターフェイス (CLI)** を選択
6. 表示された `AWS_ACCESS_KEY_ID` と `AWS_SECRET_ACCESS_KEY` をコピー
   (**シークレットキーはこの画面でしか表示されません**)

このキーは期限のない長期認証情報なので、`AWS_SESSION_TOKEN` は不要です。

ローカルで開く場合は `~/.aws` に保存しておきます。

```bash
aws configure   # 上の 2 つと region (ap-northeast-1) を入力。output は json でよい
```

</details>

### 必要な権限

この認証情報で動かすのは `terraform apply` / `terraform destroy` と
`scripts/bootstrap-image.sh` (ECR への docker push) だけです。アプリのデプロイ自体は
GitHub Actions が OIDC で別のロールを assume して行うため、ここでの認証情報は
**インフラの作成と削除**にしか使いません。

| サービス | 何をするか | 作られるもの |
|---|---|---|
| ECR | リポジトリ作成、イメージの push | ECR リポジトリ ×1 |
| IAM | OIDC プロバイダ、ロール、インラインポリシーの作成 | GitHub OIDC プロバイダ ×1、デプロイ用ロール ×3、Lambda 実行ロール ×3 |
| Lambda | 関数と Function URL の作成 | Lambda ×3 |
| S3 | バケット、バケットポリシー、パブリックアクセスブロックの設定 | バケット ×3 |
| CloudFront | ディストリビューションと OAC の作成 | ディストリビューション ×3 |
| CloudWatch Logs | Lambda のロググループ (実行時に自動作成) | ロググループ ×3 |
| STS | `aws sts get-caller-identity` での疎通確認 | — |

個人の AWS アカウントで演習するなら、**`AdministratorAccess` をアタッチするのが
手っ取り早く、確実**です (このチュートリアルは IAM ロールと OIDC プロバイダまで作るため、
権限を絞りすぎると `terraform apply` の途中で AccessDenied になって余計に時間を溶かします)。

組織のアカウントを使う場合や、権限を絞りたい場合のために、このチュートリアルに必要な分だけを
許可するカスタムポリシーを [`docs/assets/setup-policy.json`](./assets/setup-policy.json)
に用意しています。リソース名を `gitflow-tutorial-*` に限定してあるので、同じアカウントの
他のリソースには手を出せません。

```bash
# 管理者権限のある認証情報で 1 回だけ実行する (作成するのはポリシーだけ)
aws iam create-policy \
  --policy-name gitflow-tutorial-setup \
  --policy-document file://docs/assets/setup-policy.json

# B で作った IAM ユーザーにアタッチする
aws iam attach-user-policy \
  --user-name gitflow-tutorial \
  --policy-arn arn:aws:iam::<アカウントID>:policy/gitflow-tutorial-setup
```

コンソールから作る場合は **IAM → ポリシー → ポリシーを作成 → JSON** に上記ファイルの中身を
貼り付けてください。組織のアカウントで自分に IAM 権限がない場合は、この JSON をそのまま
管理者に渡して権限セットに含めてもらうのが早いです。

<details>
<summary>▶ このポリシーが何を許可しているか</summary>

| Sid | 許可 | なぜ必要か |
|---|---|---|
| `EcrAuthToken` / `EcrRepository` | ECR リポジトリ `gitflow-tutorial-backend` への全操作と `ecr:GetAuthorizationToken` | リポジトリ作成と `bootstrap-image.sh` の docker push。認証トークン取得だけはリソース指定不可なので `*` |
| `S3FrontendBuckets` | `gitflow-tutorial-*-frontend-*` バケットへの全操作 | バケット作成、ポリシー設定、`force_destroy` での中身ごと削除 |
| `LambdaFunctions` | `gitflow-tutorial-*` 関数への全操作 | 関数と Function URL の作成・削除 |
| `CloudFront` | `cloudfront:*` | CloudFront は作成系アクションがリソース指定に対応していないため `*` |
| `IamRoles` | `gitflow-tutorial-*` **ロールのみ**の作成・削除・インラインポリシー設定 | デプロイ用ロール ×3 と Lambda 実行ロール |
| `IamAttachLambdaBasicExecutionOnly` | 管理ポリシーのアタッチを `AWSLambdaBasicExecutionRole` **だけ**に限定 | 任意の管理ポリシー (例: `AdministratorAccess`) をアタッチできると権限昇格になるため条件で塞いでいる |
| `IamPassRoleToLambdaOnly` | `gitflow-tutorial-lambda-exec` を **Lambda にだけ** 渡せる | Lambda 作成時の `PassRole`。渡し先サービスを条件で限定 |
| `IamGithubOidcProvider` | `token.actions.githubusercontent.com` の OIDC プロバイダ操作 | GitHub Actions の OIDC 連携 |
| `CleanupLogGroups` | `/aws/lambda/gitflow-tutorial-*` のロググループ削除 | [終章](./99-cleanup.md)の後片付け |

`terraform.tfvars` で `project_name` を既定の `gitflow-tutorial` から変更した場合は、
JSON 内の ARN のプレフィックスも合わせて書き換えてください。

</details>

> [!TIP]
> 権限が足りているかは、実際に `terraform apply` を流してみるのが一番早いです。
> 途中で `AccessDenied` / `not authorized to perform: <アクション>` が出たら、
> そのアクションが不足しています。作成済みのリソースは
> `terraform -chdir=terraform destroy` で消してからやり直せます。

> [!CAUTION]
> アクセスキーはパスワードと同じです。リポジトリにコミットしない (`.gitignore` 済みの
> `terraform.tfvars` にも書かない)、Slack やメールに貼らない。B で作ったキーは演習が
> 終わったら [終章](./99-cleanup.md) で削除します。

`AWS_REGION` は `ap-northeast-1` を使います (`terraform/variables.tf` の既定値。
変えたい場合は `terraform.tfvars` で `aws_region` を上書きしてください)。

### AWS 認証情報を渡す

取得した認証情報を、開き方に応じてコンテナに渡します。

| 開き方 | 渡し方 |
|---|---|
| ローカルの VS Code | ホストの `~/.aws` が読み取り専用でマウントされます。上の `aws configure` / `aws configure sso` を**ホスト側で**済ませてあれば、何もしなくて OK |
| Codespaces | リポジトリの **Settings → Secrets and variables → Codespaces** に `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_REGION` を登録 (A の一時認証情報なら `AWS_SESSION_TOKEN` も) |

> [!NOTE]
> Codespaces secrets は起動時に環境変数として注入されます。**すでに起動している
> Codespace には反映されない**ので、登録後に再起動してください。

```bash
aws sts get-caller-identity   # Account / Arn が返れば準備完了
```

`InvalidClientTokenId` や `ExpiredToken` が返る場合は、キーの貼り間違いか、
A の一時認証情報の期限切れです (`aws sso login` で取り直してください)。

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
正しく渡っています。空の変数を消し、リージョンを明示すれば通ります。

```bash
unset AWS_PROFILE AWS_SESSION_TOKEN     # B の恒久キーなら SESSION_TOKEN は不要
export AWS_REGION=ap-northeast-1        # terraform/variables.tf の既定値
aws sts get-caller-identity
```

恒久的に直すなら、Codespaces secrets に `AWS_REGION` を登録し (未登録だと空文字列に
なります)、`AWS_PROFILE` はホスト側でも設定しないでおくのが確実です。

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
