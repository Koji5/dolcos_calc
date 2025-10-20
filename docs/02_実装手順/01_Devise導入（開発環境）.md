# Devise導入

Rails 8 + Hotwire（Turbo）／Importmap 構成のまま、Devise 本流のネーミングに合わせて、  
* サインアップ
* ログイン
* ログアウト
* メール確認（Confirmable）
* パスワード再設定（Recoverable）
* 記憶しますか？（Rememberable）
* Trackable  

を有効化し、ログイン後はダミーページへ遷移する最小構成を一気に作ります。
（コマンドはすべて **docker compose 経由** です）

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

* 開発環境のメール URL 既定（確認メール用）
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
   class DeviseCreateUsers < ActiveRecord::Migration[7.2]
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

### 5) User モデルの有効モジュールを宣言

* `app/models/user.rb`

   ```ruby
   class User < ApplicationRecord
     devise :database_authenticatable, :registerable,
            :recoverable, :rememberable, :validatable,
            :confirmable, :trackable
   end
   ```

### 6) ルーティングとダミーページ

* まずダミー画面用のシンプルなコントローラを用意：

   ```bash
   docker compose exec app rails g controller Dashboard show
   docker compose exec app rails g controller Home top
   ```

* `config/routes.rb`

   ```ruby
   Rails.application.routes.draw do
     devise_for :users

     # ログイン後はダッシュボードへ
     authenticated :user do
       root to: "dashboard#show", as: :authenticated_root
     end

     # 未ログイン時のトップ（ログイン/サインアップ導線用）
     root to: "pages#home"
   end
   ```

* ログイン後の遷移をさらに明示したい場合：

  `app/controllers/application_controller.rb`

   ```ruby
   class ApplicationController < ActionController::Base
     private
     def after_sign_in_path_for(resource)
       authenticated_root_path
     end
   end
   ```

### 7) ビューとフォーム

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
   <%= form_with model: resource, scope: resource_name, url: registration_path(resource_name) do |f| %>
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
   > Bootstrap トーストでフラッシュを出したい方針（#9）があるので、`application.html.erb` のフラッシュ表示は後でトースト化。

### 8) メール送信（Confirmable 動作に必須）

* 開発ではまず **実メール不要** で試すのがおすすめ（例：letter_opener_web）。本番は SMTP を設定。ここでは最小だけ：

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
   docker compose up -d --force-recreate ap
   ```

* http://localhost:3000/letter_opener に確認メールが一覧表示され、リンクをクリックすると confirmed_at が埋まります。
---

### 9) Minitest対策

`confirmable` を入れているので、**テストでは「確認済みユーザーでログイン」**してから `get dashboard_show_url` を叩く。
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
   `test/controllers/dashboard_controller_test.rb`

   ```rb
   require "test_helper"

   class DashboardControllerTest < ActionDispatch::IntegrationTest
     setup do
       @user = users(:one)
     end

     test "should get show when signed in" do
       sign_in @user
       get dashboard_show_url
       assert_response :success
     end
   end
   ```

## これでできること

* `/users/sign_up` で登録 ⇒ **確認メールのリンク**を踏むと有効化
* `/users/sign_in` でログイン（**記憶しますか？** チェック対応）
* `/users/password/new` でパスワード再設定メール送信
* ログイン後は `Dashboard#show`（ダミー）に遷移
* Trackable によりサインイン回数／最終ログイン時刻／IP を記録

---

## よくあるハマりどころ（回避策）

* **Turbo でリダイレクトが変になる** → `config.navigational_formats` 設定済みか確認。
* **確認メールが来ない** → `default_url_options` とメール送信設定（開発/本番）を確認。
* **form_for が混じる** → 生成済み Devise ビューを順次 `form_with` に置換（上のサンプルをベースに）。

---

必要なら、このあと **Bootstrap トーストのフラッシュ**、**日本語化(i18n)**、**メール文面の調整**、**レイアウト統一** まで一気に仕上げます。
