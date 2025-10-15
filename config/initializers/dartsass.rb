# config/initializers/dartsass.rb
Rails.application.configure do
  # ビルド定義（既にあればそのままでOK）
  config.dartsass.builds = {
    "app/assets/stylesheets/application.scss" => "app/assets/builds/application.css"
  }
end
