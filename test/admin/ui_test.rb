require "test/setup"

class AdminUiTest < Test::Unit::TestCase
  context "/" do
    setup { get "/oauth/admin" }
    should "return OK" do
      assert_equal 200, last_response.status
    end
    should "return HTML page" do
      assert_match "<html>", last_response.body
    end
  end
end
