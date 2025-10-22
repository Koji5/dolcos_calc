# GitHub とつなぐ最短手順
Windows（PowerShell）・GitHub Desktop前提。

---

## 0) まずリポジトリの中に移動

```powershell
cd C:\dev\dolcos_calc
```

---

## 1) 追跡対象を整える（.gitignore / .gitattributes）

**改行事故回避**と**余計な生成物除外**を追加すると吉。

### `.gitattributes`

```gitattributes
* text=auto eol=lf
*.bat eol=crlf
*.ps1  eol=crlf
```

### `.gitignore`（必要なら追記）

```gitignore
# すでに多くは入っている想定。足りなければ以下を追記
/app/assets/builds/
!/app/assets/builds/.keep
/node_modules/
/log/*
!/log/.keep
/tmp/*
!/tmp/.keep
/storage/*
!/storage/.keep
/config/master.key
```

> `app/assets/builds` は cssbundling-rails の生成物なので **コミットしない**運用が無難です。

---

## 2) 初回コミット

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

## 3) **GitHub Desktop を起動 → Add an Existing Repository**

   * **File → Add local repository…**
   * Path に `C:\dev\dolcos_calc` を指定 → **Add repository**

---

## 4) GitHub 側にリポジトリを作成 → **Publish to GitHub**

   * 右上 **Publish repository**
   * Repository name（例：`dolcos_calc`）
   * **Visibility**: Public / Private を選択
   * “Keep this code private” は Private のときだけチェック
   * **Publish Repository** を押す
     （最初の一回だけ GitHub アカウントでサインインが必要）  

**確認**

   * Desktop の “View on GitHub” を押して、ブラウザでリポジトリが見えればOK
   * 以後は Desktop で **Commit → Push**、PR も Desktop から作成可能
---

## 5) GitHub Actionsでの自動ビルド/テスト

### 以下を追加・修正

`.github\workflows\ci.yml`

```yaml
name: CI

on:
  pull_request:
  push:
    branches: [ main ]

jobs:
  scan_ruby:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Make bin scripts executable (Windows-friendly)
        run: git ls-files -z bin/* | xargs -0 chmod +x
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: .ruby-version
          bundler-cache: true
      - name: Brakeman (Rails security scan)
        run: bundle exec brakeman --no-pager

  scan_js:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Make bin scripts executable (Windows-friendly)
        run: git ls-files -z bin/* | xargs -0 chmod +x
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: .ruby-version
          bundler-cache: true
      - name: Importmap audit (JS deps)
        run: bin/importmap audit

  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Make bin scripts executable (Windows-friendly)
        run: git ls-files -z bin/* | xargs -0 chmod +x
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: .ruby-version
          bundler-cache: true
      - name: Rubocop
        run: bundle exec rubocop -f github

  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        ports: ["5432:5432"]
        env:
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: postgres
        options: >-
          --health-cmd="pg_isready -U postgres -h 127.0.0.1"
          --health-interval=10s
          --health-timeout=5s
          --health-retries=5

    env:
      RAILS_ENV: test
      DATABASE_URL: postgres://postgres:postgres@127.0.0.1:5432/dolcos_calc_test

    steps:
      - uses: actions/checkout@v4

      - name: Make bin scripts executable (Windows-friendly)
        run: git ls-files -z bin/* | xargs -0 chmod +x

      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: .ruby-version
          bundler-cache: true

      - name: Install system deps for pg/psych
        run: |
          sudo apt-get update -y
          sudo apt-get install -y --no-install-recommends libpq-dev pkg-config libyaml-dev

      # Node をセットアップ & npm 依存を入れる（bootstrap が必要）
      - name: Set up Node (for npm/sass)
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'

      - name: Install npm deps
        run: |
          if [ -f package.json ]; then
            npm ci || npm install
          fi
          mkdir -p app/assets/builds

      - name: Build CSS (bootstrap & icons)
        run: |
          if [ -f package.json ]; then
            npm run build:css --if-present
          fi

      - name: Make node_modules visible to Dart Sass
        run: echo "SASS_PATH=node_modules" >> $GITHUB_ENV

      - name: Prepare DB
        run: bundle exec rails db:prepare

      - name: Run tests (Minitest)
        run: bundle exec rails test
```

`.github\dependabot.yml`

```yaml
version: 2
updates:
  # Ruby (Bundler)
  - package-ecosystem: bundler
    directory: "/"
    schedule:
      interval: weekly        # dailyだとPRが多すぎる場合はweekly推奨
      timezone: "Asia/Tokyo"
    open-pull-requests-limit: 10
    commit-message:
      prefix: "deps(bundler)"

  # GitHub Actions
  - package-ecosystem: github-actions
    directory: "/"
    schedule:
      interval: weekly
      timezone: "Asia/Tokyo"
    open-pull-requests-limit: 10
    commit-message:
      prefix: "deps(actions)"

  # npm（sass / bootstrap など）
  - package-ecosystem: npm
    directory: "/"
    schedule:
      interval: weekly
      timezone: "Asia/Tokyo"
    open-pull-requests-limit: 10
    commit-message:
      prefix: "deps(npm)"
    # メジャー更新をまとめたい/一旦避けたい場合の例（任意）
    # ignore:
    #   - dependency-name: "*"
    #     update-types: ["version-update:semver-major"]
```

`bin\dev`

```sh
#!/usr/bin/env sh
set -e
export SASS_PATH=node_modules:$SASS_PATH
# gem の bin を PATH に通す（念のため）
export PATH="/usr/local/bundle/bin:$PATH"

# Foreman をフルパスで起動（PATH問題を回避）
exec /usr/local/bundle/bin/foreman start -f Procfile.dev
```

`Procfile.dev`

```procfile
web: bin/rails server -b 0.0.0.0 -p 3000
css: npm run watch:css
```

`config\initializers\dartsass.rb`

```ruby
# config/initializers/dartsass.rb
Rails.application.configure do
  # ビルド定義（既にあればそのままでOK）
  config.dartsass.builds = {
    "application.scss" => "app/assets/builds/application.css"
  }
end
```

# コミットメッセージ例
  
例：`git commit -m "chore: bootstrap Rails 8 + Docker + Postgres dev env"`  
**「Conventional Commits（慣例的な書き方）」** に沿った例で、意味はこうです。

* **`chore:`**
  機能追加やバグ修正ではない“雑用”系の変更（設定追加、ツール導入、依存関係更新など）を示すラベル。
* **`bootstrap`**
  「初期セットアップする／土台を立ち上げる」という動詞。プロジェクトの骨格を作った、の意。
* **`Rails 8 + Docker + Postgres dev env`**
  何をブートストラップしたかを具体化：
  「Rails 8 と Docker、PostgreSQL の開発環境（dev env）を整えた」。

つまり全体の意図は

> **「機能ではなく環境構築のコミット。Rails8×Docker×Postgres の開発環境を初期セットアップした」**
> という意味です。

### 似た表現の例

* `chore: initialize Rails 8 app with Docker & Postgres`
* `build: add Dockerfiles and compose for Rails + PG`
* `ci: add GitHub Actions Rails test workflow`（CI設定なら `ci:`）
* `docs: add setup guide`（ドキュメントなら `docs:`）

### 使い分けのコツ（Conventional Commits）

* **feat:** 機能追加
* **fix:** バグ修正
* **chore:** 付帯作業（設定・ツール・依存更新など）
* **build:** ビルド／依存に関わる変更
* **ci:** CI設定
* **docs:** ドキュメント
* **refactor / perf / test:** それぞれ意図に応じて

最初のコミットは機能ではなく“環境の土台”なので、`chore` や `build` がよく使われます。
