require "test_helper"

class Users::SessionsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "guest sign-in redirects to authenticated_root" do
    post guest_sign_in_path
    assert_redirected_to authenticated_root_path

    follow_redirect!
    assert_response :success

    # ログイン必須ページにアクセスできることをもって“ログイン済”の証拠にする
    get workspace_url
    assert_response :success
  end

  test "sign out works (default)" do
    post guest_sign_in_path
    delete destroy_user_session_path
    assert_redirected_to unauthenticated_root_path # ＝ "/"
  end

  test "sign out with redirect=sign_in goes to sign-in" do
    post guest_sign_in_path
    delete destroy_user_session_path(redirect: "sign_in")
    assert_redirected_to new_user_session_path
  end
end
