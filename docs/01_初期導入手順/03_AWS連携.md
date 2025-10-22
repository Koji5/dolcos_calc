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
   # 1️⃣ 基本ツールの導入
   sudo dnf install -y git docker
   # 2️⃣ Dockerを起動・自動起動
   sudo systemctl enable --now docker
   # 3️⃣ ec2-user を docker グループに追加（sudo不要化）
   sudo usermod -aG docker ec2-user
   # 4️⃣ Compose v2 バイナリを手動配置（AL2023標準パス）
   sudo mkdir -p /usr/libexec/docker/cli-plugins/
   VER=2.27.0    # ← 最新版に更新可
   sudo curl -SL "https://github.com/docker/compose/releases/download/v${VER}/docker-compose-linux-$(uname -m)" -o /usr/libexec/docker/cli-plugins/docker-compose
   sudo chmod +x /usr/libexec/docker/cli-plugins/docker-compose
   # 5️⃣ 動作確認
   docker --version
   docker compose version
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

## 6. **Docker設定**

本番用に設定ファイルを作成する。

1. **`Dockerfile.prod`** を作成（Rails + Node + Sass + Bootstrap対応）  

   `app\Dockerfile.prod`
   ```dockerfile
   # syntax=docker/dockerfile:1.7
   FROM public.ecr.aws/docker/library/ruby:3.3-slim

   ENV LANG=C.UTF-8 TZ=Asia/Tokyo \
       BUNDLE_JOBS=2 BUNDLE_RETRY=3 \
       RAILS_ENV=production RACK_ENV=production \
       RAILS_LOG_TO_STDOUT=true

   RUN --mount=type=cache,target=/var/cache/apt \
       --mount=type=cache,target=/var/lib/apt/lists \
          apt-get update -y \
    && apt-get install -y --no-install-recommends \
         build-essential libpq-dev pkg-config git curl ca-certificates \
         libyaml-dev libssl-dev zlib1g-dev \
         nodejs npm \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/* /tmp/*

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

   # node_modules を Sass のロードパスに通す
   ENV SASS_PATH=node_modules

   # アプリ本体
   COPY . .

   # CSSをビルドして、bootstrap-icons の CSS/フォントを builds 配下へコピー
   RUN npm run build:css

   # ビルド時はダミーの SECRET_KEY_BASE を渡す（実行時は .env の本物を使用）
   RUN --mount=type=secret,id=rails_master_key \
       --mount=type=secret,id=db_url \
       sh -lc 'set -eu; \
         RAILS_MASTER_KEY="$(tr -d "\r\n" </run/secrets/rails_master_key)"; \
         DATABASE_URL=postgres://dummy:dummy@localhost:5432/dummy; \
         export RAILS_MASTER_KEY DATABASE_URL; \
         export SECRET_KEY_BASE=dummy; \
         bundle exec rails assets:precompile'

   EXPOSE 3000
   CMD ["bash","-lc","bundle exec rails db:prepare && bundle exec rails server -b 0.0.0.0 -p 3000"]
   ```
2. **`docker-compose.prod.yml`** を作成

   * `app`（Rails）
   * `db`（PostgreSQL）→ のちにS3に連携するとき削除する  

    `docker-compose.prod.yml`
   ```yaml
    services:
      db:
        image: postgres:16
        environment:
          POSTGRES_USER: ${POSTGRES_USER:-}
          POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-}
          POSTGRES_DB: ${POSTGRES_DB:-}
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
          secrets:
            - rails_master_key
        env_file: .env                      # ← EC2 に作った .env を利用
        depends_on:
          db:
            condition: service_healthy
        ports:
          - "127.0.0.1:3000:3000"
        command: bash -lc "bundle exec rails db:migrate && bundle exec rails server -b 0.0.0.0 -p 3000"
        restart: unless-stopped

    secrets:
      rails_master_key:
        file: ./config/credentials/production.key

    volumes:
      db-data:
   ```

コミットを忘れずに！  

---

## 7. **アプリの配置**

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
   SECRET_KEY_BASE=$(openssl rand -hex 64)
   DATABASE_URL=postgres://postgres:password@db:5432/dolcos_production
   RAILS_SERVE_STATIC_FILES=true
   EOF
   ```

3. `credentials` を生成

   ```bash
   # production.key を手動生成
   mkdir -p config/credentials
   umask 177
   printf "%s" "$(openssl rand -hex 16)" > config/credentials/production.key
   chmod 600 config/credentials/production.key
   ## 32 と出ればOK
   wc -c config/credentials/production.key

   # その鍵で production.yml.enc を新規作成
   ## ホストで環境変数に読み込み、exec で渡す
   RAILS_MASTER_KEY=$(tr -d '\n' < config/credentials/production.key)
   docker compose -f docker-compose.prod.yml exec -e RAILS_MASTER_KEY="$RAILS_MASTER_KEY" -e EDITOR=true app bash -lc 'bundle exec rails credentials:edit --environment production'
   ## コンテナ → ホストへ .enc をコピー
   mkdir -p ./config/credentials
   docker compose -f docker-compose.prod.yml cp app:/app/config/credentials/production.yml.enc ./config/credentials/production.yml.enc
   ```

---

## 8. **ビルドと起動**

```bash
DOCKER_BUILDKIT=1 docker compose -f docker-compose.prod.yml build --no-cache app
docker-compose -f docker-compose.prod.yml up -d
docker-compose -f docker-compose.prod.yml logs -f app
```

✅ `Listening on 0.0.0.0:3000` が出たら成功。  
✅ `http://<EC2のIP>:3000` → トップページ表示

---

## 9. **ドメイン連携**
  Route 53にAレコードを設定します。
### **Step1  Elastic IP（固定IP）割り当て**

* ***① Elastic IPを新規作成する***

  1. AWS コンソールにログイン
  2. 上部メニューの「サービス」→ **EC2** を選択
  3. 左メニューの「**ネットワーク＆セキュリティ**」→ **Elastic IP** をクリック
  4. 「**Elastic IP アドレスの割り当て**」をクリック
  5. 内容を確認して「**割り当て**」ボタンを押す  
  → 新しい固定IP（例：`13.112.xxx.xxx`）が発行されます。

* ***② Elastic IP を EC2 インスタンスに関連付ける***
  1. 発行された Elastic IP の一覧で、チェックボックスを入れる
  2. 「**アクション**」→「**Elastic IP アドレスを関連付け**」を選択
  3. 「**リソースタイプ**」で「インスタンス」を選ぶ
  4. 「インスタンス」欄から、あなたの EC2 インスタンスを選択
  5. 「プライベートIPアドレス」は自動で補完されるので、そのまま「**関連付け**」ボタンを押す

* ***③ 確認***
  1. EC2 → 「インスタンス」画面を開く
  2. 対象インスタンスをクリック
  3. 下部の「詳細」タブで「**Elastic IP**」が表示されているか確認

* ***④ 旧パブリックIPの扱い***
  1. 旧パブリックIPは自動的に無効になります。  
  1. 以後、**新しい Elastic IP**（例：`13.112.xxx.xxx`）が固定の公開アドレスになります。

### **Step2 Aレコード設定**
* **🪜 手順①：前提確認**

  まず、次の3点を確認しておきましょう。

  | 項目                | 内容                                                                                 |
  | ----------------- | ---------------------------------------------------------------------------------- |
  | ✅ ドメイン            | すでに取得済み（例：`example.com`）                                                           |
  | ✅ EC2 のパブリックIP    | 例：`13.112.xxx.xxx`（Elastic IP なら固定）                                                |
  | ✅ Route 53 ホストゾーン | ドメイン取得元が AWS Route 53 であれば自動で作成済み。外部（お名前.com等）の場合は、Route 53 側で「ホストゾーン」を新規作成する必要あり。 |

* **🪜 手順②：Route 53 ホストゾーンを確認／作成**

  1. AWS コンソール → **Route 53** → **ホストゾーン**
  2. 「example.com」がリストにあるか確認
    　→ なければ「ホストゾーンの作成」ボタンをクリック
    　　- ドメイン名：`example.com`
    　　- タイプ：**パブリックホストゾーン**

  作成後、**ネームサーバ（NS）レコード**が表示されます。

  > 💡 外部レジストラでドメインを取った場合
  > ドメイン管理画面で **ネームサーバを Route53 の NS に変更** してください（反映まで数時間かかることがあります）。


* **🪜 手順③：Aレコードの追加（EC2のIPを指定）**

  1. Route 53 → 対象のホストゾーンを開く
  2. 「レコードの作成」をクリック
  3. 以下のように入力：

    | 項目      | 入力例                                           |
    | ------- | --------------------------------------------- |
    | レコード名   | 空欄（＝ルートドメイン `example.com`）または `www`（必要なら両方作る） |
    | レコードタイプ | **A – IPv4アドレス**                              |
    | 値       | `13.112.xxx.xxx`（EC2のElastic IP）              |
    | TTL     | 300（またはデフォルトのまま）                              |

  > 💡 EC2のIPは必ず **Elastic IP（固定IP）** にしておきましょう。
  > 再起動で変わる「動的パブリックIP」だと DNS が無効になります。

* **🪜 手順④：動作確認**

  ローカルPCから以下を実行：

  ```bash
  ping example.com
  ```

  または

  ```bash
  nslookup example.com
  ```

  結果にEC2のIP（例：13.112.xxx.xxx）が出ればOK。

  その後、ブラウザで
  👉 `http://example.com:3000`
  を開いて、昨日のRails画面が表示されれば成功です。
---
## 10. **HTTPS化**

次の3ステップで **HTTPS化（443番ポート対応）** を行います👇

### **🧭 全体の流れ**
   | ステップ                | 概要                                       | 実行場所                   |
   | ------------------- | ---------------------------------------- | ---------------------- |
   | **① nginx導入**       | 80番・443番を受けて、Railsコンテナ（3000番）にリバースプロキシする | EC2上（ホスト or nginxコンテナ） |
   | **② certbotで証明書発行** | Let's Encrypt で無料SSL証明書を取得し、nginxに適用     | EC2上                   |
   | **③ nginx.conf調整**  | 443番でSSL対応、HTTP(80)→HTTPSリダイレクト          | EC2上                   |
  
  
1. **EC2にnginxを入れる**
   ```bash
   sudo dnf update -y
   sudo dnf install -y nginx
   sudo systemctl enable --now nginx
   sudo systemctl status nginx
   ```
   `http://<EC2のIP>/` にnginxのデフォルトページが出ればOK。

2. **nginxを「3000 → 逆プロキシ」化**

   設定ファイルを作成（ドメイン名は置き換え）：

   ```bash
   sudo tee /etc/nginx/conf.d/dolcos-calc.conf >/dev/null <<'NGINX'
   server {
     listen 80;
     server_name dolcos-calc.com www.dolcos-calc.com;

     # 後でcertbotがこのserverブロックを利用して認証/書換する
     location / {
       proxy_pass http://127.0.0.1:3000;
       proxy_set_header Host              $host;
       proxy_set_header X-Real-IP         $remote_addr;
       proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
       proxy_set_header X-Forwarded-Proto $scheme;
       client_max_body_size 20m;
     }
   }
   NGINX
   ```

   テスト＆反映：

   ```bash
   sudo nginx -t
   sudo systemctl reload nginx
   ```

   > ✅ **Dockerのポート公開は127.0.0.1に限定**しておくと安全  
   > `docker-compose.prod.yml` の `ports` を `["127.0.0.1:3000:3000"]` にしておくと、外部から3000直叩きされません（後述）。

3. **certbot を導入（Let’s Encrypt）**

   ```bash
   sudo dnf install -y certbot python3-certbot-nginx
   ```

   証明書発行（wwwも使うなら両方指定。wwwが不要なら apex のみでOK）：

   ```bash
   # apexのみ
   sudo certbot --nginx -d dolcos-calc.com
   # apex+www（wwwはRoute 53でCNAMEをapexに向けておくと吉）
   # sudo certbot --nginx -d dolcos-calc.com -d www.dolcos-calc.com
   ```

   ```bash
   Saving debug log to /var/log/letsencrypt/letsencrypt.log Enter email address (used for urgent renewal and security notices) (Enter 'c' to cancel):
   # Let’s Encrypt（＝Certbot）が初回のSSL証明書を発行する際、緊急連絡用のメールアドレスを聞いています。
   # 通常はあなたが管理しているメールアドレス（例：sakamoto@example.com）を入力します。
   Please read the Terms of Service at https://letsencrypt.org/documents/LE-SA-v1.4-April-2018.pdf. 
   You must agree in order to register with the ACME server at https://acme-v02.api.letsencrypt.org/directory...
   (Y)es/(N)o:
   # Y を入力してEnter。
   Would you be willing to share your email address with the Electronic Frontier Foundation (EFF) ... ?
   (Y)es/(N)o:
   # N（どちらでもOKですが、通常はN）。
   ```
   → certbotが自動で `listen 443 ssl;` のサーバーブロックと証明書パスを追記します。  
   最後にこのようなメッセージが出れば成功です👇
   ```bash
   Congratulations! You have successfully enabled HTTPS on https://dolcos-calc.com
   ```

   動作確認：

   * `https://dolcos-calc.com/` でトップが出る
   * `http://dolcos-calc.com/` は自動でHTTPSへリダイレクトされる

4. **3000番のインバウンドルールの削除**

   #### 🔥 セキュリティグループ操作手順

   1. AWSコンソール → **EC2 → セキュリティグループ**
   2. 対象インスタンスに紐づく SG を開く
   3. **「インバウンドルール」タブ → 編集**
   4. 以下のルールを削除：  
      ```
      タイプ: カスタムTCP
      ポート範囲: 3000
      ソース: 0.0.0.0/0
      ```
   5. 保存（「ルールを保存」）

   #### ✅ 削除後の動作確認

   * 削除後、外部から：

     ```bash
     curl http://3.104.206.45:3000
     # → タイムアウトまたは接続拒否 (OK)
     ```

   * そしてブラウザで：  
     👉 `https://dolcos-calc.com/`

## 11. **S3との連携**

### ① S3バケットを作る

1. サービス → **S3**
2. 「バケットを作成」

   * バケット名：例）`dolcos-calc-prod-assets`
   * リージョン：EC2と同じ（例：`ap-northeast-1`）
   * **パブリックアクセスはすべてブロックON（推奨）**
   * バージョニングは任意（バックアップしたいならON）
   * 作成

### ② IAMでロール作成

1. サービス → **IAM**
2. 左メニューの「ロール」→「ロールを作成」
3. ユースケース選択 → 「**EC2**」を選び「次へ」
4. 「許可ポリシー」は未選択のまま「次へ」
5. 「名前、確認、および作成」

   * ロール名：`DolcosCalcRole`
   * 説明：`Allow EC2 to access S3 bucket`
   * 「ロールを作成」

### ③ IAMでポリシー作成

1. 左メニューから **「ポリシー」** をクリック
2. 右上の **「ポリシーを作成」** ボタンをクリック  
   → 新しい画面が開きます
3. 「JSON」タブを選択して、以下を貼り付け → 「次へ」

    ```json
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": [
            "s3:ListBucket"
          ],
          "Resource": "arn:aws:s3:::dolcos-calc-prod-assets"
        },
        {
          "Effect": "Allow",
          "Action": [
            "s3:GetObject",
            "s3:PutObject",
            "s3:DeleteObject",
            "s3:PutObjectAcl"
          ],
          "Resource": "arn:aws:s3:::dolcos-calc-prod-assets/*"
        }
      ]
    }
    ```
    `dolcos-calc-prod-assets`は、先ほどS3で作成したバケット名です。
4. 「確認して作成」 → 「ポリシーの作成」

   * ポリシー名：`DolcosCalcS3AccessPolicy`

### ④ 作ったポリシーをロールに付ける

1. 左メニュー → 「ロール」
2. さっき作ったロール `DolcosCalcRole` をクリック
3. 「**許可を追加**」ボタン → 「ポリシーをアタッチ」
4. 検索欄に `DolcosCalcS3AccessPolicy` と入力
5. チェックして「許可を追加」

→ これでロールにS3アクセス権が付きました ✅

## ⑤ EC2にロールをアタッチ

1. サービス → **EC2**
2. 対象インスタンスを選択
3. 上部の「**アクション > セキュリティ > IAMロールを変更**」
4. 作成したロール（例：`DolcosCalcRole`）を選択 → 「IMAロールの更新」

### ⑥ EC2で確認

   * SSHでEC2に入り、次を実行：

     ```bash
     TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
     echo "$TOKEN"   # 何か文字列が返ればOK（空なら失敗）
     curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/
     # → ここでロール名（例：DolcosCalcRole）が1行で出ます
     ROLE=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/)
     curl -s -H "X-aws-ec2-metadata-token: $TOKEN" "http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE" | jq .
     # → ここで資格情報JSONを確認
     curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/info
     ```

   * これでロール名と、`iam/security-credentials/` に DolcosCalcRole が見えていればOKです。  
   * もうAWSアクセスキーは不要になります。

## 12. **Active StorageをS3に向ける**

### 1. `docker-compose.prod.yml` に`environment`を追記

* `docker-compose.prod.yml` を以下のように書き換える

   ```yaml
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
         secrets:
           - rails_master_key
       env_file: .env                      # ← EC2 に作った .env を利用
       depends_on:
         db:
           condition: service_healthy
       ports:
         - "127.0.0.1:3000:3000"
       environment:
         RAILS_SERVE_STATIC_FILES: "1"
         RAILS_LOG_TO_STDOUT: "1"
         AWS_REGION: "ap-southeast-2"              # 利用しているリージョン名
         AWS_S3_BUCKET: "dolcos-calc-prod-assets"  # S3のバケット名
       command: bash -lc "bundle exec rails db:migrate && bundle exec rails server -b 0.0.0.0 -p 3000"
       restart: unless-stopped

   secrets:
     rails_master_key:
       file: ./config/credentials/production.key

   volumes:
     db-data:
   ```
### 2. Railsの設定
* `config\storage.yml` を以下のように書き換える

   ```yaml
   test:
     service: Disk
     root: <%= Rails.root.join("tmp/storage") %>

   local:
     service: Disk
     root: <%= Rails.root.join("storage") %>

   amazon:
     service: S3
     region: <%= ENV["AWS_REGION"] %>
     bucket: <%= ENV["AWS_S3_BUCKET"] %>
   ```
* `config\environments\production.rb` を以下のように書き換える

   ```ruby
   require "active_support/core_ext/integer/time"
   Rails.application.configure do
     #...(省略)...
     config.active_storage.service = :amazon
     #...(省略)...
   end
   ```
### 3. Gem を追加
* `Gemfile`に以下を追加する

   ```ruby
   gem "aws-sdk-s3", "~> 1.139"
   gem "image_processing", "~> 1.12"  # （サムネイルや画像変換を使うなら推奨）
   ```
* ローカルで`Gemfile.lock`を更新する

   ```bash
   docker compose run --rm app bundle install
   docker compose restart app
   ```
* ※コミット時に`Gemfile.lock`も含めること！

### 4.EC2で確認
* 起動・確認

   ```bash
   # 追加したGemを反映してイメージ再ビルド
   docker compose -f docker-compose.prod.yml build --no-cache app
   # コンテナ再起動
   docker compose -f docker-compose.prod.yml up -d

   # 起動確認（ログを覗く）
   docker compose -f docker-compose.prod.yml logs --tail=200 app
   # Active Storage が :amazon になっているか確認
   docker compose -f docker-compose.prod.yml exec app rails r 'p Rails.application.config.active_storage.service'
   # => :amazon が出ればOK
   ```
## 13. **RDSとの連携**

* 🧭 ステップ 1：RDS コンソールを開く

   1. ブラウザで
      👉 [https://console.aws.amazon.com/rds/](https://console.aws.amazon.com/rds/)
      にアクセス
   2. 右上で **リージョンが「アジアパシフィック（東京）ap-northeast-1」** になっていることを確認
      （EC2 と同じリージョンである必要があります）

---

* 🧱 ステップ 2：データベースを作成

   1. 左メニュー「**データベース**」を選択
   2. 右上「**データベースの作成**」ボタンをクリック

---

* 🧩 ステップ 3：基本設定

   | 設定項目             | 推奨値・説明                                      |
   | ---------------- | ------------------------------------------- |
   | **作成方法**         | 標準作成                                        |
   | **エンジンのタイプ**  | PostgreSQL |
   | **エンジンバージョン**   | PostgreSQL 17.6-R2（最新のマイナー（RDSの R 番号付き））                 |
   | **RDS 延長サポート**   | 無効 |
   | **テンプレート**       | 開発/テスト（小規模なら）または本番                          |
   | **デプロイオプション** | シングル AZ DB インスタンスデプロイ (1 インスタンス) |
   | **DB インスタンス識別子** | dolcos-db（任意）                               |
   | **マスターユーザー名** | `postgres` |
   | **認証情報管理** | セルフマネージド、パスワードを自動生成 |

   ※ 認証情報は、データベースを作成した後に確認できます。データベース作成バナーの [認証情報の詳細を表示] をクリックすると、パスワードが表示されます。

---

* 💾 ステップ 4：インスタンスの設定 ~

   | 設定               | 推奨値（小規模想定）                             |
   | ---------------- | -------------------------------------- |
   | **DB インスタンスクラス** | `db.t4g.micro` or `db.t3.micro`（無料枠対応） |
   | **ストレージタイプ**     | 汎用 SSD (gp2)                           |
   | **ストレージサイズ**     | 20GB（後で拡張可）                       |
   | **自動スケーリング**     | 無効（初期段階では固定）                           |
   | **コンピューティングリソース**          | EC2 コンピューティングリソースに接続                    |
   | **EC2 インスタンス**    | `dolcos-calc-server` を選択<br>ここを選ぶと、RDS 側が“EC2からDBへ入れるように”SGを自動調整します。               |
   | **DB サブネットグループ** | 自動セットアップ                          |
   | **VPC セキュリティグループ**            | まずは 「既存の選択」 でOK<br>将来的には RDS専用SG（例：`dolcos-db-sg`） を作り、インバウンド 5432/TCP の“ソース”に EC2側SG（例：`dolcos-calc-sg`） を指定する構成がベスト                                  |
   | **追加の VPC セキュリティグループ**   | 選択なし |
   | **認証機関**   | デフォルト |
   | **データベースポート**   | 5432 |
   | **データベース認証オプション**   | パスワード認証       |
   | **データベースインサイト**   | データベースインサイト - スタンダード  |
   | **Performance Insights** | 有効 |
   | **保持期間** | 7日 |
   | **AWS KMS キー** | default |
   | **拡張モニタリング**   | 有効       |
   | **OS メトリクスの詳細度** | 60秒 |
   | **OS メトリクスのモニタリングの役割** | デフォルト |
   | **ログのエクスポート** | PostgreSQL ログのみ✅ |
   | **DevOps Guru** | OFF（あとからON可） |

---

* 🕒 ステップ 5：追加設定

   展開して次の項目を設定：

   | 項目              | 設定値                       |
   | --------------- | ------------------------- |
   | **最初のデータベース名**   | `dolcos_production`       |
   | **DB パラメータグループ**   | 既定でOK（後から変更可）             |
   | **自動バックアップ**   | 有効             |
   | **バックアップ保持期間**  | 7日（推奨）                    |
   | **バックアップウィンドウ**  | ウィンドウを選択 ⇒ 18:00 UTC 0.5時間                    |
   | **スナップショットにタグをコピー**          | ✅チェック |
   | **別の AWS リージョンでレプリケーションを有効化**          | オフ |
   | **暗号を有効化**          | ✅チェック |
   | **マイナーバージョン自動アップグレード**   | 有効             |
   | **メンテナンスウィンドウ** | ウィンドウを選択 ⇒ 土曜日 19:00 UTC 0.5時間     |

---
* 🚀 ステップ 6：作成をクリック

   数分でインスタンスが作成されます。  
   作成完了後、一覧に新しい DB が表示されます。

---

* 🔑 ステップ 7：接続情報を確認

   1. 作成した DB をクリック
   2. データベース作成バナーの [`接続の詳細を表示`] をクリック ⇒ 情報を控える  
      * **※ このパスワードを表示できるのはこのときだけです。**  
         参照用にパスワードをコピーして保存しておいてください。  
         パスワードを紛失した場合は、データベースを変更してパスワードを変更する必要があります。  
   2. **「接続とセキュリティ」タブ**を開く
   3. **「エンドポイント」**と**「ポート」**を控えておきます

      * 例：`dolcos-db.xxxxxxxxx.ap-northeast-1.rds.amazonaws.com:5432`

   このエンドポイントが、Rails の `.env.prod` に書く `DATABASE_URL` のホスト部分です。

---

* ✅ ステップ 8：動作確認（EC2から）

   ```bash
   # EC2 内で（または Docker 内で）
   cd ~/dolcos-calc
   docker compose -f docker-compose.prod.yml exec app rails r "puts ActiveRecord::Base.connection.execute('select current_timestamp').to_a"
   # {"current_timestamp"=>2025-10-20 06:24:31.325099 +0000}が返れば疎通OK
   ```

接続できれば成功。
これで次の手順「アプリ用 DB ユーザー作成（dolcos_app）」に進めます。

## 14. アプリ用 DB を RDS へ向ける
* **ステップ 1. アプリ用 DB ユーザー（最小権限）**

   一時 psql コンテナで入る（パスワードはRDS作成時のpostgres）
   ```bash
   docker run --rm -it postgres:17-alpine psql -h <RDSエンドポイント> -U postgres -d dolcos_production
   ```
   `dolcos_production=>` となるので、以下のように入力

   ```sql
   -- 1) アプリ用ユーザー
   CREATE USER dolcos_app WITH PASSWORD '強いパスワード';
   -- 2) DB接続権限
   GRANT CONNECT ON DATABASE dolcos_production TO dolcos_app;
   -- 3) publicスキーマでテーブル作成できるように
   GRANT USAGE, CREATE ON SCHEMA public TO dolcos_app;
   -- 4) 既存オブジェクトへの権限（テーブル & シーケンス）
   GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO dolcos_app;
   GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO dolcos_app;
   -- 5) これから作られるオブジェクトへのデフォルト権限
   --   （このコマンドを実行した“ロールが将来作る”オブジェクトに適用）
   ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO dolcos_app;
   ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO dolcos_app;
   -- TimeZoneを変更するなら
   ALTER DATABASE dolcos_production SET timezone = 'Asia/Tokyo';
   -- そのセッションで即時反映させるなら
   SET timezone = 'Asia/Tokyo';
   -- 確認
   SHOW timezone;                -- → Asia/Tokyo
   SELECT current_timestamp;     -- → +09:00 で出る
   \q
   ```
   `.env`（EC2 側 / 既存に追記）
   ```bash
   cd ~/dolcos-calc

   # 1) バックアップ
   cp .env .env.bak-$(date +%F_%H%M%S)

   # 2) 本番必須の値を入れる（<>は適宜）
   export RDS_HOST="<RDSエンドポイント>"
   export APP_DB_USER="dolcos_app"
   export APP_DB_PASS_RAW="<アプリDBパスワード>"

   # パスワードをURLエンコード（記号があるとき必須）
   export APP_DB_PASS_ENC=$(python3 -c "import os,urllib.parse; print(urllib.parse.quote(os.environ['APP_DB_PASS_RAW']))")
   
   # 3) 置換＆追記
   # RAILS_ENV
   grep -q '^RAILS_ENV=' .env && sed -i 's/^RAILS_ENV=.*/RAILS_ENV=production/' .env || echo 'RAILS_ENV=production' >> .env

   # DATABASE_URL
   if grep -q '^DATABASE_URL=' .env; then
     sed -i -E 's|^DATABASE_URL=.*$|DATABASE_URL=postgres://'"$APP_DB_USER"':'"$APP_DB_PASS_ENC"'@'"$RDS_HOST"':5432/dolcos_production|' .env
   else
     echo "DATABASE_URL=postgres://$APP_DB_USER:$APP_DB_PASS_ENC@$RDS_HOST:5432/dolcos_production" >> .env
   fi

   # 4) ローカル用POSTGRES_*を削除
   sed -i -E '/^POSTGRES_(USER|PASSWORD|DB)=/d' .env

   # 5) マスクして確認
   echo "--- masked preview ---"
   sed -E \
     -e 's#(DATABASE_URL=postgres://[^:]+:)[^@]+#\1********#' \
     -e 's#(SECRET_KEY_BASE=).*#\1********#' \
     -e 's#(SMTP_PASSWORD=).*#\1********#' \
     .env | grep -E '^(RAILS_ENV|DATABASE_URL|SECRET_KEY_BASE|APP_HOST|MAILER_SENDER|SMTP_)='
   ```

   再起動して確認
   ```bash
   docker compose -f docker-compose.prod.yml up -d --force-recreate app
   docker compose -f docker-compose.prod.yml exec app rails r "puts ActiveRecord::Base.connection.execute('select current_user').to_a"
   ```
   `{"current_user"=>"dolcos_app"}` が出ればOK

* **ステップ 2. RDS 連携前の暫定疎通用として db サービス（ローカルPostgres）を入れていた名残を削除**

   `docker-compose.prod.yml` を以下に修正

   ```yaml
   services:
     app:
       build:
         context: .
         dockerfile: app/Dockerfile.prod
         secrets:
           - rails_master_key
           - db_url
       env_file: .env                      # ← EC2 に作った .env を利用
       ports:
         - "127.0.0.1:3000:3000"
       environment:
         RAILS_SERVE_STATIC_FILES: "1"
         RAILS_LOG_TO_STDOUT: "1"
         AWS_REGION: "ap-southeast-2"
         AWS_S3_BUCKET: "dolcos-calc-prod-assets"
       command: bash -lc "bundle exec rails db:migrate && bundle exec rails server -b 0.0.0.0 -p 3000"
       restart: unless-stopped

   secrets:
     rails_master_key:
       file: ./config/credentials/production.key
     db_url:
       environment: DATABASE_URL
   ```
   `Dockerfile.prod` を修正
   ```dockerfile
   # syntax=docker/dockerfile:1.7
   FROM public.ecr.aws/docker/library/ruby:3.3-slim
   # ...(省略)...
      # ビルド時はダミーの SECRET_KEY_BASE を渡す（実行時は .env の本物を使用）
      RUN --mount=type=secret,id=rails_master_key \
         --mount=type=secret,id=db_url \
         sh -lc 'set -eu; \
           RAILS_MASTER_KEY="$(tr -d "\r\n" </run/secrets/rails_master_key)"; \
            DATABASE_URL="$(tr -d "\r\n" </run/secrets/db_url)"; \
            export RAILS_MASTER_KEY DATABASE_URL; \
            export SECRET_KEY_BASE=dummy; \
           bundle exec rails assets:precompile'
   # ...(省略)...
   ```

   ローカルDBコンテナやボリュームが残っていれば掃除 (EC2内)

   ```bash
   # 1) ローカルDBコンテナの確認
   docker ps -a
   # 1) ローカルDBコンテナを停止・削除
   docker rm -f <dbコンテナ名>  # いれば
   # 2) ボリュームの確認（dbのデータが入っているボリューム名を特定）
   docker volume ls
   # 3) 不要ならボリュームも削除（※残データを完全削除）
   docker volume rm <db-data>   # いれば
   # 5) 孤児コンテナ/サービス整理（db を消した後の掃除）
   docker compose -f docker-compose.prod.yml up -d --remove-orphans
   ```

* **ステップ 3.反映 & 検証**

   ```powershell
   # マイグレーション実行
   docker compose -f docker-compose.prod.yml exec app rails db:migrate

   # ヘルスチェック
   docker compose -f docker-compose.prod.yml exec app rails r "puts ActiveRecord::Base.connection.current_database"
   # dolcos_productionが出れば成功
   ```










<br><br><br><br><br><br><br><br><br><br>
# AWSの本番環境の安全性

## **「IAM」 「ロール」 「インスタンスロール」 「S3連携」の関係**

### 🧭 まず基本用語の整理

| 用語                                      | 意味                                                                           |
| --------------------------------------- | ---------------------------------------------------------------------------- |
| **IAM（Identity and Access Management）** | AWSの「権限管理サービス」。誰がどのAWSリソース（S3やEC2など）にアクセスできるかを制御する仕組み。                       |
| **IAMユーザー**                             | 特定の人（あなた自身や開発者）を表すアカウント。AWSコンソールにログインしたり、アクセスキーを発行できる。                       |
| **IAMロール**                              | 「この権限でAWSの他のサービスを操作していいですよ」という“権限セット”。                                       |
| **インスタンスロール**                           | EC2 に付ける **IAMロール** のこと。EC2 が自分自身として AWS の API（S3など）を叩けるようになる。つまり「EC2本人の権限」。 |


### 🧩 なぜインスタンスロールが必要か？

Rails（Active Storage）がS3へ画像をアップロードするとき、
通常は **AWSのAPI** を使ってアクセスします。

* APIを呼ぶには「誰が呼んでいるか（認証情報）」が必要
* EC2が「自分自身の権限でアクセスできる」ようにするのが **インスタンスロール**

✅ メリット

* `.env` にアクセスキーを保存する必要がない（セキュア）
* キーの流出リスクゼロ
* 権限を中央管理できる

## **セキュリティ・メンテナンス**

* `.env` に含まれる秘密値は外部に出さない（S3 / Parameter Storeなどで管理予定）
* **SSHポート (22)** は “自分のIPだけ” 許可
