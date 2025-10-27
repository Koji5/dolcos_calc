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

  resource :dummy, only: :show
  resource :workspace, only: :show

  if Rails.env.development?
    # メール一覧が見られる UI（http://localhost:3000/letter_opener）
    mount LetterOpenerWeb::Engine, at: "/letter_opener"
  end
end
