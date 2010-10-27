require File.dirname(__FILE__) + "/config"


# 3.  Obtaining End-User Authorization
class AuthorizationTest < Test::Unit::TestCase
  module Helpers

    def should_redirect_with_error(error)
      should "redirect with error #{error}" do
        # Is 302 redirect
        assert_equal 302, last_response.status
        uri = URI.parse(last_response["Location"])
        # Back to the client host
        assert_equal uri.host, "example.com"
        # With error code query parameter
        query = Rack::Utils.parse_query(uri.query)
        assert_equal error.to_s, query["error"]
        # With state.
        assert_equal "bring this back", query["state"]
      end
    end

    def should_ask_user_for_authorization(&block)
      should "ask user for authorization" do
        assert SimpleApp.end_user_sees
      end
      should "should inform user about client" do
        assert_equal "Iz Awesome", SimpleApp.end_user_sees[:client]
      end
      should "should inform user about scope" do
        assert_equal %w{read write}, SimpleApp.end_user_sees[:scope]
      end
    end

  end
  extend Helpers

  def setup
    super
    @client = Rack::OAuth2::Models::Client.create("Iz Awesome", "http://example.com", "http://example.com/callback")
    @params = { :redirect_uri=>@client.redirect_uri, :client_id=>@client.id, :client_secret=>@client.secret, :response_type=>"token",
                :scope=>"read write", :state=>"bring this back" }
  end

  def request_authorization(changes = nil)
    get "/oauth/authorize?" + Rack::Utils.build_query(@params.merge(changes || {}))
  end


  # Checks before we request user for authorization.
  # 3.2.  Error Response

  context "no redirect URI" do
    setup { request_authorization :redirect_uri=>nil }
    should "return status 400" do
      assert_equal 400, last_response.status
    end
  end

  context "invalid redirect URI" do
    setup { request_authorization :redirect_uri=>"http:not-valid" }
    should "return status 400" do
      assert_equal 400, last_response.status
    end
  end

  context "no client ID" do
    setup { request_authorization :client_id=>nil }
    should_redirect_with_error :invalid_client
  end

  context "invalid client ID" do
    setup { request_authorization :client_id=>"foobar" }
    should_redirect_with_error :invalid_client
  end

  context "client ID but no client" do
    setup { request_authorization :client_id=>"4cc7bc483321e814b8000000" }
    should_redirect_with_error :invalid_client
  end

  context "client ID but no client secret" do
    setup { request_authorization :client_secret=>nil }
    should_redirect_with_error :invalid_client
  end

  context "mismatched redirect URI" do
    setup { request_authorization :redirect_uri=>"http://example.com/oz" }
    should_redirect_with_error :redirect_uri_mismatch
  end

  context "revoked client" do
    setup do
      @client.revoke!
      request_authorization
    end
    should_redirect_with_error :invalid_client
  end

  context "no response type" do
    setup { request_authorization :response_type=>nil }
    should_redirect_with_error :unsupported_response_type
  end

  context "unknown response type" do
    setup { request_authorization :response_type=>"foobar" }
    should_redirect_with_error :unsupported_response_type
  end


  # 3.1.  Authorization Response
  
  context "expecting authorization code" do
    setup do
      @params[:response_type] = "code"
      request_authorization
    end
    should_ask_user_for_authorization

    context "and granted" do
      setup { get "/oauth/authorize/grant" }

      should "redirect" do
        assert_equal 302, last_response.status
      end
      should "redirect back to client" do
        uri = URI.parse(last_response["Location"])
        assert_equal "example.com", uri.host
        assert_equal "/callback", uri.path
      end

      context "redirect URL query parameters" do
        setup { @params = Rack::Utils.parse_query(URI.parse(last_response["Location"]).query) }

        should "include authorization code" do
          assert_match /[a-f0-9]{32}/i, @params["code"]
        end

        should "include original scope" do
          assert_equal "read write", @params["scope"]
        end

        should "include state from requet" do
          assert_equal "bring this back", @params["state"]
        end
      end
    end

    context "and denied" do
      setup { get "/oauth/authorize/deny" }

      should "redirect" do
        assert_equal 302, last_response.status
      end
      should "redirect back to client" do
        uri = URI.parse(last_response["Location"])
        assert_equal "example.com", uri.host
        assert_equal "/callback", uri.path
      end

      context "redirect URL" do
        setup { @params = Rack::Utils.parse_query(URI.parse(last_response["Location"]).query) }

        should "not include authorization code" do
          assert !@params["code"]
        end

        should "include error code" do
          assert_equal "access_denied", @params["error"]
        end

        should "include state from requet" do
          assert_equal "bring this back", @params["state"]
        end
      end
    end
  end


  context "expecting access token" do
    setup do
      @params[:response_type] = "token"
      request_authorization
    end
    should_ask_user_for_authorization

    context "and granted" do
      setup { get "/oauth/authorize/grant" }

      should "redirect" do
        assert_equal 302, last_response.status
      end
      should "redirect back to client" do
        uri = URI.parse(last_response["Location"])
        assert_equal "example.com", uri.host
        assert_equal "/callback", uri.path
      end

      context "redirect URL fragment identifier" do
        setup { @params = Rack::Utils.parse_query(URI.parse(last_response["Location"]).fragment) }

        should "include access token" do
          assert_match /[a-f0-9]{32}/i, @params["access_token"]
        end

        should "include original scope" do
          assert_equal "read write", @params["scope"]
        end

        should "include state from requet" do
          assert_equal "bring this back", @params["state"]
        end
      end
    end

    context "and denied" do
      setup { get "/oauth/authorize/deny" }

      should "redirect" do
        assert_equal 302, last_response.status
      end
      should "redirect back to client" do
        uri = URI.parse(last_response["Location"])
        assert_equal "example.com", uri.host
        assert_equal "/callback", uri.path
      end

      context "redirect URL" do
        setup { @params = Rack::Utils.parse_query(URI.parse(last_response["Location"]).query) }

        should "not include authorization code" do
          assert !@params["code"]
        end

        should "include error code" do
          assert_equal "access_denied", @params["error"]
        end

        should "include state from requet" do
          assert_equal "bring this back", @params["state"]
        end
      end
    end
  end


  # Edge cases

  context "unregistered redirect URI" do
    setup do
      Rack::OAuth2::Models::Client.collection.update({ :_id=>@client._id }, { :$set=>{ :redirect_uri=>nil } })
      request_authorization :redirect_uri=>"http://example.com/oz"
    end
    should_ask_user_for_authorization
  end

end
