# Devise導入

Rails 8 + Hotwire（Turbo）／Importmap 構成のまま、Devise 本流のネーミングに合わせて、  
* サインアップ
* ログイン
* ログアウト
* メール確認（Confirmable）
* パスワード再設定（Recoverable）
* 記憶しますか？（Rememberable）
* Trackable  
* ゲストログイン  

を有効化する最小構成を一気に作ります。（コマンドはすべて **docker compose 経由** です）

---

## 手順（最短ルート）

### 1) Gem 追加と初期設定

* Gem 追加  
   ```bash
   docker compose exec app bundle add devise
   docker compose exec app rails g devise:install
   ```

* `.rubocop.yml` で`config/initializers/devise.rb`を除外
   ```yaml
   AllCops:
     Exclude:
       - 'config/initializers/devise.rb'
   ```

* 生成された `config/initializers/devise.rb` に **Turbo 互換** を追加（重要）：

   ```ruby
   # Turbo (Hotwire) と共存
   config.navigational_formats = ['*/*', :html, :turbo_stream]
   ```

* **開発環境**のメール URL 既定（確認メール用）
  `config/environments/development.rb` に追記：

   ```ruby
   config.action_mailer.default_url_options = { host: 'localhost', port: 3000 }
   # 開発では letter_opener_web 等を使うならここに設定してOK（必要なら後で）
   ```

### 2) User モデルを作る（Devise 流儀そのままの命名）
* Devise 流儀そのままの命名
   ```bash
   docker compose exec app rails g devise User
   ```

   > これで `users` テーブルの基本列（email, encrypted_password など）と `User` モデルができます。

### 3) 必要モジュールを **Migration に追加**（Confirmable / Recoverable / Rememberable / Trackable）

* 生成された **`db/migrate/*_devise_create_users.rb`** を開き、下のように編集します。

   ```ruby
   class DeviseCreateUsers < ActiveRecord::Migration[8.0]
     def change
       create_table :users do |t|
         ## Database authenticatable
         t.string  :email,              null: false, default: ""
         t.string  :encrypted_password, null: false, default: ""

         ## Recoverable（パスワードをお忘れですか？）
         t.string   :reset_password_token
         t.datetime :reset_password_sent_at

         ## Rememberable（記憶しますか？）
         t.datetime :remember_created_at

         ## Trackable
         t.integer  :sign_in_count, default: 0, null: false
         t.datetime :current_sign_in_at
         t.datetime :last_sign_in_at
         # Postgres なら inet 型が綺麗（string でも可）
         t.inet     :current_sign_in_ip
         t.inet     :last_sign_in_ip

         ## Confirmable（メール確認）
         t.string   :confirmation_token
         t.datetime :confirmed_at
         t.datetime :confirmation_sent_at
         t.string   :unconfirmed_email # 変更時に使用（任意だが一般的）

         ## 監査的に欲しければ
         # t.timestamps null: false
         t.timestamps
       end

       add_index :users, :email,                unique: true
       add_index :users, :reset_password_token, unique: true
       add_index :users, :confirmation_token,   unique: true
     end
   end
   ```

   > 追記ポイント
   >
   > * **Trackable** の IP カラムは PostgreSQL なので `:inet` を採用。
   > * Confirmable の `unconfirmed_email` はメール変更時の再確認に使うため入れておくのが Devise 流。  

### 4) マイグレーション実行

* マイグレーション実行

   ```bash
   docker compose exec app rails db:migrate
   ```

### 5) User モデルの有効モジュールを宣言、およびゲストログイン設定

* `app/models/user.rb`

    ```ruby
    class User < ApplicationRecord
      devise :database_authenticatable, :registerable,
            :recoverable, :rememberable, :validatable,
            :confirmable, :trackable

      GUEST_EMAIL_PREFIX = "guest+".freeze
      GUEST_EMAIL_DOMAIN = "example.com".freeze

      def self.guest
        10.times do
          token     = SecureRandom.hex(4)               # 8桁（衝突しにくい）
          email     = "#{GUEST_EMAIL_PREFIX}#{token}@#{GUEST_EMAIL_DOMAIN}"
          password  = SecureRandom.urlsafe_base64(16)   # Deviseの最小長(デフォ6)を超える十分な長さ

          user = new(email: email, password: password, password_confirmation: password)

          # Confirmable を使っている場合はメール確認をスキップ
          user.skip_confirmation! if user.respond_to?(:skip_confirmation!)

          begin
            user.save!
            return user
          rescue ActiveRecord::RecordNotUnique
            # 非常にまれに email が衝突したらリトライ
            next
          end
        end
        raise "Failed to create guest user (email collision)"
      end

      def guest?
        email&.start_with?("guest+")
      end
    end
    ```

### 6) ルーティング

* まずシンプルなコントローラを用意：

   ```bash
   docker compose exec app rails g controller Pages home
   docker compose exec app rails g controller Workspaces show
   ```

* `config/routes.rb`

    ```ruby
    Rails.application.routes.draw do
      devise_for :users, controllers: {
        sessions: "users/sessions"   # ← これで Devise が Users::SessionsController を使う
      }
      # ゲストサインイン
      devise_scope :user do
        post "users/guest_sign_in", to: "users/sessions#guest", as: :guest_sign_in
      end

      get "up" => "rails/health#show", as: :rails_health_check
    
      # ログイン後はworkspaceへ
      authenticated :user do
        root to: "workspaces#show", as: :authenticated_root
      end

      # 非認証の時はこちら
      unauthenticated do
        root to: "pages#home", as: :unauthenticated_root
      end

      resource :workspace, only: :show
    end
    ```

* ユーザー切替時の処理：

  `app/controllers/application_controller.rb`

    ```ruby
    # ユーザー切替時の処理
    def after_sign_out_path_for(_resource_or_scope)
      case params[:redirect]
      when "sign_in" then new_user_session_path
      when "sign_up" then new_user_registration_path
      else                unauthenticated_root_path
      end
    end
    ```

### 7) Devise の ビューとフォーム

* Devise の標準テンプレは `form_for` ですが、**本プロジェクト方針（form_withのみ）** に合わせ、最低限の画面だけ置き換えます。
（当面はログインとサインアップだけ変えれば十分）

   ```bash
   docker compose exec app rails g devise:views
   ```

* `app/views/devise/sessions/new.html.erb`（抜粋：`form_with` 化）

   ```erb
   <h2>ログイン</h2>
   <%= form_with scope: resource_name, url: session_path(resource_name), html: { class: "needs-validation" } do |f| %>
     <div class="mb-3">
       <%= f.label :email, "メールアドレス" %>
       <%= f.email_field :email, autofocus: true, autocomplete: "email", class: "form-control" %>
     </div>

     <div class="mb-3">
       <%= f.label :password, "パスワード" %>
       <%= f.password_field :password, autocomplete: "current-password", class: "form-control" %>
     </div>

     <% if devise_mapping.rememberable? %>
       <div class="form-check mb-3">
         <%= f.check_box :remember_me, class: "form-check-input" %>
         <%= f.label :remember_me, "記憶しますか？", class: "form-check-label" %>
       </div>
     <% end %>

     <%= f.submit "ログイン", class: "btn btn-primary" %>
   <% end %>

   <div class="mt-3">
     <%= link_to "パスワードをお忘れですか？", new_password_path(resource_name) %><br>
     <%= link_to "新規登録", new_registration_path(resource_name) %>
   </div>
   ```

* `app/views/devise/registrations/new.html.erb`（抜粋）

   ```erb
   <h2>新規登録</h2>
   <%= form_with model: resource, as: resource_name, url: registration_path(resource_name) do |f| %>
     <div class="mb-3">
       <%= f.label :email, "メールアドレス" %>
       <%= f.email_field :email, autofocus: true, autocomplete: "email", class: "form-control" %>
     </div>

     <div class="mb-3">
       <%= f.label :password, "パスワード" %>
       <%= f.password_field :password, autocomplete: "new-password", class: "form-control" %>
       <small class="text-muted">6文字以上</small>
     </div>

     <div class="mb-3">
       <%= f.label :password_confirmation, "パスワード（確認）" %>
       <%= f.password_field :password_confirmation, autocomplete: "new-password", class: "form-control" %>
     </div>

     <%= f.submit "登録する", class: "btn btn-primary" %>
   <% end %>
   ```

   > 以外の Devise 画面（パスワード再設定、確認再送 等）は後で順次 `form_with` に置換でOK。  

* **パスワード再設定メール送信**

    ```erb
    <%= form_with scope: resource_name, url: password_path(resource_name) do |f| %>
      ...
    <% end %>
    ```

* **パスワード変更（トークン付き）**

    ```erb
    <%= form_with model: resource, as: resource_name, url: password_path(resource_name) do |f| %>
      <%= f.hidden_field :reset_password_token %>
      ...
    <% end %>
    ```

---

### 10) その他のビューとコントローラー

* `app\controllers\pages_controller.rb`

    ```ruby
    class PagesController < ApplicationController
      def home
      end
    end
    ```

* `app\views\pages\home.html.erb`

    ```erb
    <%= link_to "新規登録", new_user_registration_path, class: "btn btn-primary btn-lg px-4" %>
    <%= link_to "ログイン",     new_user_session_path,   class: "btn btn-outline-secondary btn-lg px-4" %>
    <%= link_to "ゲストとして利用", guest_sign_in_path, class: "btn btn-link btn-lg text-decoration-none", data: { turbo_method: :post, turbo_frame: "_top" } %>
    ```

* `app\controllers\workspaces_controller.rb`

    ```ruby
    class WorkspacesController < ApplicationController
      before_action :authenticate_user!
      def show
      end
    end
    ```

* `app\views\workspaces\show.html.erb`

    ```erb
    <%= turbo_frame_tag "main", src: dummy_path, loading: "lazy" do %>
      <div class="p-3 text-muted">読み込み中...</div>
    <% end %>
    ```

* ```app\controllers\dummies_controller.rb```

    ```ruby
    class DummiesController < ApplicationController
      def show
      end
    end
    ```

* `app\views\dummies\show.html.erb`

    ```erb
    <%= turbo_frame_tag "main" do %>
      <ul>
        <% if current_user.guest? %>
          <li>
            <%= link_to destroy_user_session_path(redirect: "sign_in"),
                        data: { turbo_method: :delete, turbo_frame: "_top",
                                turbo_confirm: "ゲストを終了してログイン画面へ進みます。よろしいですか？" },
                        class: "dropdown-item" do %>
              <i class="bi bi-arrow-left-right me-2"></i> ログイン
            <% end %>
          </li>
          <li>
            <%= link_to destroy_user_session_path(redirect: "sign_up"),
                        class: "dropdown-item",
                        data: { turbo_method: :delete, turbo_frame: "_top",
                                turbo_confirm: "ゲストを終了して新規登録画面へ進みます。よろしいですか？" } do %>
              <i class="bi bi-person-plus me-2"></i> 新規登録
            <% end %>
          </li>
        <% else %>
          <li>
            <%= link_to dummy_path,
                        class: "dropdown-item", data: { turbo_frame: "main" } do %>
              <i class="bi bi-gear me-2"></i> 設定
            <% end %>
          </li>
          <li>
            <%= link_to destroy_user_session_path(redirect: "sign_in"),
                        data: { turbo_method: :delete, turbo_frame: "_top",
                                turbo_confirm: "ユーザーを切り替えます。よろしいですか？" },
                        class: "dropdown-item" do %>
              <i class="bi bi-arrow-left-right me-2"></i> ユーザーを切り替える
            <% end %>
          </li>
          <li>
            <%= link_to destroy_user_session_path,
                        data: { turbo_method: :delete, turbo_frame: "_top",
                                turbo_confirm: "ログアウトしますか？" },
                        class: "dropdown-item text-danger" do %>
              <i class="bi bi-box-arrow-right me-2"></i> ログアウト
            <% end %>
          </li>
        <% end %>
      </ul>
    <% end %>
    ```

* `app\controllers\users\sessions_controller.rb`：新規作成する

    ```bash
    docker compose exec app rails g controller users/sessions --no-helper --no-assets
    ```

    ```ruby
    class Users::SessionsController < Devise::SessionsController
      def guest
        user = User.guest
        sign_in(:user, user)
        user.forget_me! if user.respond_to?(:forget_me!)
        session[:guest_user] = true
        redirect_to authenticated_root_path, notice: "ゲストとしてログインしました"
      end
    end
    ```

---

### 9) メール送信（Confirmable 動作に必須）

* **開発環境**ではまず **実メール不要** で試すのがおすすめ（例：letter_opener_web）。  
    本番は SMTP を設定。ここでは最小だけ：

   `config/environments/development.rb`

   ```ruby
   # Devise の確認メール等を「送信せず」ブラウザで閲覧
   config.action_mailer.perform_deliveries = true
   config.action_mailer.delivery_method    = :letter_opener_web

   # 確認メール内のURL生成に使用
   config.action_mailer.default_url_options = {
     host: ENV.fetch("APP_HOST", "localhost"),
     port: ENV.fetch("APP_PORT", 3000)
   }

   # 失敗を見落とさないように（任意）
   config.action_mailer.raise_delivery_errors = true
   ```

    `config/initializers/devise.rb`：追記

    ```ruby
    config.mailer_sender = "no-reply@localhost"
    ```

* Gemを追加：

   `Gemfile`

   ```ruby
   source "https://rubygems.org"
   #...(省略)...
   group :development do
     #...(省略)...
     gem "letter_opener_web" # ←ここ letter_opener を内部で読み込みます
   end
   #...(省略)...
   ```

* ルーティング（/letter_opener を開発限定で公開）：

   `config/routes.rb`

   ```ruby
     if Rails.env.development?
       # メール一覧が見られる UI（http://localhost:3000/letter_opener）
       mount LetterOpenerWeb::Engine, at: "/letter_opener"
     end
   ```

* 反映

   ```bash
   docker compose run --rm app bundle install
   docker compose build app
   docker compose up -d --force-recreate app
   ```

* http://localhost:3000/letter_opener に確認メールが一覧表示され、リンクをクリックすると confirmed_at が埋まります。

---

### 10) Minitest対策

`confirmable` を入れているので、 **テストでは「確認済みユーザーでログイン」** してから `get workspace_url` を叩く。
* `test/fixtures/users.yml` を作り、固有の email を入れる

   ```yaml
   one:
     email: one@example.com
     encrypted_password: <%= Devise::Encryptor.digest(User, "Passw0rd!") %>
     confirmed_at: <%= Time.current %>

   two:
     email: two@example.com
     encrypted_password: <%= Devise::Encryptor.digest(User, "Passw0rd!") %>
     confirmed_at: <%= Time.current %>
   ```

* `test/test_helper.rb`

   ```rb
   # IntegrationTest で Devise のログインヘルパを使えるように
   class ActionDispatch::IntegrationTest
     include Devise::Test::IntegrationHelpers
   end
   ```

* テストを「確認済みユーザーで sign_in」に修正

    `test\controllers\workspaces_controller_test.rb`

    ```rb
    require "test_helper"

    class WorkspacesControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = users(:one)
        sign_in @user
      end
      test "should get show" do
        get workspace_url
        assert_response :success
      end
    end
    ```

    コントローラーを新規作成した場合で `before_action :authenticate_user!` 等が含まれる場合、同様の修正が必要です。

* カバレッジを上げたいなら

    `test\controllers\users\sessions_controller_test.rb`

    ```ruby
    require "test_helper"

    class Users::SessionsControllerTest < ActionDispatch::IntegrationTest
      include Devise::Test::IntegrationHelpers

      test "guest sign-in redirects to authenticated_root" do
        post guest_sign_in_path
        assert_redirected_to authenticated_root_path

        follow_redirect!
        assert_response :success

        # ログイン必須ページにアクセスできることをもって“ログイン済”の証拠にする
        get workspace_url
        assert_response :success
      end

      test "sign out works (default)" do
        post guest_sign_in_path
        delete destroy_user_session_path
        assert_redirected_to unauthenticated_root_path # ＝ "/"
      end

      test "sign out with redirect=sign_in goes to sign-in" do
        post guest_sign_in_path
        delete destroy_user_session_path(redirect: "sign_in")
        assert_redirected_to new_user_session_path
      end
    end
    ```

### 11) 管理者ユーザーの作成

* 初期化ファイル作成

    `config/initializers/admins.rb`
    ```ruby
    module AdminConfig
      module_function

      def admin_emails
        raw = ENV.fetch("ADMIN_MAIL_ADDRESS_LIST", "")
        raw.split(",").map { _1.strip.downcase }.reject(&:empty?).uniq
      end

      def admin?(email)
        return false if email.blank?
        admin_emails.include?(email.strip.downcase)
      end
    end
    ```

* Userモデルに“委譲”メソッドを追加

    `app/models/user.rb` に、以下を追記します。
    ```ruby
    class User < ApplicationRecord
      # ...(省略)...
      # ここだけ追加（環境変数のリストに含まれるかで判定）
      def admin?
        AdminConfig.admin?(email)
      end
    end
    ```

* 環境変数の設定

    `.env`を編集する。  
    例：
    ```graphql
    ADMIN_MAIL_ADDRESS_LIST=admin1@example.com,admin2@example.com
    ```

    * ローカル  
        `.env`をそのまま編集 ※ **改行コードは LF 推奨**

    * 本番（EC2）  
        vi等で編集
        ```bash
        cd dolcos-calc
        vi .env
        ```
        > **viの基本操作**  
        >   
        > * 編集開始：`i` キーを押す（INSERTモードになる）  
        > * 入力が終わったら `Esc` を押す  
        > * 保存して終了 → `:wq` → Enter  
        > * 保存せず終了 → `:q!` → Enter  

        → ビルド


## これでできること

* `/users/sign_up` で登録 ⇒ **確認メールのリンク**を踏むと有効化
* `/users/sign_in` でログイン（**記憶しますか？** チェック対応）
* `/users/password/new` でパスワード再設定メール送信
* ログイン後は `workspaces#show` に遷移
* Trackable によりサインイン回数／最終ログイン時刻／IP を記録
* ゲストでログイン

