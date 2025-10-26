class Users::SessionsController < Devise::SessionsController
  def guest
    user = User.guest
    sign_in(:user, user)
    user.forget_me! if user.respond_to?(:forget_me!)
    session[:guest_user] = true
    redirect_to authenticated_root_path, notice: "ゲストとしてログインしました"
  end
end
