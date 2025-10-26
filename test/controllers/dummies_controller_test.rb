require "test_helper"

class DummiesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in @user
  end
  test "should get show" do
    get dummy_url
    assert_response :success
  end
end
