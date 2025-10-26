require "test_helper"

class DummiesControllerTest < ActionDispatch::IntegrationTest
  test "should get show" do
    get dummies_show_url
    assert_response :success
  end
end
