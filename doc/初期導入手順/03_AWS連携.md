# AWSで本番公開する

## 1. **AWSアカウント作成**（法人名はローマ字で登録）
## 2. **Route 53でドメイン取得**（例：`dolcos-calc.com`）
### 🪜 ステップ1：Route 53 を開く

AWSコンソールで
検索バーに `Route 53` と入力 → 開く

---

### 🪜 ステップ2：「ドメインを登録」へ進む

左メニュー → 「**ドメインを登録**」
→ 「**ドメインを登録する**」ボタンをクリック

---

### 🪜 ステップ3：検索

検索欄に

```
dolcos-calc
```

と入力して検索。

すると候補一覧に：

| ドメイン            | 年額         | 備考               |
| --------------- | ---------- | ---------------- |
| dolcos-calc.com | $15.00 USD | ✅ 空いていれば「利用可能」表示 |

---

### 🪜 ステップ4：「カートに追加」→「次へ」

---

### 🪜 ステップ5：登録者情報を入力

| 項目           | 設定例                     |
| ------------ | ----------------------- |
| 登録者タイプ       | Business（法人）            |
| Organization | Office UTQ Inc.         |
| Contact name | Koji Sakamoto           |
| Address      | 6-33-13 Tsuboi, Chuo-ku |
| City         | Kumamoto-shi            |
| State        | Kumamoto                |
| Country      | Japan                   |
| Postal Code  | 860-0863                |
| Phone        | +81-96-xxxx-xxxx        |
| Email        | 普段確認できる業務用メール           |

---

### 🪜 ステップ6：オプション設定

| 項目            | 設定          |
| ------------- | ----------- |
| 自動更新          | ✅ 有効にする（推奨） |
| WHOISプライバシー保護 | ✅ 有効にする（推奨） |

（※ AWSが「Amazon Registrar」経由でWHOIS情報を隠してくれます）

---

### 🪜 ステップ7：支払いと登録完了

* クレジットカードを選択
* 「注文を確定」ボタンをクリック

するとメールが届きます👇

> “Your domain registration for dolcos-calc.com has been successfully submitted.”

⏳ 数分〜1時間で登録完了。

---

### 🪜 ステップ8：DNS（ホストゾーン）自動生成

登録完了後に Route 53 の「ホストゾーン」一覧を見ると
`dolcos-calc.com` のゾーンが自動でできています ✅

これが後で

* EC2 や S3 に紐づける
* HTTPS化 (Let’s Encrypt / ACM)
  ための設定場所になります。

---

💡補足：

* 請求はAWSの月次請求に合算されます（ドル建て）
* 1年単位の自動更新（取り消しも可能）

---

## 3. **EC2インスタンス作成**
やること（AWSコンソール内）：

1. サービス検索 → 「EC2」
2. 「インスタンスを起動」クリック
3. 以下のように設定👇

| 項目        | 設定例                             | 解説                                    |
| --------- | ------------------------------- | ------------------------------------- |
| 名前        | `dolcos-calc-server`            | |
| OS        | Amazon Linux 2023               | |
| インスタンスタイプ | t3.micro（無料枠）                   | |
| キーペア      | 新規作成（例：`dolcos-key`）            | dolcos-key.pemをローカルPCに保存 |
| ストレージ     | 20GB でOK                        | |
| **VPC**            | `vpc-04cdea686121558d9 (デフォルト)` | そのままでOK（AWSが用意している基本ネットワーク）           |
| **サブネット**          | 指定なし（または自動選択）                   | デフォルトVPC内のどこでもOK。後でElastic IPで固定可。    |
| **アベイラビリティゾーン**    | 指定なし                            | 自動で選ばせてOK（`ap-northeast-1a` などが選ばれます） |
| **パブリックIPの自動割り当て** | ✅ **有効化**（重要）                   | これをONにしないと、外部からアクセスできません！             |
| **セキュリティグループ**     | 🔧 **新規作成** して以下ルールを追加          | SSH(22)だけでなくHTTP/HTTPSを許可します          |

起動後、「パブリックIPv4アドレス」を控えておきます
（例：`18.183.45.22`）

これが後で `dolcos-calc.com` の Aレコードに登録するIPです。

---
### 🔒 セキュリティグループ設定（重要）

#### ① 「セキュリティグループを作成」 を選択

新しいグループ名を入れましょう：

| フィールド | 設定例                                       |
| ----- | ----------------------------------------- |
| 名前    | `dolcos-calc-sg`                          |
| 説明    | Security group for Dolcos Calc web server |

---

#### ② インバウンドルールを設定します

| タイプ   | プロトコル | ポート範囲 | ソース                   | 説明                |
| ----- | ----- | ----- | --------------------- | ----------------- |
| SSH   | TCP   | 22    | マイIP（推奨）or 0.0.0.0/0 | SSHログイン用（後で制限可）   |
| HTTP  | TCP   | 80    | 0.0.0.0/0             | Webアクセス（ブラウザで確認用） |
| HTTPS | TCP   | 443   | 0.0.0.0/0             | SSL化後に必要          |
| カスタム TCP | TCP   | 3000   | マイIP             | Nginxをまだ立てないので、Rails を 3000 で直接見るため<br>後で Nginx + HTTPS(443) に切り替えたら 3000 は閉じます。          |

👉 一時的には全世界(0.0.0.0/0)で構いませんが、
本運用時はSSHだけ自分の固定IPに制限するのがおすすめです。

---

#### ③ アウトバウンドルール

デフォルトの「全てのトラフィックを許可 (0.0.0.0/0)」でOKです。
（外部にパッケージをダウンロードする必要があるため）

---

### 💾 ストレージ設定（容量）

| フィールド | 推奨値                             |
| ----- | ------------------------------- |
| サイズ   | **20 GiB**（最初の8GiBだとすぐ足りなくなります） |
| タイプ   | gp3 のままでOK                      |
| 暗号化   | なしでOK（後で切り替え可）                  |

---
## 4. **EC2への初回接続**

1. PowerShellでSSHキーを利用して接続

   ```powershell
   ssh -i C:\Users\xxxxx\.ssh\dolcos-key.pem ec2-user@<IP>
   ```
2. `git`, `docker`, `docker-compose` のインストール

   ```bash
   sudo dnf install -y git docker
   sudo systemctl enable --now docker
   sudo usermod -aG docker ec2-user
   exit  # ← 一度ログアウトして再ログイン（権限反映）
   ```
3. 動作確認

   ```bash
   docker run --rm hello-world
   ```

---

## 5. **システム安定化（Swapの設定）**

1. 一時Swapを作成（ビルド用）

   ```bash
   sudo fallocate -l 2G /swapfile
   sudo chmod 600 /swapfile
   sudo mkswap /swapfile
   sudo swapon /swapfile
   free -h
   ```
2. 永続化（再起動しても有効）

   ```bash
   echo '/swapfile swap swap defaults 0 0' | sudo tee -a /etc/fstab
   ```

---

## 6. **アプリの配置**

1. リポジトリを clone

   ```bash
   git clone https://github.com/xxxxx/dolcos_calc.git dolcos-calc
   cd dolcos-calc
   ```

   （2回目以降は `git pull origin main`）

2. `.env` を作成

   ```bash
   cat > .env <<EOF
   RAILS_ENV=production
   POSTGRES_USER=postgres
   POSTGRES_PASSWORD=password
   POSTGRES_DB=dolcos_production
   SECRET_KEY_BASE=$(openssl rand -hex 64)<長いhex>
   DATABASE_URL=postgres://postgres:password@db:5432/dolcos_production
   RAILS_SERVE_STATIC_FILES=true
   EOF
   ```

---

## 7. **Docker設定**

本番用に設定ファイルを作成する。

1. **`Dockerfile.prod`** を作成（Rails + Node + Sass + Bootstrap対応）  

   `app\Dockerfile.prod`
   ```dockerfile
    FROM ruby:3.3-slim

    ENV LANG=C.UTF-8 TZ=Asia/Tokyo \
        BUNDLE_JOBS=2 BUNDLE_RETRY=3 \
        RAILS_ENV=production RACK_ENV=production \
        RAILS_LOG_TO_STDOUT=true

    RUN apt-get update -y && apt-get install -y --no-install-recommends \
        build-essential libpq-dev pkg-config git curl ca-certificates \
        libyaml-dev libssl-dev zlib1g-dev \
        nodejs npm \
      && rm -rf /var/lib/apt/lists/*

    WORKDIR /app

    # 先にGemを入れてキャッシュを効かせる
    COPY Gemfile Gemfile.lock ./
    RUN gem install bundler -N \
    && bundle config set without 'development test' \
    && bundle config set force_ruby_platform true \
    && bundle install -j2

    # ← Node 依存（package.json）があるなら先に入れてキャッシュを効かせる
    #    * package-lock.json があるなら一緒にCOPYして npm ci を使うのがベスト
    COPY package.json package-lock.json* ./
    RUN test -f package.json && (npm ci || npm install) || true

    RUN npm install --no-audit --no-fund bootstrap@5 @popperjs/core

    # node_modules を Sass のロードパスに通す
    ENV SASS_PATH=node_modules

    # アプリ本体
    COPY . .

    # ビルド時はダミーの SECRET_KEY_BASE を渡す（実行時は .env の本物を使用）
    RUN SECRET_KEY_BASE=dummy bundle exec rails assets:precompile

    EXPOSE 3000
    CMD ["bash","-lc","bundle exec rails db:prepare && bundle exec rails server -b 0.0.0.0 -p 3000"]
   ```
2. **`docker-compose.prod.yml`** を作成

   * `app`（Rails）
   * `db`（PostgreSQL）  

    `docker-compose.prod.yml`
   ```yaml
    version: "3.9"

    services:
      db:
        image: postgres:16
        environment:
          POSTGRES_USER: ${POSTGRES_USER}
          POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
          POSTGRES_DB: ${POSTGRES_DB}
        volumes:
          - db-data:/var/lib/postgresql/data
        healthcheck:
          test: ["CMD-SHELL", "pg_isready -U $$POSTGRES_USER -d $$POSTGRES_DB"]
          interval: 5s
          timeout: 5s
          retries: 20
        restart: unless-stopped

      app:
        build:
          context: .
          dockerfile: app/Dockerfile.prod
        env_file: .env                      # ← EC2 に作った .env を利用
        depends_on:
          db:
            condition: service_healthy
        ports:
          - "3000:3000"
        command: bash -lc "bundle exec rails db:migrate && bundle exec rails server -b 0.0.0.0 -p 3000"
        restart: unless-stopped

    volumes:
      db-data:
   ```
---

## 8. **ビルドと起動**

```bash
docker-compose -f docker-compose.prod.yml build --no-cache --progress=plain
docker-compose -f docker-compose.prod.yml up -d
docker-compose -f docker-compose.prod.yml logs -f app
```

✅ `Listening on 0.0.0.0:3000` が出たら成功。

---

## 9. **ブラウザ確認**

* `http://<EC2のIP>:3000` → トップページ表示

---

## 🔒 8. セキュリティ・メンテナンス

* `.env` に含まれる秘密値は外部に出さない（S3 / Parameter Storeなどで管理予定）
* **SSHポート (22)** は “自分のIPだけ” 許可
* 余裕が出たら：

  * Nginx＋Let's Encrypt で **HTTPS化**
  * `docker-compose.prod.yml` に `nginx` サービスを追加してポート80→3000リバースプロキシ

---

# 🧾 **まとめ**

| ステップ             | 内容                      | 状況        |
| ---------------- | ----------------------- | --------- |
| ① AWS環境構築        | EC2 + Route 53          | ✅ 完了      |
| ② SSH接続・Docker準備 | docker, git, compose    | ✅ 完了      |
| ③ スワップ設定         | 永続化済み                   | ✅ 完了      |
| ④ ソース配置          | GitHubからclone           | ✅ 完了      |
| ⑤ Docker設定       | prodファイル分離              | ✅ 完了      |
| ⑥ ビルド＆起動         | 成功、Rails稼働              | ✅ 完了      |
| ⑦ 静的配信・CSS適用     | dart-sass + bootstrap対応 | ✅ 完了      |
| ⑧ ドメイン連携         | Route 53にAレコード設定        | ⚙️ 実施予定   |
| ⑨ HTTPS化         | nginx + certbot構成       | 🔜 次のステップ |

---

💡 **次にやると良いこと**

1. Route 53で Aレコードを追加（`dolcos-calc.com` → EC2 IP）
2. Nginxリバースプロキシを導入して、`http://dolcos-calc.com` → Rails3000
3. certbot（Let’s Encrypt）で HTTPS 化
4. CloudWatch Logs か EBS Snapshot を設定して運用安定化

---
