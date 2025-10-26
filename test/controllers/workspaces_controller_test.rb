require "test_helper"

class WorkspacesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in @user
  end
  test "should get show" do
    get workspace_url
    assert_response :success
  end
end
