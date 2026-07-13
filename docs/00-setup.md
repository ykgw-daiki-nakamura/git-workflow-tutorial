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
許可するカスタムポリシーを用意しています。

このチュートリアルが作るリソースは、名前がすべて `<project_name>-<owner>-...` で始まり、
全リソースに `Owner` タグが付きます (`terraform/variables.tf` の `owner`)。ポリシーは
この**名前のプレフィックス**と **`Owner` タグ**の 2 つで許可範囲を絞るので、`owner` を
変えるだけで「自分のリソースにしか触れない IAM ユーザー」が作れます。1 つの AWS アカウントを
複数人で共有して演習できるのは、この仕組みのおかげです ([後述](#1-つの-aws-アカウントを複数人で共有する))。

ポリシーは [`scripts/gen-setup-policy.sh`](../scripts/gen-setup-policy.sh) で
[テンプレート](./assets/setup-policy.template.json)から生成します。生成から IAM への
登録・アタッチまでを [`scripts/apply-setup-policy.sh`](../scripts/apply-setup-policy.sh) が
まとめて行います (管理者権限のある認証情報で実行してください)。

```bash
# 演習に使う識別子。terraform.tfvars の owner と同じ値にすること
./scripts/apply-setup-policy.sh alice
```

**このスクリプトは何度実行しても同じ結果になります** (冪等)。ポリシーが無ければ作り、
あれば新しいバージョンに切り替えるだけです。**リポジトリを更新したら、参加者ごとに
これを実行し直してください。**リソース名の付け方が変わると、古いポリシーの許可は
名前が変わったリソースに届かなくなり、`terraform apply` が `AccessDenied` になります
(実際に起きました: [#28](https://github.com/ykgw-daiki-nakamura/git-workflow-tutorial/issues/28))。

IAM ユーザー名が `owner` と違う場合は `--user` で渡します。

```bash
./scripts/apply-setup-policy.sh alice --user git-workflow-tutorial-alice
```

コンソールから作る場合は、`./scripts/gen-setup-policy.sh alice` の出力を
**IAM → ポリシー → ポリシーを作成 → JSON** に貼り付けてください。組織のアカウントで
自分に IAM 権限がない場合は、この JSON をそのまま管理者に渡して権限セットに含めて
もらうのが早いです。

> [!WARNING]
> **ポリシーを作るときの `owner` は、参加者の `terraform.tfvars` の `owner` と一字一句
> 同じにしてください。**ポリシーはリソース名 `<project_name>-<owner>-*` で許可範囲を
> 絞るため、ここが食い違うと、**プレフィックスで絞った許可が 1 つ残らず効かなくなります**
> (`Resource: "*"` の許可だけが通るので、権限が半分あるように見えて余計に紛らわしい)。
> 手で IAM に登録するときに起きがちです ([#30](https://github.com/ykgw-daiki-nakamura/git-workflow-tutorial/issues/30))。
>
> `apply-setup-policy.sh` は生成とアタッチを 1 つの `owner` で行うので、この食い違いが
> 起きません。参加者側は `./scripts/check-aws-permissions.sh` を実行すれば、食い違って
> いる場合にその旨を表示します。

<details>
<summary>▶ このポリシーが何を許可しているか</summary>

以下は `owner = alice` で生成した場合です (プレフィックスは `gitflow-tutorial-alice-`)。

| Sid | 許可 | なぜ必要か |
|---|---|---|
| `EcrAuthToken` / `EcrRepository` | ECR リポジトリ `gitflow-tutorial-alice-backend` への全操作と `ecr:GetAuthorizationToken` | リポジトリ作成と `bootstrap-image.sh` の docker push。認証トークン取得だけはリソース指定不可なので `*` |
| `S3FrontendBuckets` | `gitflow-tutorial-alice-*-frontend-*` バケットへの全操作 | バケット作成、ポリシー設定、`force_destroy` での中身ごと削除 |
| `LambdaFunctions` | `gitflow-tutorial-alice-*` 関数への全操作 | 関数と Function URL の作成・削除 |
| `CloudFrontCreateDistributionTaggedAsMine` | ディストリビューションの作成。ただし **`Owner=alice` タグを付ける場合のみ** (`aws:RequestTag`) | CloudFront の作成系アクションはリソース指定に対応していないため、`Resource` は `*` にせざるを得ない。代わりに**作成時のタグを条件にする**ことで「自分名義でしか作れない」に絞る |
| `CloudFrontTagDistributionAsMine` | ディストリビューションへの `Owner=alice` タグ付与 | Terraform は内部で `CreateDistributionWithTags` を呼ぶ。この API は IAM 上 `CreateDistribution` **と** `TagResource` の両方で認可されるため、片方だけでは作成できない |
| `CloudFrontOwnDistributionsOnly` | 参照・更新・削除・invalidation。ただし **`Owner=alice` タグが付いたものだけ** (`aws:ResourceTag`) | 他の参加者のディストリビューションを触れないようにする本体。ここが効くので `Resource` が `distribution/*` でも実質「自分のものだけ」になる |
| `CloudFrontReadOnlyUnscopable` / `CloudFrontOriginAccessControlUnscopable` | ディストリビューションの一覧、キャッシュポリシーの参照、**OAC の全操作** | 絞れない箇所 ([下記](#絞りきれない箇所)) |
| `IamRoles` | `gitflow-tutorial-alice-*` **ロールのみ**の作成・削除・インラインポリシー設定 | デプロイ用ロール ×3 と Lambda 実行ロール |
| `IamAttachLambdaBasicExecutionOnly` | 管理ポリシーのアタッチを `AWSLambdaBasicExecutionRole` **だけ**に限定 | 任意の管理ポリシー (例: `AdministratorAccess`) をアタッチできると権限昇格になるため条件で塞いでいる |
| `IamPassRoleToLambdaOnly` | `gitflow-tutorial-alice-lambda-exec` を **Lambda にだけ** 渡せる | Lambda 作成時の `PassRole`。渡し先サービスを条件で限定 |
| `IamGithubOidcProviderRead` | OIDC プロバイダの **参照のみ** (`Get`) | GitHub Actions の OIDC 連携。既定 (`create_oidc_provider = false`) では既存プロバイダを参照するだけなので、作成・削除の権限は要らない ([後述](#oidc-プロバイダを自分で作る場合)) |
| `CleanupLogGroupsList` / `CleanupLogGroups` | ロググループの一覧取得と、`/aws/lambda/gitflow-tutorial-alice-*` の削除 | [終章](./99-cleanup.md)の後片付け。一覧取得は特定のロググループに対する操作ではなく、IAM が「名前が空の ARN」で認可判定するため、リソース指定できず `*` になる (削除の方はプレフィックスで絞れる) |

`Owner` タグは `terraform/main.tf` の `default_tags` が全リソースに付けます。**タグの値を
変えるとポリシーの条件と食い違い、`terraform apply` が AccessDenied になります**。

#### 絞りきれない箇所

**このポリシーは「事故」を防ぐためのもので、悪意ある参加者に対する境界ではありません。**
同じアカウントを共有する相手が信頼できる同僚である、という前提で使ってください。厳密に
分離するなら、参加者ごとに AWS アカウントを分ける (AWS Organizations) のが唯一確実な方法です。

塞げていないのは次の 3 点です。

- **OAC (Origin Access Control)**: CloudFront の OAC は**タグに対応していません** (ARN 以外に
  条件を書く手掛かりがない)。しかも作成アクションはリソース指定にも対応していないため、
  `Resource: "*"` にするしかありません。他人の OAC を消せてしまいますが、使用中の OAC は
  削除できないので、実害は出にくい箇所です。
- **CloudFront のタグ付け**: `TagResource` は「`Owner=alice` を付ける」ことしか条件にできず、
  「タグの付いていないリソースにだけ付ける」とは書けません。他人のディストリビューションを
  `Owner=alice` に**付け替えて**から消す、という手順は踏めてしまいます。
- **自分のロールへのインラインポリシー**: `IamRoles` には `iam:PutRolePolicy` が含まれます
  (デプロイロールの権限を Terraform が書き込むため必須)。自分のデプロイロールに強い権限を
  書き込み、GitHub Actions 経由で assume すれば、プレフィックスの外にも手が届きます。
  管理ポリシーのアタッチ (`AdministratorAccess` など) は条件で塞いでいますが、インライン
  ポリシーは塞げていません。

#### OIDC プロバイダを自分で作る場合

上のポリシーは OIDC プロバイダに対して **参照 (`Get`) しか許可していません**。
プロバイダは URL ごとに AWS アカウントで 1 つしか作れないアカウント共有リソースで、
削除権限を持っていると、誤操作や `terraform destroy` で**他プロジェクトの OIDC 連携を
壊せてしまう**ためです ([0.3](#03-aws-リソースの作成) 参照)。既定ではそもそも作成しないので、
これで足ります。

自分専用のまっさらなアカウントで `create_oidc_provider = true` にする場合だけ、
[`setup-policy-oidc-create.json`](./assets/setup-policy-oidc-create.json) を**追加で**
アタッチしてください。

</details>

> [!TIP]
> 権限が足りているかは、`terraform apply` の前に確かめられます。何も作らずに
> 読み取りだけで確認するので、いつ実行しても安全です。
>
> ```bash
> ./scripts/check-aws-permissions.sh        # owner は terraform.tfvars から読む
> ```
>
> 足りない権限があれば、アクション名と直し方を表示します。apply の途中で生の
> `AccessDenied` を踏むより、ここで気付くほうが早いです。
> (S3 と CloudFront の作成は読み取りだけでは確かめられないため、この検査は万能では
> ありません。apply が `not authorized to perform: <アクション>` で落ちたら、
> そのアクションが不足しています。)

> [!CAUTION]
> アクセスキーはパスワードと同じです。リポジトリにコミットしない (`.gitignore` 済みの
> `terraform.tfvars` にも書かない)、Slack やメールに貼らない。B で作ったキーは演習が
> 終わったら [終章](./99-cleanup.md) で削除します。

`AWS_REGION` は `ap-northeast-1` を使います (`terraform/variables.tf` の既定値。
変えたい場合は `terraform.tfvars` で `aws_region` を上書きしてください)。

### 1 つの AWS アカウントを複数人で共有する

研修などで、参加者全員が 1 つの AWS アカウントで演習することができます。**`owner` を
参加者ごとに変える**だけで、リソース名 (`gitflow-tutorial-<owner>-...`) と `Owner` タグが
分かれ、上のポリシーがその範囲に許可を絞ります。state は各自の Codespace のローカル
ファイルなので、そもそも衝突しません。

デプロイ用ロールの信頼ポリシーも `repo:<自分のリポジトリ>:environment:<env>` に
限定されているため、**他人のロールは自分の GitHub Actions からは assume できません**。

#### 管理者が最初に 1 回だけやること

```bash
# 1. GitHub OIDC プロバイダをアカウントに 1 つ作る (アカウント共有リソース)
#    参加者は全員 create_oidc_provider = false のまま、これを参照する
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com

# 2. 参加者ごとに IAM ユーザーとポリシーを作る
for OWNER in alice bob carol; do
  aws iam create-user --user-name "${OWNER}"

  # ポリシーの生成・登録・アタッチ。冪等なので、あとから何度実行してもよい
  ./scripts/apply-setup-policy.sh "${OWNER}"

  # アクセスキーを発行して本人にだけ安全な経路で渡す (画面にしか出ない)
  aws iam create-access-key --user-name "${OWNER}"
done
```

> [!IMPORTANT]
> **このリポジトリを更新したら、参加者ごとに `apply-setup-policy.sh` を実行し直して
> ください。**ポリシーはリソース名 (`gitflow-tutorial-<owner>-...`) で許可範囲を絞って
> いるため、命名を変える更新が入ると、古いポリシーの許可は新しい名前のリソースに
> 届かなくなります。
>
> 実際にこれが起きたことがあります ([#28](https://github.com/ykgw-daiki-nakamura/git-workflow-tutorial/issues/28))。
> リソース名に `owner` が入るようになった際、それ以前のポリシーは ECR リポジトリを
> `gitflow-tutorial-backend` という**完全一致**で許可していたため、
> `gitflow-tutorial-alice-backend` に改名された瞬間に許可の外に出て、
> 参加者全員の `terraform apply` が `ecr:CreateRepository` の `AccessDenied` で
> 止まりました。S3 や Lambda は `gitflow-tutorial-*` というワイルドカードだったので
> たまたま動き続け、ECR だけが壊れたぶん原因が分かりにくい形になりました。
>
> 貼り直しは 1 行です。古い名前のポリシー (`gitflow-tutorial-setup`) が付いていれば、
> スクリプトが検出してデタッチします。
>
> ```bash
> for OWNER in alice bob carol; do ./scripts/apply-setup-policy.sh "${OWNER}"; done
> ```
>
> 参加者側は `./scripts/check-aws-permissions.sh` で、`terraform apply` を流す前に
> 権限が揃っているかを確認できます。

#### 参加者がやること

`terraform.tfvars` に、管理者から伝えられた `owner` を書きます ([0.3](#03-aws-リソースの作成))。
これだけで、自分専用のリソース一式ができます。

> [!IMPORTANT]
> `owner` の値は、管理者がポリシーを生成したときの値と**一字一句同じ**にしてください。
> ズレていると、名前もタグも許可範囲の外に出るため `terraform apply` が AccessDenied で
> 落ちます。

#### 気をつける点

| | |
|---|---|
| `owner` の長さ | 13 文字以内 (英小文字・数字・ハイフン)。S3 バケット名の 63 文字制限から逆算した上限で、`terraform plan` が検査します |
| CloudFront の上限 | 1 人あたり 3 ディストリビューション使います。アカウントの既定上限は 200 なので、数十人までは問題ありません |
| コストの按分 | 全リソースに `Owner` タグが付くので、コスト配分タグとして有効化すれば参加者ごとの内訳が取れます |
| 分離の強度 | 「事故」は防げますが、悪意には耐えません ([絞りきれない箇所](#絞りきれない箇所)) |

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
push → 全体を apply」の 3 段階で進めます。

```bash
cat > terraform/terraform.tfvars <<EOF
github_repository = "<GitHubアカウント>/<リポジトリ名>"
owner             = "<自分の識別子>"
EOF

./scripts/check-aws-permissions.sh    # 権限が揃っているか (読み取りだけ。何も作らない)

terraform -chdir=terraform init
terraform -chdir=terraform apply -target=aws_ecr_repository.backend   # ECR だけ先に作成

./scripts/bootstrap-image.sh          # :bootstrap イメージを push

terraform -chdir=terraform apply      # 全体を作成 (数分かかる)
```

最初の `check-aws-permissions.sh` は、いまの認証情報で必要な権限が揃っているかを
読み取りだけで確かめます。ここで `権限なし` が出たら、先に進んでも `terraform apply` の
途中で `AccessDenied` になるだけなので、表示された手順に従ってポリシーを直してください。

`owner` は作られるリソースの名前とタグに入る、あなた専用の目印です (英小文字・数字・
ハイフン、13 文字以内)。自分のアカウントで一人で演習するなら好きな値で構いません。
**1 つの AWS アカウントを複数人で共有する場合は、ここが参加者ごとの仕切りになります**
([前述](#1-つの-aws-アカウントを複数人で共有する))。

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
