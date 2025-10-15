# GitHub とつなぐ最短手順
Windows（PowerShell）前提で、HTTPS と SSH の2パターンを用意しました。

---

# 0) まずリポジトリの中に移動

```powershell
cd C:\dev\dolcos_calc
```

---

# 1) 追跡対象を整える（.gitignore / .gitattributes）

**改行事故回避**と**余計な生成物除外**を追加すると吉。

## `.gitattributes`

```gitattributes
* text=auto eol=lf
*.bat eol=crlf
*.ps1  eol=crlf
```

## `.gitignore`（必要なら追記）

```gitignore
# すでに多くは入っている想定。足りなければ以下を追記
/node_modules
/app/assets/builds
/tmp
/log
/storage
/.env
```

> `app/assets/builds` は cssbundling-rails の生成物なので **コミットしない**運用が無難です（記事でもそうしていました）。

---

# 2) 初回コミット

```powershell
git init -b main
#warning: re-init: ...のメッセージが出た場合は、すでにmainになっているので、無視しても問題なし
git add .
#warning: in the working copy of ...のメッセージが出た場合は、次のコミット/チェックアウトで改行コードLFに。無視しても問題なし
git commit -m "chore: bootstrap Rails 8 + Docker + Postgres dev env"
```

> もし Git のユーザー名/メール未設定なら先に：

```powershell
git config --global user.name  "Your Name"
git config --global user.email "you@example.com"
```

---

# 3) GitHub 側に空のリポジトリを作る

## A) GitHub CLI（`gh`）がある場合（超速）

```powershell
gh repo create dolcos_calc --public --source . --remote origin --push
```

## B) ブラウザで作る場合

1. GitHubで新規リポジトリ作成（例：`dolcos_calc` / public or private）
2. 表示された「…or push an existing repository from the command line」を実行：

### HTTPS で push

```powershell
git remote add origin https://github.com/<your-account>/dolcos_calc.git
git push -u origin main
```

### SSH で push（おすすめ）

1. SSH鍵を作って GitHub に登録（未設定の場合）

```powershell
# 例: ed25519
ssh-keygen -t ed25519 -C "you@example.com"
# -> C:\Users\<you>\.ssh\id_ed25519.pub を GitHubの Settings > SSH keys に登録
```

2. リモート設定＆push

```powershell
git remote add origin git@github.com:<your-account>/dolcos_calc.git
git push -u origin main
```

---

# 4) 以後の定番ワークフロー

```powershell
git switch -c feature/xxx
# 作業…
git add -A
git commit -m "feat: xxx"
git push -u origin feature/xxx
# GitHub上で PR を作成 → マージ
```

---

# 5) 役立つオプション（任意）

* 大きなファイル（画像・設計資料）を入れるなら **Git LFS** も検討：

  ```powershell
  git lfs install
  git lfs track "*.png"
  git add .gitattributes
  ```
* GitHub Actions（Rails CI）
  Rails 8 の `rails new` で `.github/workflows/ci.yml` が既に生成されているはず。
  CI でPostgreSQLを使う場合は、Workflow内の DB サービス/環境変数が意図通りかだけ確認。

---

# よくあるハマり & 一言で解決

* **「改行で差分だらけ」** → `.gitattributes` の `* text=auto eol=lf` を入れて、いったん `git rm --cached -r .; git reset --hard` で差分整理。
* **pushできない（認証エラー）** → HTTPS の場合は **PAT**（パスワードではなくトークン）を使う / SSH の場合は **鍵の登録**と `ssh -T git@github.com` で疎通確認。
* **巨大生成物が混ざった** → `.gitignore` を直して `git rm --cached <path>` で履歴から外す。

---

必要なら、**GitHub Actionsでの自動ビルド/テスト**のテンプレも用意します。PR 時に `bundle install → db:prepare → rails test` を走らせるだけならすぐ書けますよ。
