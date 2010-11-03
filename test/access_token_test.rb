require File.dirname(__FILE__) + "/setup"


# 5.  Accessing a Protected Resource
class AccessTokenTest < Test::Unit::TestCase
  module Helpers

    def should_return_resource(content)
      should "respond with status 200" do
        assert_equal 200, last_response.status
      end
      should "respond with resource name" do
        assert_equal content, last_response.body
      end
    end

    def should_fail_authentication(error = nil)
      should "respond with status 401 (Unauthorized)" do
        assert_equal 401, last_response.status
      end
      should "respond with authentication method OAuth" do
        assert_equal "OAuth", last_response["WWW-Authenticate"].split.first
      end
      should "respond with realm" do
        assert_match " realm=\"example.org\"", last_response["WWW-Authenticate"] 
      end
      if error
        should "respond with error code #{error}" do
          assert_match " error=\"#{error}\"", last_response["WWW-Authenticate"]
        end
      else
        should "not respond with error code" do
          assert !last_response["WWW-Authenticate"]["error="]
        end
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
    code = Rack::Utils.parse_query(URI.parse(last_response["Location"]).query)["code"]
    # Get access token
    basic_authorize client.id, client.secret
    post "/oauth/access_token", :scope=>"read write", :grant_type=>"authorization_code", :code=>code, :redirect_uri=>client.redirect_uri
    @token = JSON.parse(last_response.body)["access_token"]
    header "Authorization", nil
  end

  def with_token(token = @token)
    header "Authorization", "OAuth #{token}"
  end


  # 5.  Accessing a Protected Resource

  context "public resource" do
    context "no authorization" do
      setup { get "/public" }
      should_return_resource "HAI"
    end

    context "with authorization" do
      setup do
        with_token
        get "/public"
      end
      should_return_resource "HAI from Superman"
    end
  end

  context "private resource" do
    context "no authorization" do
      setup { get "/private" }
      should_fail_authentication
    end

    context "HTTP authentication" do
      context "valid token" do
        setup do
          with_token
          get "/private"
        end
        should_return_resource "Shhhh"
      end

      context "unknown token" do
        setup do
          with_token "dingdong"
          get "/private"
        end
        should_fail_authentication :invalid_token
      end

      context "revoked HTTP token" do
        setup do
          Rack::OAuth2::Server::AccessToken.from_token(@token).revoke!
          with_token
          get "/private"
        end
        should_fail_authentication :invalid_token
      end

      context "revoked client" do
        setup do
          client.revoke!
          with_token
          get "/private"
        end
        should_fail_authentication :invalid_token
      end
    end

    # 5.1.2.  URI Query Parameter
    
    context "query parameter" do
      context "valid token" do
        setup { get "/private?oauth_token=#{@token}" }
        should_return_resource "Shhhh"
      end

      context "invalid token" do
        setup { get "/private?oauth_token=dingdong" }
        should_fail_authentication :invalid_token
      end
    end
  end
  
  context "POST" do
    context "no authorization" do
      setup { post "/change" }
      should_fail_authentication
    end

    context "HTTP authentication" do
      context "valid token" do
        setup do
          with_token
          post "/change"
        end
        should_return_resource "Woot!"
      end

      context "unknown token" do
        setup do
          with_token "dingdong"
          post "/change"
        end
        should_fail_authentication :invalid_token
      end

    end

    # 5.1.3.  Form-Encoded Body Parameter

    context "body parameter" do
      context "valid token" do
        setup { post "/change", :oauth_token=>@token }
        should_return_resource "Woot!"
      end

      context "invalid token" do
        setup { post "/change", :oauth_token=>"dingdong" }
        should_fail_authentication :invalid_token
      end
    end
  end


  context "insufficient scope" do
    context "valid token" do
      setup { get "/calc?oauth_token=#@token" }

      should "respond with status 403 (Forbidden)" do
        assert_equal 403, last_response.status
      end
      should "respond with authentication method OAuth" do
        assert_equal "OAuth", last_response["WWW-Authenticate"].split.first
      end
      should "respond with realm" do
        assert_match " realm=\"example.org\"", last_response["WWW-Authenticate"] 
      end
      should "respond with error code insufficient_scope" do
        assert_match " error=\"insufficient_scope\"", last_response["WWW-Authenticate"]
      end
      should "respond with scope name" do
        assert_match " scope=\"math\"", last_response["WWW-Authenticate"]
      end
    end
  end


  context "setting resource" do
    context "authenticated" do
      setup do
        with_token
        get "/user"
      end

      should "render user name" do
        assert_equal "Superman", last_response.body
      end
    end

    context "not authenticated" do
      setup do
        get "/user"
      end

      should "not render user name" do
        assert  last_response.body.empty?
      end
    end
  end

  context "list tokens" do
    setup do
      @other = Rack::OAuth2::Server::AccessToken.get_token_for("foobar", "read", client.id).token
      get "/list_tokens"
    end

    should "return access token" do
      assert_contains last_response.body.split, @token
    end

    should "not return other resource's token" do
      assert !last_response.body.split.include?(@other)
    end
  end


  context "get_token_for" do
    should "return two different tokens for two different clients" do
      myapp = Rack::OAuth2::Server::AccessToken.get_token_for("Superman", "read write", "myapp")
      yourapp = Rack::OAuth2::Server::AccessToken.get_token_for("Superman", "read write", "yourapp")
      assert myapp.token != yourapp.token
    end
    should "return two different tokens for two different identities" do
      me = Rack::OAuth2::Server::AccessToken.get_token_for("Superman", "read write", "myapp")
      you = Rack::OAuth2::Server::AccessToken.get_token_for("Batman", "read write", "myapp")
      assert me.token != you.token
    end
    should "return two different tokens for two different scope" do
      write = Rack::OAuth2::Server::AccessToken.get_token_for("Superman", "read write", "myapp")
      math = Rack::OAuth2::Server::AccessToken.get_token_for("Superman", "read math", "myapp")
      assert write.token != math.token
    end
    should "return same tokens regardless of order of scope" do
      one = Rack::OAuth2::Server::AccessToken.get_token_for("Superman", "read write math", "myapp")
      two = Rack::OAuth2::Server::AccessToken.get_token_for("Superman", "math write read", "myapp")
      assert_equal one.token, two.token
    end
  end
end
