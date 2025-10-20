require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      email: "u@example.com",
      password: "Passw0rd!",
      password_confirmation: "Passw0rd!",
      confirmed_at: Time.current  # ← confirmable 対策（これが重要）
    )
  end

  test "should get show when signed in" do
    sign_in @user            # ← ここでログイン
    get dashboard_show_url
    assert_response :success
  end
end

