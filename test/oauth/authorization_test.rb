require "test/setup"


# 3.  Obtaining End-User Authorization
class AuthorizationTest < Test::Unit::TestCase
  module Helpers

    def should_redirect_with_error(error)
      should "respond with status code 302 (Found)" do
        assert_equal 302, last_response.status
      end
      should "redirect back to redirect_uri" do
        assert_equal URI.parse(last_response["Location"]).host, "uberclient.dot"
      end
      should "redirect with error code #{error}" do
        assert_equal error.to_s, Rack::Utils.parse_query(URI.parse(last_response["Location"]).query)["error"]
      end
      should "redirect with state parameter" do
        assert_equal "bring this back", Rack::Utils.parse_query(URI.parse(last_response["Location"]).query)["state"]
      end
    end

    def should_ask_user_for_authorization(&block)
      should "inform user about client" do
        response = last_response.body.split("\n").inject({}) { |h,l| n,v = l.split(/:\s*/) ; h[n.downcase] = v ; h }
        assert_equal "UberClient", response["client"]
      end
      should "inform user about scope" do
        response = last_response.body.split("\n").inject({}) { |h,l| n,v = l.split(/:\s*/) ; h[n.downcase] = v ; h }
        assert_equal "read, write", response["scope"]
      end
    end

  end
  extend Helpers

  def setup
    super
    @params = { :redirect_uri=>client.redirect_uri, :client_id=>client.id, :client_secret=>client.secret, :response_type=>"code",
                :scope=>"read write", :state=>"bring this back" }
  end

  def request_authorization(changes = nil)
    get "/oauth/authorize?" + Rack::Utils.build_query(@params.merge(changes || {}))
    get last_response["Location"] if last_response.status == 303
  end

  def authorization
    last_response.body[/authorization:\s*(\S+)/, 1]
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

  context "client ID but no such client" do
    setup { request_authorization :client_id=>"4cc7bc483321e814b8000000" }
    should_redirect_with_error :invalid_client
  end

  context "mismatched redirect URI" do
    setup { request_authorization :redirect_uri=>"http://uberclient.dot/oz" }
    should_redirect_with_error :redirect_uri_mismatch
  end

  context "revoked client" do
    setup do
      client.revoke!
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

  context "unsupported scope" do
    setup do
      request_authorization :scope=>"read write math"
    end
    should_redirect_with_error :invalid_scope
  end


  # 3.1.  Authorization Response
  
  context "expecting authorization code" do
    setup do
      @params[:response_type] = "code"
      request_authorization
    end
    should_ask_user_for_authorization

    context "and granted" do
      setup { post "/oauth/grant", :authorization=>authorization }

      should "redirect" do
        assert_equal 302, last_response.status
      end
      should "redirect back to client" do
        uri = URI.parse(last_response["Location"])
        assert_equal "uberclient.dot", uri.host
        assert_equal "/callback", uri.path
      end

      context "redirect URL query parameters" do
        setup { @return = Rack::Utils.parse_query(URI.parse(last_response["Location"]).query) }

        should "include authorization code" do
          assert_match /[a-f0-9]{32}/i, @return["code"]
        end

        should "include original scope" do
          assert_equal "read write", @return["scope"]
        end

        should "include state from requet" do
          assert_equal "bring this back", @return["state"]
        end
      end
    end

    context "and denied" do
      setup { post "/oauth/deny", :authorization=>authorization }

      should "redirect" do
        assert_equal 302, last_response.status
      end
      should "redirect back to client" do
        uri = URI.parse(last_response["Location"])
        assert_equal "uberclient.dot", uri.host
        assert_equal "/callback", uri.path
      end

      context "redirect URL" do
        setup { @return = Rack::Utils.parse_query(URI.parse(last_response["Location"]).query) }

        should "not include authorization code" do
          assert !@return["code"]
        end

        should "include error code" do
          assert_equal "access_denied", @return["error"]
        end

        should "include state from requet" do
          assert_equal "bring this back", @return["state"]
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
      setup { post "/oauth/grant", :authorization=>authorization }

      should "redirect" do
        assert_equal 302, last_response.status
      end
      should "redirect back to client" do
        uri = URI.parse(last_response["Location"])
        assert_equal "uberclient.dot", uri.host
        assert_equal "/callback", uri.path
      end

      context "redirect URL fragment identifier" do
        setup { @return = Rack::Utils.parse_query(URI.parse(last_response["Location"]).fragment) }

        should "include access token" do
          assert_match /[a-f0-9]{32}/i, @return["access_token"]
        end

        should "include original scope" do
          assert_equal "read write", @return["scope"]
        end

        should "include state from requet" do
          assert_equal "bring this back", @return["state"]
        end
      end
    end

    context "and denied" do
      setup { post "/oauth/deny", :authorization=>authorization }

      should "redirect" do
        assert_equal 302, last_response.status
      end
      should "redirect back to client" do
        uri = URI.parse(last_response["Location"])
        assert_equal "uberclient.dot", uri.host
        assert_equal "/callback", uri.path
      end

      context "redirect URL" do
        setup { @return = Rack::Utils.parse_query(URI.parse(last_response["Location"]).fragment) }

        should "not include authorization code" do
          assert !@return["code"]
        end

        should "include error code" do
          assert_equal "access_denied", @return["error"]
        end

        should "include state from requet" do
          assert_equal "bring this back", @return["state"]
        end
      end
    end
  end


  # Using existing authorization request

  context "with authorization request" do
    setup do
      request_authorization
      get "/oauth/authorize?" + Rack::Utils.build_query(:authorization=>authorization)
    end

    should_ask_user_for_authorization
  end

  context "with invalid authorization request" do
    setup do
      request_authorization
      get "/oauth/authorize?" + Rack::Utils.build_query(:authorization=>"foobar")
    end

    should "return status 400" do
      assert_equal 400, last_response.status
    end
  end

  context "with revoked authorization request" do
    setup do
      request_authorization
      response = last_response.body.split("\n").inject({}) { |h,l| n,v = l.split(/:\s*/) ; h[n.downcase] = v ; h }
      client.revoke!
      get "/oauth/authorize?" + Rack::Utils.build_query(:authorization=>response["authorization"])
    end

    should "return status 400" do
      assert_equal 400, last_response.status
    end
  end


  # Edge cases

  context "unregistered redirect URI" do
    setup do
      Rack::OAuth2::Server::Client.collection.update({ :_id=>client._id }, { :$set=>{ :redirect_uri=>nil } })
      request_authorization :redirect_uri=>"http://uberclient.dot/oz"
    end
    should_ask_user_for_authorization
  end

end
