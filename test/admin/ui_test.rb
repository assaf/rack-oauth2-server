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

  context "force SSL" do
    setup { Server::Admin.force_ssl = true }

    context "HTTP request" do
      setup { get "/oauth/admin" }

      should "redirect to HTTPS" do
        assert_equal 302, last_response.status
        assert_match "https://example.org/oauth/admin", last_response.location
      end
    end

    context "HTTPS request" do
      setup { get "https://example.org/oauth/admin" }

      should "serve request" do
        assert_equal 200, last_response.status
        assert_match "<html>", last_response.body
      end
    end

    teardown { Server::Admin.force_ssl = false }
  end

end
