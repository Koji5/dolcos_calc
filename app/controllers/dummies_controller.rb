class DummiesController < ApplicationController
  def show
    render_flash_and_replace(
      template: "dummies/show",
      message: "dummies/showに遷移しました。",
      type: :notice
    )
  end
end
