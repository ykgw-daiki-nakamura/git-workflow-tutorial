# 管理者ガイド: AWS アカウントの準備

**このページは、演習環境を用意する人 (研修の主催者・チームリーダー) 向けです。**
参加者として演習するだけなら読む必要はありません → [第0章 セットアップ](./00-setup.md)

- 研修などで **1 つの AWS アカウントを複数人で共有する**場合 … このページ全体
- **自分の AWS アカウントで一人で演習する**場合 … [一人で演習する場合](#一人で演習する場合)だけ

## 参加者に渡すもの

参加者がやることは、**受け取った認証情報を Codespaces に登録するだけ**です。
そこまで持っていくのが、このページの目的です。

| 渡すもの | 例 | 用途 |
|---|---|---|
| `AWS_ACCESS_KEY_ID` | `AKIA...` (20 文字) | Codespaces secrets に登録してもらう |
| `AWS_SECRET_ACCESS_KEY` | 40 文字 | 同上 |
| `AWS_REGION` | `ap-northeast-1` | 同上 |
| `owner` | `alice` | 参加者の `terraform.tfvars` に書いてもらう |

> [!IMPORTANT]
> **`owner` は、あなたがポリシーを作るときに使った値と一字一句同じものを伝えてください。**
> ポリシーはリソース名 `<project_name>-<owner>-*` で許可範囲を絞るため、ここが食い違うと
> 参加者の `terraform apply` が `AccessDenied` で落ちます ([#30](https://github.com/ykgw-daiki-nakamura/git-workflow-tutorial/issues/30))。

## 仕組み

このチュートリアルが作るリソースは、名前がすべて `<project_name>-<owner>-...` で始まり、
全リソースに `Owner` タグが付きます。ポリシーはこの**名前のプレフィックス**と
**`Owner` タグ**の 2 つで許可範囲を絞ります。つまり **`owner` を参加者ごとに変えるだけで、
「自分のリソースにしか触れない IAM ユーザー」ができます。**

Terraform の state は各自の Codespace のローカルファイルなので、そもそも衝突しません。
デプロイ用ロールの信頼ポリシーも `repo:<自分のリポジトリ>:environment:<env>` に限定されて
いるため、**他人のロールは自分の GitHub Actions からは assume できません**。

`owner` は 13 文字以内 (英小文字・数字・ハイフン)。S3 バケット名の 63 文字制限から
逆算した上限で、`terraform plan` が検査します。

## 最初に 1 回だけやること

管理者権限のある認証情報で、このリポジトリの中で実行します。

### 1. GitHub OIDC プロバイダを作る

AWS アカウントに 1 つだけ作るアカウント共有リソースです。参加者は全員
`create_oidc_provider = false` のまま、これを参照します。

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com
```

既に存在する場合 (他プロジェクトが作っている) は、そのまま使えます。

### 2. 参加者ごとに IAM ユーザーとポリシーを作る

```bash
for OWNER in alice bob carol; do
  aws iam create-user --user-name "${OWNER}"

  # ポリシーの生成・登録・アタッチ。冪等なので、あとから何度実行してもよい
  ./scripts/apply-setup-policy.sh "${OWNER}"

  # アクセスキーを発行して本人にだけ安全な経路で渡す (画面にしか出ない)
  aws iam create-access-key --user-name "${OWNER}"
done
```

IAM ユーザー名を `owner` と別にしたい場合は `--user` で渡します。

```bash
./scripts/apply-setup-policy.sh alice --user git-workflow-tutorial-alice
```

`apply-setup-policy.sh` は実行時に、どの名前を許可したのかを表示します。

```
==> owner       : alice
==> IAM ユーザー: git-workflow-tutorial-alice
==> 許可する名前: gitflow-tutorial-alice-*
```

**この「許可する名前」が、参加者の `terraform.tfvars` の `owner` から組み立てられる名前と
一致している**ことを確認してください。ここがこの手順の要です。

## リポジトリを更新したら、ポリシーを貼り直す

> [!IMPORTANT]
> **このリポジトリを更新したら、参加者ごとに `apply-setup-policy.sh` を実行し直して
> ください。**ポリシーはリソース名で許可範囲を絞っているため、命名を変える更新が入ると、
> 古いポリシーの許可は新しい名前のリソースに届かなくなります。

```bash
for OWNER in alice bob carol; do ./scripts/apply-setup-policy.sh "${OWNER}"; done
```

このスクリプトは冪等です。ポリシーが無ければ作り、あれば新しいバージョンに切り替えるだけ。
古い名前のポリシー (`gitflow-tutorial-setup`) が付いていれば検出してデタッチします。

実際にこれが必要になったことがあります
([#28](https://github.com/ykgw-daiki-nakamura/git-workflow-tutorial/issues/28))。
リソース名に `owner` が入るようになった際、それ以前のポリシーは ECR リポジトリを
`gitflow-tutorial-backend` という**完全一致**で許可していたため、
`gitflow-tutorial-alice-backend` に改名された瞬間に許可の外に出て、参加者全員の
`terraform apply` が `ecr:CreateRepository` の `AccessDenied` で止まりました。
S3 や Lambda は `gitflow-tutorial-*` というワイルドカードだったのでたまたま動き続け、
ECR だけが壊れたぶん原因が分かりにくい形になりました。

参加者側は [`check-aws-permissions.sh`](../scripts/check-aws-permissions.sh) を実行すれば、
`terraform apply` を流す前に権限が揃っているかを確認できます。

## コンソールから手でポリシーを登録する場合

CLI の管理者権限が手元に無い場合は、JSON を生成してコンソールに貼り付けます。

```bash
./scripts/gen-setup-policy.sh alice > /tmp/setup-policy-alice.json
cat /tmp/setup-policy-alice.json
```

**第 1 引数は `owner` です。IAM ユーザー名ではありません。** 実行すると、標準エラーに
どの名前向けに作ったのかが出ます。

```
生成しました (owner=alice, リソース名のプレフィックス=gitflow-tutorial-alice-)
```

出力された JSON を **IAM → ポリシー → ポリシーを作成 → JSON** に貼り、作成したポリシーを
IAM ユーザーにアタッチしてください。

> [!WARNING]
> JSON は**標準出力**に、上の案内文は**標準エラー**に出ます。ターミナルの表示を範囲選択で
> コピーすると案内文まで混ざり、IAM に弾かれます。上のように**ファイルへリダイレクトしてから**
> 開いてください。
>
> また、第 2 引数の `project_name` は、参加者が `terraform.tfvars` で `project_name` を
> 上書きしている場合だけ渡します。**上書きしていないなら省略してください** (既定値は
> `terraform/variables.tf` の `gitflow-tutorial`)。ここにリポジトリ名や IAM ユーザー名を
> 渡してしまうと、プレフィックスが食い違って `AccessDenied` になります。

## 一人で演習する場合

自分の AWS アカウントで一人で演習するなら、**`AdministratorAccess` を持った IAM ユーザーを
作り、そのアクセスキーを使うのが手っ取り早く、確実**です。このチュートリアルは IAM ロールと
OIDC プロバイダまで作るため、権限を絞りすぎると `terraform apply` の途中で AccessDenied に
なって余計に時間を溶かします。

1. AWS マネジメントコンソール → **IAM** → **ユーザー** → **ユーザーを作成**
2. ユーザー名は任意 (例: `gitflow-tutorial`)。コンソールへのアクセスは不要
3. 許可のオプションで **ポリシーを直接アタッチする** → `AdministratorAccess`
4. 作成後、**セキュリティ認証情報** タブ → **アクセスキーを作成**
5. ユースケースは **コマンドラインインターフェイス (CLI)** を選択
6. `AWS_ACCESS_KEY_ID` と `AWS_SECRET_ACCESS_KEY` をコピー
   (**シークレットキーはこの画面でしか表示されません**)

権限を絞りたい場合は、上と同じ手順で自分にポリシーを当てられます。

```bash
./scripts/apply-setup-policy.sh <自分の owner> --user <自分の IAM ユーザー名>
```

`owner` は好きな値で構いません。ただし [第0章 0.2](./00-setup.md#02-aws-リソースの作成) で
`terraform.tfvars` に書く `owner` と同じにしてください。

### まっさらなアカウントで OIDC プロバイダも自分で作る場合

生成されるポリシーは OIDC プロバイダに対して **参照 (`Get`) しか許可していません**。
プロバイダは URL ごとに AWS アカウントで 1 つしか作れないアカウント共有リソースで、削除権限を
持っていると、誤操作や `terraform destroy` で**他プロジェクトの OIDC 連携を壊せてしまう**ためです。
既定 (`create_oidc_provider = false`) ではそもそも作成しないので、これで足ります。

`create_oidc_provider = true` にする場合だけ、
[`setup-policy-oidc-create.json`](./assets/setup-policy-oidc-create.json) を**追加で**
アタッチしてください。

## IAM Identity Center (AWS SSO) を使っている組織の場合

会社から「AWS のアクセスポータル」の URL を渡されているなら、そちらから
**有効期限つきの一時認証情報**を取得します。この場合は `AWS_SESSION_TOKEN` もセットで必要です。

1. 組織のアクセスポータル (`https://<組織名>.awsapps.com/start`) にログイン
2. 演習に使う AWS アカウント → 権限セットの行を開く
3. **Access keys** をクリックすると、`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` /
   `AWS_SESSION_TOKEN` の 3 つが表示されます

ローカルの VS Code で開く場合は、コピーする代わりにプロファイルを作っておくほうが、
期限切れのたびに貼り直さずに済みます (ホスト側の `~/.aws` がコンテナに読み取り専用で
マウントされます)。

```bash
aws configure sso          # SSO start URL / リージョン / アカウント / 権限セットを対話で選ぶ
aws sso login --profile <作ったプロファイル名>
export AWS_PROFILE=<作ったプロファイル名>
```

自分に IAM の権限がない場合は、`gen-setup-policy.sh` が出力した JSON をそのまま管理者に渡して、
権限セットに含めてもらうのが早いです。

## このポリシーが何を許可しているか

以下は `owner = alice` で生成した場合です (プレフィックスは `gitflow-tutorial-alice-`)。
この認証情報で動かすのは `terraform apply` / `terraform destroy` と
[`bootstrap-image.sh`](../scripts/bootstrap-image.sh) (ECR への docker push) だけです。
アプリのデプロイ自体は GitHub Actions が OIDC で別のロールを assume して行うため、ここでの
認証情報は**インフラの作成と削除**にしか使いません。

| Sid | 許可 | なぜ必要か |
|---|---|---|
| `EcrAuthToken` / `EcrRepository` | ECR リポジトリ `gitflow-tutorial-alice-backend` への全操作と `ecr:GetAuthorizationToken` | リポジトリ作成と `bootstrap-image.sh` の docker push。認証トークン取得だけはリソース指定不可なので `*` |
| `S3FrontendBuckets` | `gitflow-tutorial-alice-*-frontend-*` バケットへの全操作 | バケット作成、ポリシー設定、`force_destroy` での中身ごと削除 |
| `LambdaFunctions` | `gitflow-tutorial-alice-*` 関数への全操作 | 関数と Function URL の作成・削除 |
| `CloudFrontCreateDistributionTaggedAsMine` | ディストリビューションの作成。ただし **`Owner=alice` タグを付ける場合のみ** (`aws:RequestTag`) | CloudFront の作成系アクションはリソース指定に対応していないため、`Resource` は `*` にせざるを得ない。代わりに**作成時のタグを条件にする**ことで「自分名義でしか作れない」に絞る |
| `CloudFrontTagDistributionAsMine` | ディストリビューションへの `Owner=alice` タグ付与 | Terraform は内部で `CreateDistributionWithTags` を呼ぶ。この API は IAM 上 `CreateDistribution` **と** `TagResource` の両方で認可されるため、片方だけでは作成できない |
| `CloudFrontOwnDistributionsOnly` | 更新・削除・invalidation・タグの削除。ただし **`Owner=alice` タグが付いたものだけ** (`aws:ResourceTag`) | 他の参加者のディストリビューションを**変更・削除できない**ようにする本体。ここが効くので `Resource` が `distribution/*` でも実質「自分のものだけ」になる |
| `CloudFrontReadOnlyUnscopable` / `CloudFrontOriginAccessControlUnscopable` | ディストリビューションの一覧と参照、キャッシュポリシーの参照、**OAC の全操作** | 絞れない箇所 ([下記](#絞りきれない箇所)) |
| `IamRoles` | `gitflow-tutorial-alice-*` **ロールのみ**の作成・削除・インラインポリシー設定 | デプロイ用ロール ×3 と Lambda 実行ロール |
| `IamAttachLambdaBasicExecutionOnly` | 管理ポリシーのアタッチを `AWSLambdaBasicExecutionRole` **だけ**に限定 | 任意の管理ポリシー (例: `AdministratorAccess`) をアタッチできると権限昇格になるため条件で塞いでいる |
| `IamPassRoleToLambdaOnly` | `gitflow-tutorial-alice-lambda-exec` を **Lambda にだけ** 渡せる | Lambda 作成時の `PassRole`。渡し先サービスを条件で限定 |
| `IamGithubOidcProviderRead` | OIDC プロバイダの **参照のみ** (`Get`) | GitHub Actions の OIDC 連携。既定では既存プロバイダを参照するだけなので、作成・削除の権限は要らない |
| `CleanupLogGroupsList` / `CleanupLogGroups` | ロググループの一覧取得と、`/aws/lambda/gitflow-tutorial-alice-*` の削除 | [終章](./99-cleanup.md)の後片付け。一覧取得は特定のロググループに対する操作ではなく、IAM が「名前が空の ARN」で認可判定するため、リソース指定できず `*` になる (削除の方はプレフィックスで絞れる) |

`Owner` タグは `terraform/main.tf` の `default_tags` が全リソースに付けます。**タグの値を
変えるとポリシーの条件と食い違い、`terraform apply` が AccessDenied になります**。

### 絞りきれない箇所

**このポリシーは「事故」を防ぐためのもので、悪意ある参加者に対する境界ではありません。**
同じアカウントを共有する相手が信頼できる同僚である、という前提で使ってください。厳密に
分離するなら、参加者ごとに AWS アカウントを分ける (AWS Organizations) のが唯一確実な方法です。

塞げていないのは次の 4 点です。

- **CloudFront の参照 (`GetDistribution`)**: 参照系は**タグで絞れません**。`terraform destroy` は
  `DeleteDistribution` を投げたあと、`GetDistribution` が「そんなディストリビューションは無い」を
  返すまでポーリングして削除完了を確かめます。ところが**消えた瞬間にタグも消える**ため、
  `aws:ResourceTag/Owner` を条件にしていると、待っている NotFound の代わりに AccessDenied が
  返り、destroy がそこで止まります。そもそも `ListDistributions` はリソース指定に対応しておらず
  `Resource: "*"` にするしかなく、他人のディストリビューションの設定もそこから読めます。
  参照を絞っても隠せるものは無いので、`GetDistribution` も `*` にしています。
  **読めるだけで、変更・削除はできません** (そちらは `Owner` タグで絞っています)。
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

## 運用上の注意

| | |
|---|---|
| `owner` の長さ | 13 文字以内 (英小文字・数字・ハイフン)。S3 バケット名の 63 文字制限から逆算した上限で、`terraform plan` が検査します |
| CloudFront の上限 | 1 人あたり 3 ディストリビューション使います。アカウントの既定上限は 200 なので、数十人までは問題ありません |
| コストの按分 | 全リソースに `Owner` タグが付くので、コスト配分タグとして有効化すれば参加者ごとの内訳が取れます |
| 分離の強度 | 「事故」は防げますが、悪意には耐えません ([絞りきれない箇所](#絞りきれない箇所)) |

演習後の後片付け (IAM ユーザー・ポリシー・アクセスキーの削除) は
[終章](./99-cleanup.md)に書いています。
