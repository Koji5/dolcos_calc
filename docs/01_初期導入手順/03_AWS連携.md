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

`git pull origin main`を忘れずに！  

---

## 8. **ビルドと起動**

```bash
docker-compose -f docker-compose.prod.yml build --no-cache --progress=plain
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

4. **`docker-compose.prod.yml` の編集**  
   編集前：  
   ```yaml
        ports:
          - "3000:3000"
   ```
   編集後：
   ```yaml
        ports:
          - "127.0.0.1:3000:3000"
   ```
   EC2にて：
   ```bash
   git pull origin main
   docker-compose -f docker-compose.prod.yml up -d
   ```
5. **3000番のインバウンドルールの削除**

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

<br><br>
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
