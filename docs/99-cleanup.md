# 終章 後片付け

演習が終わったら AWS リソースを削除します。放置してもコストはごく小さい構成
ですが、削除まで含めて演習です。

## AWS リソースの削除

```bash
terraform -chdir=terraform destroy
```

- ECR は `force_delete = true` なのでイメージごと消えます
- S3 は `force_destroy = true` なのでオブジェクトごと消えます
- CloudFront の削除には数分かかります

完了後、コンソールで残骸がないか確認してください
(CloudWatch Logs のロググループ `/aws/lambda/gitflow-tutorial-*` は
Lambda 削除後も残るため、気になる場合は手動で削除します)。

```bash
aws logs describe-log-groups \
  --log-group-name-prefix /aws/lambda/gitflow-tutorial \
  --query 'logGroups[].logGroupName' --output text | tr '\t' '\n' \
  | xargs -I{} aws logs delete-log-group --log-group-name {}
```

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
