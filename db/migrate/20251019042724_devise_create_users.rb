# frozen_string_literal: true

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
