# 終章 後片付け

演習が終わったら AWS リソースを削除します。放置してもコストはごく小さい構成
ですが、削除まで含めて演習です。

## AWS リソースの削除

```bash
# 自分のリソースの名前 (gitflow-tutorial-<owner>) を先に控える。
# destroy すると terraform の出力も消えるため、後からでは取れない
PREFIX=$(terraform -chdir=terraform output -raw name_prefix)
echo "${PREFIX}"

terraform -chdir=terraform destroy
```

> [!IMPORTANT]
> **控えた `PREFIX` は、AWS リソースの作成者や管理者にも伝えてください。** この後の
> ロググループ削除で使うだけの値ではありません。1 つの AWS アカウントを複数人で共有して
> 演習した場合 ([管理者ガイド](./90-admin.md))、管理者は最後に参加者全員分の IAM ユーザーと
> ポリシー (`gitflow-tutorial-<owner>-setup`) を削除します。その後片付けは、誰が
> どの `owner` を使ったかが分かって初めて実行できます。自分のアカウントで一人で演習した
> 場合は、自分が管理者なので報告は不要です。

- ECR は `force_delete = true` なのでイメージごと消えます
- S3 は `force_destroy = true` なのでオブジェクトごと消えます
- CloudFront の削除には数分かかります

> [!NOTE]
> **`cloudfront:GetDistribution` で AccessDenied が出て destroy が止まる場合**、ポリシーが
> 古いままです。管理者に `./scripts/apply-setup-policy.sh <owner>` の再実行を依頼して
> (自分のアカウントなら自分で実行して) から、`terraform destroy` をもう一度流してください。
> 削除自体は AWS 側で進んでいるので、2 回目は残りだけが片付きます。
>
> 参照権限を `Owner` タグで絞っていたのが原因です。Terraform は `DeleteDistribution` の後
> `GetDistribution` が NotFound を返すまで待ちますが、**消えた瞬間にタグも消える**ため、
> 条件付きだと NotFound の代わりに AccessDenied が返ってしまいます
> ([管理者ガイド](./90-admin.md#絞りきれない箇所))。

完了後、コンソールで残骸がないか確認してください
(CloudWatch Logs のロググループ `/aws/lambda/<PREFIX>-*` は Lambda 削除後も残るため、
気になる場合は手動で削除します)。

```bash
aws logs describe-log-groups \
  --log-group-name-prefix "/aws/lambda/${PREFIX}" \
  --query 'logGroups[].logGroupName' --output text | tr '\t' '\n' \
  | xargs -I{} aws logs delete-log-group --log-group-name {}
```

> [!WARNING]
> プレフィックスから `-<owner>` の部分を落として `/aws/lambda/gitflow-tutorial` で
> 実行しないでください。1 つの AWS アカウントを複数人で共有している場合
> ([管理者ガイド](./90-admin.md))、**他の参加者の
> ロググループまで一覧に入り、まとめて消えます**。最小権限ポリシーを使っていれば
> 他人の分は削除が拒否されますが、`AdministratorAccess` で演習している場合は通ります。

## AWS 認証情報の始末

第0章 B (IAM ユーザーのアクセスキー) で演習用のキーを発行した場合は、期限がない
長期認証情報なので **AWS 側から削除**してください。

- コンソール: **IAM → ユーザー → 該当ユーザー → セキュリティ認証情報 → アクセスキー → 削除**
  (演習専用に作ったユーザーなら、ユーザーごと削除してしまうのが確実です)

**Codespaces secrets の削除は A・B どちらでも必要です。** A (IAM Identity Center の
一時認証情報) は放っておいても失効しますが、失効するのは AWS 側の認証情報であって、
**secrets に登録した値そのものは残り続けます**。次に Codespace を起動したときに
失効済みの値が環境変数として注入され、`ExpiredToken` の原因になります。

**Settings → Secrets and variables → Codespaces** から、登録したものをすべて削除して
ください。A の場合は `AWS_SESSION_TOKEN` も、リージョンを明示した場合は `AWS_REGION` も
対象です。

| | 削除するもの |
|---|---|
| A: IAM Identity Center | Codespaces secrets (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_SESSION_TOKEN` / `AWS_REGION`) |
| B: IAM ユーザーのアクセスキー | 上記に加えて、**AWS 側のアクセスキー本体** (期限が無いため必須) |

`terraform destroy` の前にキーを消すと後片付けができなくなるので、順番に注意してください。

<details>
<summary>▶ 1 つの AWS アカウントを複数人で共有した場合 (管理者の後片付け)</summary>

参加者全員の `terraform destroy` が終わってから、管理者が実行します。

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

for OWNER in alice bob carol; do
  POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/gitflow-tutorial-${OWNER}-setup"

  # アクセスキーとポリシーを外してからでないとユーザーは削除できない
  aws iam list-access-keys --user-name "${OWNER}" \
    --query 'AccessKeyMetadata[].AccessKeyId' --output text | tr '\t' '\n' \
    | xargs -r -I{} aws iam delete-access-key --user-name "${OWNER}" --access-key-id {}

  aws iam detach-user-policy --user-name "${OWNER}" --policy-arn "${POLICY_ARN}"

  # ポリシーは既定以外のバージョンが残っていると削除できない。
  # apply-setup-policy.sh で貼り直していると版が増えているので、先に消す
  aws iam list-policy-versions --policy-arn "${POLICY_ARN}" \
    --query 'Versions[?!IsDefaultVersion].VersionId' --output text | tr '\t' '\n' \
    | xargs -r -I{} aws iam delete-policy-version --policy-arn "${POLICY_ARN}" --version-id {}

  aws iam delete-policy --policy-arn "${POLICY_ARN}"
  aws iam delete-user --user-name "${OWNER}"
done
```

GitHub OIDC プロバイダは**消さないのが既定**です。アカウント共有リソースなので、
他のプロジェクトが使っている可能性があります。この演習のために作り、他に使い道が
無いと確信できる場合だけ削除してください。

```bash
aws iam delete-open-id-connect-provider \
  --open-id-connect-provider-arn \
  "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
```

</details>

## GitHub 側

リポジトリごと消すなら操作は不要です。教材として残す場合:

- Rulesets / Environments はコストがかからないのでそのままで問題ありません
- `sync-github-vars.sh` が設定した variables には削除済みリソースの名前が
  残るため、混乱を避けたければ Settings → Secrets and variables → Actions
  から削除してください

## 振り返り

このハンズオンで一周したサイクルを、自分の言葉で説明できるか確認してみて
ください。

1. なぜ main への直 push を禁止し、squash merge に一本化するのか
2. なぜアーティファクトに `-rc.N` を焼き込まないのか
3. GA ワークフローからビルドを排除すると、何が保証できるようになるのか
4. なぜバグ修正は main が先 (upstream first) なのか
5. production の承認ゲートが「手順」ではなく「権限」である、とはどういうことか

すべて第1〜4章のどこかで、エラーメッセージや検品票として実際に目にした
はずです。

---

← [第5章 発展演習](./05-advanced.md) | [目次に戻る](./README.md)
