class PagesController < ApplicationController
  def home
  end

  # ダミー遷移先（とりあえず画面が変わるだけ）
  def dummy
    render plain: "Coming soon..."
  end
end
