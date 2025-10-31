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
* 管理者ログイン（初期）  

を有効化する最小構成を一気に作ります。（コマンドはすべて **docker compose 経由** です）  

> 基本レイアウトも同時に作成します。

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

### 5) 管理者ユーザーの作成

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

### 6) User モデルの有効モジュールを宣言、およびゲストログイン設定

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

      def admin?
        AdminConfig.admin?(email)
      end
    end
    ```

### 7) ルーティング

* まずシンプルなコントローラを用意：

   ```bash
   docker compose exec app rails g controller Pages home
   docker compose exec app rails g controller Workspaces show
   docker compose exec app rails g controller Dummies show
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
      resource :dummy, only: :show
    end
    ```

* ユーザー切替時の処理：

  追記： `app/controllers/application_controller.rb`

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

### 8) Devise の ビューとフォーム

* Devise の標準テンプレは `form_for` ですが、**本プロジェクト方針（form_withのみ）** に合わせ、最低限の画面だけ置き換えます。

   ```bash
   docker compose exec app rails g devise:views
   ```

* `app\views\shared\_link_to_top.html.erb`

  ```erb
  <%# 期待する locals:
  #  - path:        文字列URL or *_path(...) の戻り値（必須推奨）
  #  - label:       リンク文言（省略時デフォルト）
  #  - classes:     追加クラス（省略可）
  #  - turbo_frame: Turbo遷移先フレーム（省略時 "_top"）
  -%>

  <% label       ||= "ドルコス計算機" %>
  <% classes     ||= "navbar-brand flex-grow-1 text-primary-emphasis text-center text-sm-start m-0 ms-2 fw-bold" %>
  <% turbo_frame ||= "_top" %>

  <%= link_to path, class: classes, data: { turbo_frame: turbo_frame } do %>
    <%= image_tag "top-icon.svg",
                  alt: "",
                  aria: { hidden: true } %>
    <span class="align-middle ps-2"><%= label %></span>
  <% end %>
  ```

* `app\views\devise\shared\_header.html.erb`

    ```erb
    <header id="appHeader" class="navbar text-primary-emphasis bg-primary-subtle border border-primary-subtle border-bottom sticky-top">
      <div class="container-fluid d-flex align-items-center gap-2 ps-2">
        <%= render "shared/link_to_top", path: unauthenticated_root_path %>
      </div>
    </header>

    <div id="alert"><% unless turbo_frame_request? %><%= render "shared/alert" %><% end %></div>
    ```

* ログイン画面  

  `app/views/devise/sessions/new.html.erb`（`form_with` 化・日本語化）

  ```erb
  <%= render "devise/shared/header" %>
  <div class="container py-3">
    <div class="card w-100 mx-auto" style="max-width: 720px;">
      <h5 class="card-header">ログイン</h5>
      <%= form_with scope: resource_name, url: session_path(resource_name), html: { class: "needs-validation" } do |f| %>

        <div class="card-body">
          <div class="row g-3 mb-3 align-items-center">
            <div class="col-md-3">
              <%= f.label :email, "メールアドレス" %>
            </div>
            <div class="col-md-5">
              <%= f.email_field :email, autofocus: true, autocomplete: "email", class: "form-control", aria_labelledby: "emailHelpInline" %>
            </div>
            <div class="col-md-4"></div>
          </div>

          <div class="row g-3 mb-3 align-items-center">
            <div class="col-md-3">
              <%= f.label :password, "パスワード", class: "col-form-label" %>
            </div>
            <div class="col-md-5">
              <%= f.password_field :password, autocomplete: "new-password", class: "form-control" %>
            </div>
            <div class="col-md-4">
              <% if devise_mapping.rememberable? %>
                <%= f.check_box :remember_me, class: "form-check-input" %>
                <%= f.label :remember_me, "ログイン情報を記憶する", class: "form-check-label fw-light" %>
              <% end %>
            </div>
          </div>
          <div class="row g-3 mb-3 align-items-center">
            <div class="col-md-12"><%= f.submit "ログイン", class: "btn btn-primary" %></div>
          </div>
        </div>
      <% end %>
    </div>
    <div class="w-100 mx-auto mt-3" style="max-width: 720px;">
      <%= link_to "パスワードをお忘れですか？", new_password_path(resource_name) %><br>
      <%= link_to "確認メールを再送", new_confirmation_path(resource_name) %><br>
      <%= link_to "新規登録", new_registration_path(resource_name) %>
    </div>
  </div>
  ```

* 新規登録画面  

  `app/views/devise/registrations/new.html.erb`（`form_with` 化・日本語化）

  ```erb
  <%= render "devise/shared/header" %>
  <div class="container py-3">
    <div class="card w-100 mx-auto" style="max-width: 720px;">
      <h5 class="card-header">新規登録</h5>
      <%= form_with model: resource, as: resource_name, url: registration_path(resource_name) do |f| %>
        <div class="card-body">

          <div class="row g-3 mb-3 align-items-center">
            <div class="col-md-3">
              <%= f.label :email, "メールアドレス", class: "col-form-label" %>
            </div>
            <div class="col-md-5">
              <%= f.email_field :email, autofocus: true, autocomplete: "email", class: "form-control", aria_labelledby: "emailHelpInline" %>
            </div>
            <div class="col-md-4">
              <span id="emailHelpInline" class="form-text">
                （受信可能なメールアドレス）
              </span>
            </div>
          </div>

          <div class="row g-3 mb-3 align-items-center">
            <div class="col-md-3">
              <%= f.label :password, "パスワード", class: "col-form-label" %>
            </div>
            <div class="col-md-5">
              <%= f.password_field :password, autocomplete: "new-password", class: "form-control", aria_labelledby: "passwordHelpInline" %>
            </div>
            <div class="col-md-4">
              <span id="passwordHelpInline" class="form-text">
                （6文字以上）
              </span>
            </div>
          </div>

          <div class="row g-3 mb-3 align-items-center">
            <div class="col-md-3">
              <%= f.label :password_confirmation, "パスワード（確認）", class: "col-form-label" %>
            </div>
            <div class="col-md-5">
              <%= f.password_field :password_confirmation, autocomplete: "new-password", class: "form-control", aria_labelledby: "passwordConfirmationHelpInline" %>
            </div>
            <div class="col-md-4">
              <span id="passwordConfirmationHelpInline" class="form-text">
                （同じパスワードを再入力）
              </span>
            </div>
          </div>
          <%= f.submit "登録する", class: "btn btn-primary" %>
        </div>
      <% end %>
    </div>
  </div>
  ```

* 確認メールの再送画面  

  `app\views\devise\confirmations\new.html.erb`（`form_with` 化・日本語化）

  ```erb
  <%= render "devise/shared/header" %>
  <div class="container py-3">
    <div class="card w-100 mx-auto" style="max-width: 720px;">
      <h5 class="card-header">確認メールの再送</h5>

      <%= form_with scope: resource_name, url: confirmation_path(resource_name) do |f| %>
        <div class="card-body">
          <p class="small text-body-secondary mb-3">
            登録済みのメールアドレスを入力してください。確認用メールを再送します。
          </p>

          <div class="row g-3 mb-3 align-items-center">
            <div class="col-md-3">
              <%= f.label :email, "メールアドレス", class: "col-form-label" %>
            </div>
            <div class="col-md-5">
              <%= f.email_field :email, autofocus: true, autocomplete: "email", class: "form-control" %>
            </div>
            <div class="col-md-4"></div>
          </div>

          <%= f.submit "確認メールを送信", class: "btn btn-primary" %>
        </div>
      <% end %>
    </div>

    <div class="w-100 mx-auto mt-3" style="max-width: 720px;">
      <%= link_to "ログインに戻る", new_session_path(resource_name) %><br>
      <%= link_to "新規登録", new_registration_path(resource_name) %>
    </div>
  </div>
  ```

* パスワード再設定画面  

  `app\views\devise\passwords\new.html.erb`（`form_with` 化・日本語化）

  ```erb
  <%= render "devise/shared/header" %>
  <div class="container py-3">
    <div class="card w-100 mx-auto" style="max-width: 720px;">
      <h5 class="card-header">パスワード再設定</h5>

      <%= form_with scope: resource_name, url: password_path(resource_name), method: :post do |f| %>
        <div class="card-body">
          <p class="text-body-secondary small mb-3">
            登録済みのメールアドレスを入力してください。パスワード再設定用のリンクをお送りします。
          </p>

          <div class="row g-3 mb-3 align-items-center">
            <div class="col-md-3">
              <%= f.label :email, "メールアドレス", class: "col-form-label" %>
            </div>
            <div class="col-md-5">
              <%= f.email_field :email,
                                autofocus: true,
                                autocomplete: "email",
                                class: "form-control",
                                aria_labelledby: "passwordEmailHelpInline" %>
            </div>
            <div class="col-md-4">
              <span id="passwordEmailHelpInline" class="form-text">
                （受信可能なメールアドレス）
              </span>
            </div>
          </div>

          <%= f.submit "再設定メールを送信", class: "btn btn-primary" %>
        </div>
      <% end %>
    </div>

    <div class="w-100 mx-auto mt-3" style="max-width: 720px;">
      <%= link_to "ログインに戻る", new_session_path(resource_name) %><br>
      <%= link_to "新規登録", new_registration_path(resource_name) %>
    </div>
  </div>
  ```

* 新しいパスワードの設定画面  

  `app\views\devise\passwords\edit.html.erb`（`form_with` 化・日本語化）

  ```erb
  <%= render "devise/shared/header" %>
  <div class="container py-3">
    <div class="card w-100 mx-auto" style="max-width: 720px;">
      <h5 class="card-header">新しいパスワードの設定</h5>

      <%= form_with model: resource, as: resource_name, url: password_path(resource_name), method: :put do |f| %>
        <div class="card-body">
          <%= f.hidden_field :reset_password_token %>

          <p class="text-body-secondary small mb-3">
            登録メール宛に送信されたリンクからこのページに来ています。新しいパスワードを入力してください。
          </p>

          <div class="row g-3 mb-3 align-items-center">
            <div class="col-md-3">
              <%= f.label :password, "新しいパスワード", class: "col-form-label" %>
            </div>
            <div class="col-md-5">
              <%= f.password_field :password,
                                  autocomplete: "new-password",
                                  class: "form-control",
                                  aria_labelledby: "newPasswordHelpInline" %>
            </div>
            <div class="col-md-4">
              <span id="newPasswordHelpInline" class="form-text">
                <% if @minimum_password_length %>
                  （<%= @minimum_password_length %>文字以上）
                <% else %>
                  （6文字以上）
                <% end %>
              </span>
            </div>
          </div>

          <div class="row g-3 mb-3 align-items-center">
            <div class="col-md-3">
              <%= f.label :password_confirmation, "新しいパスワード（確認）", class: "col-form-label" %>
            </div>
            <div class="col-md-5">
              <%= f.password_field :password_confirmation,
                                  autocomplete: "new-password",
                                  class: "form-control",
                                  aria_labelledby: "passwordConfirmationHelpInline" %>
            </div>
            <div class="col-md-4">
              <span id="passwordConfirmationHelpInline" class="form-text">
                （同じパスワードを再入力）
              </span>
            </div>
          </div>

          <%= f.submit "パスワードを変更する", class: "btn btn-primary" %>
        </div>
      <% end %>
    </div>

    <div class="w-100 mx-auto mt-3" style="max-width: 720px;">
      <%= link_to "ログインに戻る", new_session_path(resource_name) %>
    </div>
  </div>
  ```
---

### 9) Devise の メール日本語化

**件名はI18nのキーで日本語化されますが、本文はDeviseのデフォルトviewが英語固定**なので、そのままだと英語になります。  
本文も日本語にするには **Deviseのメールviewを上書き**してください。
> * `rails g devise:views -v mailer` は通常 **HTML版（`.html.erb`）のみ**を出します。  
> * **テキスト版（`.text.erb`）も配信したい**場合は、自分でファイルを追加してください。  
> * **`.html.erb` だけでも送信可**。ただし可読性・迷惑メール判定・アクセシビリティの観点で、テキスト版も用意するのがおすすめです。  
> * 両方置くと **ActionMailer が自動で multipart（text + html）** にして送ります。  
> * HTML版にレイアウトを当てている場合、**テキスト用レイアウト**（`app/views/layouts/mailer.text.erb`）も置けばテキストメールにも適用できます。  
> * 件名は I18n のキーで日本語化されます（`devise-i18n` を導入していれば既に日本語）。  

* メールアドレス確認（Confirmable）  

  `app/views/devise/mailer/confirmation_instructions.html.erb`

  ```erb
  <p><%= @resource.try(:name) || @email %> 様</p>
  <p>ドルコス計算機へのご登録ありがとうございます。以下のボタンからメールアドレスの確認を完了してください。</p>
  <p>
    <%= link_to "メールアドレスを確認する", confirmation_url(@resource, confirmation_token: @token), class: "btn btn-primary" %>
  </p>
  <p>もしこのメールにお心当たりがない場合は、本メールは破棄してください。</p>
  ```

  `app/views/devise/mailer/confirmation_instructions.text.erb`

  ```text
  <%= @resource.try(:name) || @email %> 様

  ドルコス計算機へのご登録ありがとうございます。
  以下のURLからメールアドレスの確認を完了してください。

  <%= confirmation_url(@resource, confirmation_token: @token) %>

  ※お心当たりがない場合は本メールを破棄してください。
  ```

* パスワード再設定

  `app/views/devise/mailer/reset_password_instructions.html.erb`

  ```erb
  <p><%= @resource.try(:name) || @email %> 様</p>
  <p>パスワード再設定のご依頼を受け付けました。以下のボタンから再設定手続きを行ってください。</p>
  <p>
    <%= link_to "パスワードを再設定する", edit_password_url(@resource, reset_password_token: @token), class: "btn btn-primary" %>
  </p>
  <p>この操作にお心当たりがない場合は、本メールは破棄してください。上記リンクを開くまでパスワードは変更されません。</p>
  ```

  `app/views/devise/mailer/reset_password_instructions.text.erb`

  ```text
  <%= @resource.try(:name) || @email %> 様

  パスワード再設定のご依頼を受け付けました。
  以下のURLから再設定手続きを行ってください。

  <%= edit_password_url(@resource, reset_password_token: @token) %>

  ※お心当たりがない場合は本メールを破棄してください。
  ```

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
    <div id="alert"><% unless turbo_frame_request? %><%= render "shared/alert" %><% end %></div>
    ...
    <%= link_to "新規登録", new_user_registration_path, class: "btn btn-primary btn-lg px-4" %>
    <%= link_to "ログイン",     new_user_session_path,   class: "btn btn-outline-secondary btn-lg px-4" %>
    <%= link_to "ゲストとして利用", guest_sign_in_path, class: "btn btn-link btn-lg text-decoration-none", data: { turbo_method: :post, turbo_frame: "_top" } %>
    ...
    ```

* `app\controllers\workspaces_controller.rb`

    ```ruby
    class WorkspacesController < ApplicationController
      before_action :authenticate_user!
      def show
      end
    end
    ```

* `app\views\workspaces\show.html.erb`（レイアウトまで一気に）

  ```erb
  <header id="appHeader" class="navbar text-primary-emphasis bg-primary-subtle border border-primary-subtle border-bottom sticky-top">
    <div class="container-fluid d-flex align-items-center gap-2 ps-2">

      <!-- 左: ハンバーガー（XL未満のみ表示） -->
      <button class="btn text-primary-emphasis bg-primary-subtle border-primary-subtle d-xl-none"
              type="button"
              data-bs-toggle="offcanvas"
              data-bs-target="#appSidebar"
              aria-controls="appSidebar"
              aria-label="メニューを開く">
        <i class="bi bi-list" aria-hidden="true"></i>
      </button>

      <!-- 中央: サイトタイトル（xsは中央寄せ＆トランケート、sm以上は左寄せ） -->
      <%= render "shared/link_to_top", path: authenticated_root_path %>

      <!-- 右: ユーザードロップダウン（xsはアイコンのみ、md以上でメール表示） -->
      <div class="dropdown">
        <!--button class="btn btn-outline-secondary dropdown-toggle d-flex align-items-center"-->
        <button class="btn text-primary-emphasis bg-primary-subtle border-primary-subtle dropdown-toggle d-flex align-items-center"
                type="button" data-bs-toggle="dropdown" aria-expanded="false"
                aria-label="<%= current_user.guest? ? 'ゲストメニュー' : 'ユーザーメニュー' %>">
          <i class="bi bi-person-circle" aria-hidden="true"></i>
          <span class="d-none d-md-inline ms-2 text-primary-emphasis" style="max-width: 28ch;">
            <% if current_user.guest? %>
              ゲスト
            <% else %>
              <%= current_user.email %>
            <% end %>
          </span>

        </button>

        <ul class="dropdown-menu dropdown-menu-end">
          <% if current_user.guest? %>
            <!-- ゲスト用：設定は省略or読み取り専用にするならリンクなしでもOK -->
            <li>
              <%= link_to destroy_user_session_path(redirect: "sign_in"),
                          data: { turbo_method: :delete, turbo_frame: "_top",
                                  turbo_confirm: "ゲストを終了してログイン画面へ進みます。よろしいですか？" },
                          class: "dropdown-item" do %>
                <i class="bi bi-arrow-left-right me-2"></i> ログイン
              <% end %>
            </li>
            <li><hr class="dropdown-divider"></li>
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
            <li><hr class="dropdown-divider"></li>
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
      </div>

    </div>
  </header>

  <div id="alert"><% unless turbo_frame_request? %><%= render "shared/alert" %><% end %></div>

  <div class="container-fluid">
    <!-- ★ ヘッダー直下のラッパ。XL以上は固定高＆内部だけスクロール -->
    <div class="app-shell d-xl-flex">

      <nav id="appSidebar"
          class="offcanvas offcanvas-start offcanvas-xl border-end app-col"
          tabindex="-1"
          aria-labelledby="appSidebarLabel"
          style="--bs-offcanvas-width: 260px;"
          data-controller="workspaces--sidebar"
          data-workspaces--sidebar-frame-value="main"
          data-workspaces--sidebar-target-value="#appSidebar">
        <div class="offcanvas-header d-xl-none d-flex align-items-center gap-2">
          <h5 class="offcanvas-title flex-grow-1 mb-0 text-truncate" id="appSidebarLabel">メニュー</h5>
          <button type="button" class="btn btn-outline-secondary ms-auto" data-bs-dismiss="offcanvas" aria-label="閉じる">
            <i class="bi bi-list" aria-hidden="true"></i>
          </button>
        </div>
        <!-- ★ ここは app-col が高さ100%を持つので h-100 を付けておくと安定 -->
        <div class="offcanvas-body p-0 h-100">
          <%= render "workspaces/sidebar" %>
        </div>
      </nav>

      <main class="flex-grow-1 py-3 app-col">
        <%= turbo_frame_tag "main", src: dummy_path, loading: "lazy" do %>
          <div class="p-3 text-muted">読み込み中...</div>
        <% end %>
      </main>

      <aside class="d-none d-xxl-block border-start py-3 app-col" style="width: 280px;">
        <div class="card">
          <div class="card-body">
            <div class="text-muted">広告スペース（XXL以上で表示）</div>
            <div class="ratio ratio-1x1 mt-2 border rounded"></div>
          </div>
        </div>
      </aside>
    </div>
  </div>

  <!-- ヘッダー高さを CSS 変数に反映（レスポンシブ対応） -->
  <script type="module">
    const setHeaderVar = () => {
      const h = document.getElementById("appHeader")?.offsetHeight || 56;
      document.documentElement.style.setProperty("--app-header-h", `${h}px`);
    };
    addEventListener("resize", setHeaderVar);
    addEventListener("turbo:load", setHeaderVar);
    document.readyState === "loading" ? addEventListener("DOMContentLoaded", setHeaderVar) : setHeaderVar();
  </script>
  ```
* `app\views\workspaces\_sidebar.html.erb`

  ```erb
  <ul class="list-group list-group-flush w-100 me-2">
    <% menu = [
      { path: ->{ dummy_path }, icon: "calculator",   label: "積立計算",     roles: [:member, :admin, :guest], turbo: true },
      { path: ->{ dummy_path }, icon: "filetype-py",  label: "Pythonテスト", roles: [:admin],                  turbo: true },
      { path: ->{ dummy_path }, icon: "journal-text", label: "お知らせ",     roles: [:member, :admin],         turbo: true },
      { path: ->{ dummy_path }, icon: "shield-lock",  label: "管理",         roles: [:admin],                  turbo: true }
    ] %>

    <% roles_now =
        if current_user&.guest?
          [:guest]
        elsif current_user&.admin?
          [:admin]
        else
          [:member]
        end %>

    <% menu.each do |item| %>
      <% next unless (item[:roles] & roles_now).any? %>
      <% link_opts = item[:turbo] ? { data:{ turbo_frame:"main"} } : {} %>
      <li class="list-group-item">
        <%= link_to item[:path].call, { class:"mb-2 link-underline link-underline-opacity-0 link-opacity-25-hover fw-medium" }.merge(link_opts) do %>
          <i class="bi bi-<%= item[:icon] %> fs-4" aria-label="<%= item[:label] %>"></i>
          <span class="ms-3"><%= item[:label] %></span>
        <% end %>
      </li>
    <% end %>
  </ul>
  ```

* `app\assets\stylesheets\application.scss`：追記

  ```scss
  @use "components/workspaces";
  ```

* `app\assets\stylesheets\components\workspaces.scss`

  ```scss
  /* XL 以上で “カラム独立スクロール & サイドバー静的化” */
  @media (min-width: 1200px) {
    /* 1) body をスクロールさせない */
    html, body { height: 100%; }
    body { overflow: hidden; }

    /* 2) ヘッダー直下のラッパはビューポート高 - ヘッダー高で固定 */
    .app-shell {
      min-height: calc(100dvh - var(--app-header-h, 56px));
      height:     calc(100dvh - var(--app-header-h, 56px));
      overflow: hidden; /* ここではスクロールさせない */
    }

    /* 3) 各カラムが自前でスクロール（＝貼り付き） */
    .app-col {
      height: 100%;
      overflow: auto;
      overscroll-behavior: contain;
    }

    /* 4) サイドバーを静的化（offcanvas解除） */
    #appSidebar.offcanvas-xl {
      position: static;
      transform: none !important;
      visibility: visible !important;
      display: block !important;
      width: var(--bs-offcanvas-width, 260px);
      flex: 0 0 var(--bs-offcanvas-width, 260px);
      z-index: auto;
    }
    #appSidebar .offcanvas-header { display: none !important; }
  }
  @media (min-width: 1400px) {
    .app-ads-col { width: 280px; flex: 0 0 280px; }
  }
  ```

* `app\javascript\controllers\workspaces\sidebar_controller.js`

  ```javascript
  import { Controller } from "@hotwired/stimulus"
  import { Offcanvas } from "bootstrap"

  /*
    サイドバー内のリンクをクリックしたら即座にオフキャンバスを閉じる。
    - XL未満（offcanvas動作中）のみ動く
    - data-turbo-frame が指定されたリンク（既定: main）のときに閉じる
    - 既存の遷移は止めない（preventDefaultしない）
  */
  export default class extends Controller {
    static values = {
      frame: { type: String, default: "main" },      // 対象の Turbo Frame
      target: { type: String, default: "#appSidebar"} // Offcanvas 要素
    }

    connect() {
      this.onClick = this.onClick.bind(this)
      // サイドバー全体でデリゲート
      this.element.addEventListener("click", this.onClick, true) // captureにして先に拾う
    }

    disconnect() {
      this.element.removeEventListener("click", this.onClick, true)
    }

    onClick(e) {
      // クリックされた a[href] を特定
      const a = e.target.closest("a[href]")
      if (!a || !this.element.contains(a)) return

      // XL以上は静的サイドバーなので何もしない
      if (!window.matchMedia("(max-width: 1199.98px)").matches) return

      // data-turbo-frame の判定（既定は this.frameValue）
      const tf = (a.getAttribute("data-turbo-frame") || "").trim()
      const willUpdateTargetFrame =
        tf ? (tf === this.frameValue) : false

      // 「main を更新するリンク」のみ閉じる（必要なら true にすれば全リンクで閉じる）
      if (!willUpdateTargetFrame) return

      // オフキャンバスを閉じる（表示時のみ）
      const el = document.querySelector(this.targetValue)
      if (!el) return
      const api = Offcanvas.getInstance(el) || new Offcanvas(el)
      if (el.classList.contains("show")) api.hide()
    }
  }
  ```

* `app\controllers\dummies_controller.rb`

    ```ruby
    class DummiesController < ApplicationController
      def show
        render_flash_and_replace(
          template: "dummies/show",
          message: "dummies/showに遷移しました。",
          type: :notice
        )
      end
    end
    ```

* `app\views\dummies\show.html.erb`

  ```erb
  <h1>Dummies#show</h1>
  <p>Find me in app/views/dummies/show.html.erb</p>
  <p>Turbo Frame 内にレンダリングされています。</p>
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

### 11) メール送信設定（Confirmable 動作に必須）

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

    `config/initializers/devise.rb`：追記（本番：開発共通で使用）

    ```ruby
    config.mailer_sender = "no-reply@dolcos-calc.com"
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
  * メール一覧を見るには、以下にアクセスします。  
    （http://localhost:3000/letter_opener）  
    確認メールが一覧表示され、リンクをクリックすると confirmed_at が埋まります。

---

### 12) Minitest対策

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


## これでできること

* `/users/sign_up` で登録 ⇒ **確認メールのリンク**を踏むと有効化
* `/users/sign_in` でログイン（**記憶しますか？** チェック対応）
* `/users/password/new` でパスワード再設定メール送信
* ログイン後は `workspaces#show` に遷移
* Trackable によりサインイン回数／最終ログイン時刻／IP を記録
* ゲストでログイン

