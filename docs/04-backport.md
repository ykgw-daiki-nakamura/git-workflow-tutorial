# 第4章 upstream first とバックポート

シナリオ: v1.0.0 が本番稼働中、main では次バージョンの開発が進んでいます
(第3章の最後で PR を 1 つマージしていれば、すでに main と release/v1.0 は
分岐しています)。ここで本番のバグが見つかりました。

```mermaid
gitGraph
    commit id: "feat: 環境名表示"
    branch release/v1.0
    commit id: " " tag: "v1.0.0"
    checkout main
    commit id: "feat: 次の開発"
    commit id: "fix: バグ修正" type: HIGHLIGHT
    checkout release/v1.0
    cherry-pick id: "fix: バグ修正" tag: "v1.0.1-rc.1"
```

原則は **upstream first**: 修正はまず main に入れ、それをリリースブランチへ
cherry-pick します。逆順 (リリースブランチだけ直す) にすると、次のリリースで
同じバグが再発する事故が起きます。

## 4.1 バグを発見する

検品票をよく見ると、チェック行に **「version 一致」が 2 つ並んでいます**。

```
✓ version 一致    ✓ version 一致
```

2 行目が判定しているのは `git_sha` の一致 (`ok={shaMatch}`) なのに、ラベルだけが
コピペのまま `version 一致` になっているのが原因です。判定そのものは正しく
動いていますが、**票の読み手には git_sha が検品されたことが伝わりません**。
出荷検品票としては十分に「バグ」です。

`frontend/src/App.tsx`:

```tsx
      <section className="checks">
        <Check label="version 一致" ok={versionMatch} pending={!loaded} />
        <Check label="version 一致" ok={shaMatch} pending={!loaded} />   {/* ← "git_sha 一致" が正 */}
      </section>
```

バグ報告の Issue を作ります。

```bash
gh issue create \
  --title "検品票のチェック行に「version 一致」が 2 つ表示される" \
  --body "2 行目は git_sha を判定しているので「git_sha 一致」と表示するのが正。v1.0 系にもバックポートが必要"
```

## 4.2 まず main を直す (upstream first)

第1章とまったく同じ日常フローです。

```bash
git switch main && git pull
git switch -c fix/3-check-label
# App.tsx の 2 つ目の Check のラベルを "git_sha 一致" に修正
git add -A && git commit -m "チェック行のラベル修正"
git push -u origin fix/3-check-label
gh pr create --title "fix: git_sha チェックのラベルが version 一致になっている" --body "Closes #3"
gh pr checks --watch
gh pr merge --squash
```

merge 後、**squash されたコミットの SHA** を控えます。

```bash
git switch main && git pull
git log --oneline -1
# 例: 9f8e7d6 fix: git_sha チェックのラベルが version 一致になっている (#4)
```

dev の URL を開くと、チェック行が `✓ version 一致  ✓ git_sha 一致` になっています。
staging / production はまだ `version 一致` が 2 つ並んだままです — この差が、
これからバックポートするものです。

## 4.3 release/v1.0 へ cherry-pick する

リリースブランチも Ruleset で保護されているため、直 push はできません。
バックポートも **PR 経由**です。

```bash
git switch release/v1.0 && git pull
git switch -c backport/v1.0-check-label
git cherry-pick -x 9f8e7d6      # ← 4.2 で控えた SHA
git push -u origin backport/v1.0-check-label
```

> [!TIP]
> `-x` を付けると、コミットメッセージに `(cherry picked from commit ...)` が
> 追記され、main のどのコミット由来かの追跡が残ります。

バックポート用テンプレートを使って、**base を release/v1.0 にした** PR を作ります。

```bash
gh pr create \
  --base release/v1.0 \
  --title "fix: git_sha チェックのラベルが version 一致になっている (backport v1.0)" \
  --body "$(sed -e 's/#<!--.*-->/#4/' .github/PULL_REQUEST_TEMPLATE/backport.md)"
```

(UI で作る場合は PR 作成 URL の末尾に `?template=backport.md` を付けると
テンプレートが読み込まれます。base ブランチの選択を忘れずに)

CI 通過後、squash merge します。

```bash
gh pr merge --squash
```

<details>
<summary>▶ ペア/研修モードの場合</summary>

バックポート PR のレビュー観点は通常 PR と異なります。「修正内容が正しいか」は
main 側 PR で審査済みなので、ここでは **(1) 元 PR と差分が一致しているか、
(2) 余計な変更が紛れ込んでいないか、(3) 対象ブランチが正しいか** だけを
確認して Approve してください。

</details>

## 4.4 v1.0.1 をリリースする

第3章と同じ手順の 2 周目です。今度はガイドなしでどうぞ。

```bash
git switch release/v1.0 && git pull
git tag v1.0.1-rc.1 && git push origin v1.0.1-rc.1
# → staging で検品
git tag v1.0.1 && git push origin v1.0.1
# → 承認 → production
```

RC が staging に出たら、**staging と production を並べて開いてください**。

| | チェック行 | version |
| --- | --- | --- |
| staging (v1.0.1) | `✓ version 一致  ✓ git_sha 一致` | 1.0.1 |
| production (v1.0.0) | `✓ version 一致  ✓ version 一致` | 1.0.0 |

修正が staging にだけ届いている状態が見えます。GA タグを打って承認すると、
production 側のチェック行も `git_sha 一致` に変わります。これがバックポートの
着地確認です。

## 4.5 チェックポイント

- [ ] main に fix が入って dev に反映された (チェック行のラベルは次期バージョンでも直っている)
- [ ] `release/v1.0` には cherry-pick の 1 コミットだけが追加された
      (`git log --oneline main..release/v1.0` で確認 — 次期開発のコミットが**混ざっていない**)
- [ ] production の検品票が `version: 1.0.1` になり、チェック行が
      `✓ version 一致  ✓ git_sha 一致` に変わった
- [ ] main 側の開発内容 (第3章末の PR) は production に**出ていない**

最後の 2 点が、リリースブランチ方式の価値そのものです:
**修正だけを、開発中の変更を巻き込まずに出荷できました**。

---

← [第3章 v1.0 リリース](./03-release.md) | [第5章 発展演習 →](./05-advanced.md)
