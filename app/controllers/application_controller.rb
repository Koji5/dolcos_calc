class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # ユーザー切替時の処理
  def after_sign_out_path_for(_resource_or_scope)
    case params[:redirect]
    when "sign_in" then new_user_session_path
    when "sign_up" then new_user_registration_path
    else                unauthenticated_root_path
    end
  end
end
