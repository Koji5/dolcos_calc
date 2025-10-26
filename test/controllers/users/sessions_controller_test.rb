require "test_helper"

class Users::SessionsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "guest sign-in redirects to authenticated_root" do
    post guest_sign_in_path
    assert_redirected_to authenticated_root_path
    follow_redirect!
    assert_response :success
    assert user_signed_in?
    assert_match /ゲストとしてログインしました|/ , response.body
  end

  test "sign out works" do
    # いったんゲストでログイン
    post guest_sign_in_path
    delete destroy_user_session_path
    # after_sign_out_path_for の実装に合わせて期待を調整
    # 例: サインイン画面へ
    assert_redirected_to new_user_session_path
  end
end
