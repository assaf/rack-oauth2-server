require "test/setup"
require "jwt"
require "openssl"


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
        assert_equal scope || "", JSON.parse(last_response.body)["scope"]
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
    get last_response["Location"] if last_response.status == 303
    authorization = last_response.body[/authorization:\s*(\S+)/, 1]
    post "/oauth/grant", :authorization=>authorization
    @code = Rack::Utils.parse_query(URI.parse(last_response["Location"]).query)["code"]
  end

  def request_none(scope = nil)
    basic_authorize client.id, client.secret
    # Note: This grant_type becomes "client_credentials" in version 11 of the OAuth 2.0 spec
    params = { :grant_type=>"none", :scope=>"read write" }
    params[:scope] = scope if scope
    post "/oauth/access_token", params
  end

  def request_access_token(changes = nil)
    params = { :client_id=>client.id, :client_secret=>client.secret, :scope=>"read write",
               :grant_type=>"authorization_code", :code=>@code, :redirect_uri=>client.redirect_uri }.merge(changes || {})
    basic_authorize params.delete(:client_id), params.delete(:client_secret)
    post "/oauth/access_token", params
  end

  def request_with_username_password(username, password, scope = nil)
    basic_authorize client.id, client.secret
    params = { :grant_type=>"password" }
    params[:scope] = scope if scope
    params[:username] = username if username
    params[:password] = password if password
    post "/oauth/access_token", params
  end

  def request_with_assertion(assertion_type, assertion)
    basic_authorize client.id, client.secret
    params = { :grant_type=>"assertion", :scope=>"read write" }
    params[:assertion_type] = assertion_type if assertion_type
    params[:assertion] = assertion if assertion
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
      grant = Server::AccessGrant.create("foo bar", Server.register(:scope=>%w{read write}), "read write", nil)
      request_access_token :code=>grant.code
    end
    should_return_error :invalid_grant
  end

  context "authorization code revoked" do
    setup do
      Server::AccessGrant.from_code(@code).revoke!
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
      @client = Server.register(:display_name=>"No rediret", :scope=>"read write")
      grant = Server::AccessGrant.create("foo bar", client, "read write", nil)
      request_access_token :code=>grant.code, :redirect_uri=>"http://uberclient.dot/oz"
    end
    should_respond_with_access_token
  end

  context "access grant expired" do
    setup do
      Timecop.travel 300 do
        request_access_token
      end
    end
    should_return_error :invalid_grant
  end

  context "access grant spent" do
    setup do
      request_access_token
      request_access_token
    end
    should_return_error :invalid_grant
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
    setup { request_with_username_password "cowbell", "more" }
    should_respond_with_access_token "oauth-admin read write"
  end

  context "given scope" do
    setup { request_with_username_password "cowbell", "more", "read" }
    should_respond_with_access_token "read"
  end

  context "unsupported scope" do
    setup { request_with_username_password "cowbell", "more", "read write math" }
    should_return_error :invalid_scope
  end

  context "authenticator with 4 parameters" do
    setup do
      @old = config.authenticator
      config.authenticator = lambda do |username, password, client_id, scope|
        @client_id = client_id
        @scope = scope
        "Batman"
      end
      request_with_username_password "cowbell", "more", "read"
    end

    should_respond_with_access_token "read"
    should "receive client identifier" do
      assert_equal client.id, @client_id
    end
    should "receive scope" do
      assert_equal %w{read}, @scope
    end

    teardown { config.authenticator = @old }
  end

  # 4.1.3. Assertion

  context "assertion" do
    context "no assertion_type" do
      setup { request_with_assertion nil, "myassertion" }
      should_return_error :invalid_grant
    end

    context "no assertion" do
      setup { request_with_assertion "urn:some:assertion:type", nil }
      should_return_error :invalid_grant
    end
    
    context "assertion_type with callback" do
      setup do
        config.assertion_handler['special_assertion_type'] = lambda do |client, assertion, scope|
          @client = client
          @assertion = assertion
          @scope = scope
          if assertion == 'myassertion'
            "Spiderman"
          else
            nil
          end
        end
        request_with_assertion 'special_assertion_type', 'myassertion'
      end
      
      context "valid credentials" do
        setup { request_with_assertion 'special_assertion_type', 'myassertion' }
        
        should_respond_with_access_token "read write"
        should "receive client" do
          assert_equal client, @client
        end
        should "receieve assertion" do
          assert_equal 'myassertion', @assertion
        end
      end
      
      context "invalid credentials" do
        setup { request_with_assertion 'special_assertion_type', 'dunno' }
        should_return_error :invalid_grant
      end

      teardown { config.assertion_handler['special_assertion_type'] = nil }
    end

    context "unsupported assertion_type" do
      setup { request_with_assertion "urn:some:assertion:type", "myassertion" }
      should_return_error :invalid_grant
    end

    context "JWT" do
      setup {
        @hour_from_now = Time.now.utc.to_i + (60 * 60)
      }
      context "malformed assertion" do
        setup { request_with_assertion "urn:ietf:params:oauth:grant-type:jwt-bearer", "myassertion" }
        should_return_error :invalid_grant
      end

      context "missing principal claim" do
        setup {
          @hmac_issuer = Server.register_issuer(:identifier => "http://www.hmacissuer.com", :hmac_secret => "foo", :notes => "Test HMAC Issuer")
          @claims = {"iss" => @hmac_issuer.identifier, "aud" => "http://www.mycompany.com", "exp" => @hour_from_now}
          jwt_assertion = JWT.encode(@claims, @hmac_issuer.hmac_secret, "HS256")
          request_with_assertion "urn:ietf:params:oauth:grant-type:jwt-bearer", jwt_assertion
        }
        should_return_error :invalid_grant
      end

      context "missing audience claim" do
        setup {
          @hmac_issuer = Server.register_issuer(:identifier => "http://www.hmacissuer.com", :hmac_secret => "foo", :notes => "Test HMAC Issuer")
          @claims = {"iss" => @hmac_issuer.identifier, "prn" => "1234567890", "exp" => @hour_from_now}
          jwt_assertion = JWT.encode(@claims, @hmac_issuer.hmac_secret, "HS256")
          request_with_assertion "urn:ietf:params:oauth:grant-type:jwt-bearer", jwt_assertion
        }
        should_return_error :invalid_grant
      end

      context "missing expiration claim" do
        setup {
          @hmac_issuer = Server.register_issuer(:identifier => "http://www.hmacissuer.com", :hmac_secret => "foo", :notes => "Test HMAC Issuer")
          @claims = {"iss" => @hmac_issuer.identifier, "aud" => "http://www.mycompany.com", "prn" => "1234567890"}
          jwt_assertion = JWT.encode(@claims, "shhh", "HS256")
          request_with_assertion "urn:ietf:params:oauth:grant-type:jwt-bearer", jwt_assertion
        }
        should_return_error :invalid_grant
      end

      context "missing issuer claim" do
        setup {
          @claims = {"aud" => "http://www.mycompany.com", "prn" => "1234567890", "exp" => @hour_from_now}
          jwt_assertion = JWT.encode(@claims, "shhh", "HS256")
          request_with_assertion "urn:ietf:params:oauth:grant-type:jwt-bearer", jwt_assertion
        }
        should_return_error :invalid_grant
      end

      context "unknown issuer" do
        setup {
          @claims = {"iss" => "unknown", "aud" => "http://www.mycompany.com", "prn" => "1234567890", "exp" => @hour_from_now}
          jwt_assertion = JWT.encode(@claims, "shhh", "HS256")
          request_with_assertion "urn:ietf:params:oauth:grant-type:jwt-bearer", jwt_assertion
        }
        should_return_error :invalid_grant
      end

      context "valid HMAC assertion" do
        setup {
          @hmac_issuer = Server.register_issuer(:identifier => "http://www.hmacissuer.com", :hmac_secret => "foo", :notes => "Test HMAC Issuer")
          @claims = {"iss" => @hmac_issuer.identifier, "aud" => "http://www.mycompany.com", "prn" => "1234567890", "exp" => @hour_from_now}
          jwt_assertion = JWT.encode(@claims, @hmac_issuer.hmac_secret, "HS256")
          request_with_assertion "urn:ietf:params:oauth:grant-type:jwt-bearer", jwt_assertion
        }
        should_respond_with_access_token "read write"
      end

      context "valid RSA assertion" do
        setup {
          @private_key = OpenSSL::PKey::RSA.generate(512)
          @rsa_issuer = Server.register_issuer(:identifier => "http://www.rsaissuer.com", :public_key => @private_key.public_key.to_pem, :notes => "Test RSA Issuer")
          @claims = {"iss" => @rsa_issuer.identifier, "aud" => "http://www.mycompany.com", "prn" => "1234567890", "exp" => @hour_from_now}
          jwt_assertion = JWT.encode(@claims, @private_key, "RS256")
          request_with_assertion "urn:ietf:params:oauth:grant-type:jwt-bearer", jwt_assertion
        }
        should_respond_with_access_token "read write"
      end

      context "expired claim set" do
        setup {
          @hmac_issuer = Server.register_issuer(:identifier => "http://www.hmacissuer.com", :hmac_secret => "foo", :notes => "Test HMAC Issuer")
          @claims = {"iss" => @hmac_issuer.identifier, "aud" => "http://www.mycompany.com", "prn" => "1234567890", "exp" => Time.now.utc.to_i - (11 * 60)}
          jwt_assertion = JWT.encode(@claims, @hmac_issuer.hmac_secret, "HS256")
          request_with_assertion "urn:ietf:params:oauth:grant-type:jwt-bearer", jwt_assertion
        }
        should_return_error :invalid_grant
      end

      context "expiration claim within the fudge factor time" do
        setup {
          @hmac_issuer = Server.register_issuer(:identifier => "http://www.hmacissuer.com", :hmac_secret => "foo", :notes => "Test HMAC Issuer")
          @claims = {"iss" => @hmac_issuer.identifier, "aud" => "http://www.mycompany.com", "prn" => "1234567890", "exp" => Time.now.utc.to_i - (9 * 60)}
          jwt_assertion = JWT.encode(@claims, @hmac_issuer.hmac_secret, "HS256")
          request_with_assertion "urn:ietf:params:oauth:grant-type:jwt-bearer", jwt_assertion
        }
        should_respond_with_access_token "read write"
      end

    end
  end


  # 4.2.  Access Token Response

  context "using none" do
    setup { request_none }
    should_respond_with_access_token "read write"
    should "generate a new access token on each request per client_id/client_secret pair" do
      request_none
      token1 = JSON.parse(last_response.body)["access_token"]
      request_none
      token2 = JSON.parse(last_response.body)["access_token"]
      request_none
      token3 = JSON.parse(last_response.body)["access_token"]
      assert_not_equal token1, token2
      assert_not_equal token2, token3
      assert_not_equal token1, token3
    end
  end

  context "using authorization code" do
    setup { request_access_token }
    should_respond_with_access_token "read write"
  end

  context "using username/password" do
    setup { request_with_username_password "cowbell", "more", "read" }
    should_respond_with_access_token "read"
  end
  
end
