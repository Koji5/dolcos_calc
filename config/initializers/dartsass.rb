# config/initializers/dartsass.rb
Rails.application.configure do
  # ビルド定義（既にあればそのままでOK）
  config.dartsass.builds = {
    "app/assets/stylesheets/application.scss" => "app/assets/builds/application.css"
  }

  # ★ 重要: node_modules を Sass の検索パスに追加
  config.dartsass.load_paths << Rails.root.join("node_modules")
end
