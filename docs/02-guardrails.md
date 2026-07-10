# 第2章 ガードレール体験

この章では**わざと違反行為を試みて、仕組みに止められる**体験をします。
ルールを「知っている」のと「破ろうとしても破れないことを確認した」のとでは
安心感がまったく違います。すべての手順で、**エラーが出れば成功**です。

> [!NOTE]
> ここで試すことはすべて安全です。ガードレールが機能していれば何も壊れませんし、
> 万一設定漏れで通ってしまったら、それはセットアップの問題を発見できたということです
> (`./scripts/setup-github.sh` を再実行してください)。

## 💥 2.1 main へ直接 push する

```bash
git switch main && git pull
git commit --allow-empty -m "直接pushのテスト"
git push
```

期待される結果:

```
remote: error: GH013: Repository rule violations found for refs/heads/main.
remote: - Changes must be made through a pull request.
```

**なぜ**: main はデプロイ可能であるべきトランクです。CI を通っていない変更が
入る経路 (直 push) を Ruleset が塞いでいます。後始末をしておきます。

```bash
git reset --hard origin/main
```

## 💥 2.2 main を force push で書き換える

```bash
git push --force
```

`non_fast_forward` ルールにより拒否されます (直 push 禁止と二重にブロック)。

**なぜ**: force push は共有ブランチの履歴を書き換え、全員の手元との整合性を
破壊します。squash merge 運用では main の履歴そのものが変更管理台帳なので、
書き換え不能であることが台帳としての信頼の根拠になります。

## 💥 2.3 規約違反の PR タイトルで出す

```bash
git switch -c feature/title-test
git commit --allow-empty -m "テスト"
git push -u origin feature/title-test
gh pr create --title "修正しました" --body "タイトル検証のテスト"
gh pr checks --watch
```

`pr-title` チェックが **fail** します。Actions のログを開くと、許可される
type の一覧 (`feat` / `fix` / `chore` ...) が表示されています。

タイトルを直すとチェックが通ることも確認しましょう。

```bash
gh pr edit --title "test: タイトル検証の動作確認"
gh pr checks --watch   # 今度は通る
```

**なぜ**: squash merge では PR タイトルがそのまま main のコミットメッセージに
なります。つまりタイトル検証は「main の履歴の品質検査」を PR の段階で
やっていることになります。確認できたら PR はクローズしてください。

```bash
gh pr close feature/title-test --delete-branch
```

## 💥 2.4 merge commit / rebase merge を試す

第1章で作った PR、または新しく PR を作って、GitHub の UI でマージボタンの
ドロップダウン (▼) を開いてください。

期待される結果: **Squash and merge しか存在しない**。

```bash
# CLI で試しても同じ
gh pr merge --merge
# => Merge commits are not allowed on this repository.
```

**なぜ**: マージ方式を人間の注意力に任せると必ず事故ります。リポジトリ設定で
選択肢そのものを消すのが最も確実なガードレールです。

## 💥 2.5 CI が落ちる変更をマージしようとする

```bash
git switch main && git pull
git switch -c feature/break-test
```

`backend/app/main.py` の `/api/healthz` の戻り値を `{"ok": False}` に書き換えて
push し、PR を作ります。

```bash
git add -A && git commit -m "テストを壊す"
git push -u origin feature/break-test
gh pr create --title "test: CI必須チェックの確認" --body "壊れたコードはマージできないことの確認"
```

`backend` チェックが fail し、**マージボタンが押せない**ことを確認してください。

```bash
gh pr merge --squash
# => Pull request is not mergeable: the base branch policy prohibits the merge.
```

**なぜ**: `required_status_checks` により、CI 通過はマージの前提条件です。
「レビューで気をつける」ではなく「通らないと物理的に入らない」が正解です。
確認できたらクローズします。

```bash
gh pr close feature/break-test --delete-branch
```

<details>
<summary>▶ ペア/研修モードの場合: 承認なしマージも試す</summary>

CI がすべて通った PR で、承認が付く前に `gh pr merge --squash` を実行して
ください。レビュー承認数の不足で拒否されます。solo モードでは承認数を
0 に緩和しているため、この体験はできません。

</details>

## 2.6 この章のまとめ

| 試したこと | 止めたもの | 層 |
|---|---|---|
| main へ直 push | Ruleset: pull_request 必須 | Git サーバー |
| force push | Ruleset: non_fast_forward | Git サーバー |
| 雑な PR タイトル | CI: pr-title チェック | CI |
| merge commit | リポジトリ設定 (選択肢が存在しない) | 設定 |
| 壊れたコードのマージ | Ruleset: required_status_checks | Git サーバー × CI |

ポイントは、どれも「気をつけましょう」という運用ルールではなく、
**破れない仕組み**として実装されていることです。レビューは設計や仕様の議論に
集中でき、形式的なチェックは機械に任せられます。

タグの保護 (削除・付け替え禁止) はまだ試せません — タグがないからです。
第3章でリリースした後、第5章で壊しに行きます。

---

← [第1章 フィーチャー開発](./01-feature-flow.md) | [第3章 v1.0 リリース →](./03-release.md)
