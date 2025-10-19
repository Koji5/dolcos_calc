Rails.application.routes.draw do
  get "dashboard/show"
  devise_for :users
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # ログイン後はダッシュボードへ
  authenticated :user do
    root to: "dashboard#show", as: :authenticated_root
  end

  # Defines the root path route ("/")
  # root "posts#index"

  # 未ログイン時のトップ（ログイン/サインアップ導線用）
  root "pages#home"

  # ひとまずダミー（後で実装する想定）
#  get  "/sign_up", to: "pages#dummy", as: :sign_up
#  get  "/login",   to: "pages#dummy", as: :login
  get  "/guest",   to: "pages#dummy", as: :guest_mode

  if Rails.env.development?
    # メール一覧が見られる UI（http://localhost:3000/letter_opener）
    mount LetterOpenerWeb::Engine, at: "/letter_opener"
  end
end
