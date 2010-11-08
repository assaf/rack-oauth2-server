require "test/setup"


# 4.  Obtaining an Access Token
class AccessGrantTest < Test::Unit::TestCase
  module Helpers

    def should_return_error(error)
      should "respond with status 400 (Bad Request)" do
        assert_equal 400, last_response.status
      end
      should "respond with JSON document" do
        assert_equal "application/json", last_response.content_type
      end
      should "respond with error code #{error}" do
        assert_equal error.to_s, JSON.parse(last_response.body)["error"]
      end
    end

    def should_respond_with_authentication_error(error)
      should "respond with status 401 (Unauthorized)" do
        assert_equal 401, last_response.status
      end
      should "respond with authentication method OAuth" do
        assert_equal "OAuth", last_response["WWW-Authenticate"].split.first
      end
      should "respond with realm" do
        assert_match " realm=\"example.org\"", last_response["WWW-Authenticate"] 
      end
      should "respond with error code #{error}" do
        assert_match " error=\"#{error}\"", last_response["WWW-Authenticate"]
      end
    end

    def should_respond_with_access_token(scope = "read write")
      should "respond with status 200" do
        assert_equal 200, last_response.status
      end
      should "respond with JSON document" do
        assert_equal "application/json", last_response.content_type
      end
      should "respond with cache control no-store" do
        assert_equal "no-store", last_response["Cache-Control"]
      end
      should "not respond with error code" do
        assert JSON.parse(last_response.body)["error"].nil?
      end
      should "response with access token" do
        assert_match /[a-f0-9]{32}/i, JSON.parse(last_response.body)["access_token"]
      end
      should "response with scope" do
        assert_equal scope, JSON.parse(last_response.body)["scope"]
      end
    end


  end
  extend Helpers

  def setup
    super
    # Get authorization code.
    params = { :redirect_uri=>client.redirect_uri, :client_id=>client.id, :client_secret=>client.secret, :response_type=>"code",
               :scope=>"read write", :state=>"bring this back" }
    get "/oauth/authorize?" + Rack::Utils.build_query(params)
    post "/oauth/grant"
    @code = Rack::Utils.parse_query(URI.parse(last_response["Location"]).query)["code"]
  end

  def request_access_token(changes = nil)
    params = { :client_id=>client.id, :client_secret=>client.secret, :scope=>"read write",
               :grant_type=>"authorization_code", :code=>@code, :redirect_uri=>client.redirect_uri }.merge(changes || {})
    basic_authorize params.delete(:client_id), params.delete(:client_secret)
    post "/oauth/access_token", params
  end

  def request_with_username_password(username, password, scope = "read write")
    basic_authorize client.id, client.secret
    params = { :grant_type=>"password", :scope=>scope }
    params[:username] = username if username
    params[:password] = password if password
    post "/oauth/access_token", params
  end


  # 4.  Obtaining an Access Token
  
  context "GET request" do
    setup { get "/oauth/access_token" }

    should "respond with status 405 (Method Not Allowed)" do
      assert_equal 405, last_response.status
    end
  end

  context "no client ID" do
    setup { request_access_token :client_id=>nil }
    should_respond_with_authentication_error :invalid_client
  end

  context "invalid client ID" do
    setup { request_access_token :client_id=>"foobar" }
    should_respond_with_authentication_error :invalid_client
  end

  context "client ID but no such client" do
    setup { request_access_token :client_id=>"4cc7bc483321e814b8000000" }
    should_respond_with_authentication_error :invalid_client
  end

  context "no client secret" do
    setup { request_access_token :client_secret=>nil }
    should_respond_with_authentication_error :invalid_client
  end

  context "wrong client secret" do
    setup { request_access_token :client_secret=>"plain wrong" }
    should_respond_with_authentication_error :invalid_client
  end

  context "client revoked" do
    setup do
      client.revoke!
      request_access_token
    end
    should_respond_with_authentication_error :invalid_client
  end

  context "unsupported grant type" do
    setup { request_access_token :grant_type=>"bogus" }
    should_return_error :unsupported_grant_type
  end


  # 4.1.1.  Authorization Code

  context "no authorization code" do
    setup { request_access_token :code=>nil }
    should_return_error :invalid_grant
  end
  
  context "unknown authorization code" do
    setup { request_access_token :code=>"unknown" }
    should_return_error :invalid_grant
  end

  context "authorization code for different client" do
    setup do
      grant = Rack::OAuth2::Server::AccessGrant.create("foo bar", "read write", "4cc7bc483321e814b8000000", nil)
      request_access_token :code=>grant.code
    end
    should_return_error :invalid_grant
  end

  context "authorization code revoked" do
    setup do
      Rack::OAuth2::Server::AccessGrant.from_code(@code).revoke!
      request_access_token
    end
    should_return_error :invalid_grant
  end

  context "mistmatched redirect URI" do
    setup { request_access_token :redirect_uri=>"http://uberclient.dot/oz" }
    should_return_error :invalid_grant
  end

  context "no redirect URI to match" do
    setup do
      grant = Rack::OAuth2::Server::AccessGrant.create("foo bar", "read write", client.id, nil)
      request_access_token :code=>grant.code, :redirect_uri=>"http://uberclient.dot/oz"
    end
    should_respond_with_access_token
  end


  # 4.1.2.  Resource Owner Password Credentials

  context "no username" do
    setup { request_with_username_password nil, "more" }
    should_return_error :invalid_grant
  end  
  
  context "no password" do
    setup { request_with_username_password nil, "more" }
    should_return_error :invalid_grant
  end

  context "not authorized" do
    setup { request_with_username_password "cowbell", "less" }
    should_return_error :invalid_grant
  end

  context "no scope specified" do
    setup { request_with_username_password "cowbell", "more", nil }
    should_respond_with_access_token nil
  end

  context "unsupported scope" do
    setup { request_with_username_password "cowbell", "more", "read write math" }
    should_return_error :invalid_scope
  end

  # 4.2.  Access Token Response

  context "using authorization code" do
    setup { request_access_token }
    should_respond_with_access_token "read write"
  end

  context "using username/password" do
    setup { request_with_username_password "cowbell", "more", "read" }
    should_respond_with_access_token "read"
  end
  
end
