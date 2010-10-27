class SimpleApp < Sinatra::Base
  use Rack::Logger
  use Rack::OAuth2::Server, :restricted_path=>"/restricted", :scopes=>%w{read write} do |username, password|
    "Superman" if username == "cowbell" && password == "more"
  end
  set :sessions, true

  class << self
    # What we show the end user when requesting authentication.
    attr_accessor :end_user_sees
  end

  before do
    request.extend  Rack::OAuth2::Server::RequestHelpers
    response.extend Rack::OAuth2::Server::ResponseHelpers
    @account = "Superman" if request.oauth_resource
  end


  # 3.  Obtaining End-User Authorization

  get "/oauth/authorize" do
    self.class.end_user_sees = { :client=>request.oauth_client.display_name,
                                 :scope=>request.oauth_scope }
    session["oauth.request"] = request.oauth_request
  end

  post "/oauth/grant" do
    response.oauth_grant! session["oauth.request"], "bathtub"
  end

  post "/oauth/deny" do
    response.oauth_deny! session["oauth.request"]
  end


  # 5.  Accessing a Protected Resource

  get "/public" do
    "HAI"
  end

  get "/private" do
    if @account
      "Shhhh"
    else
      response.oauth_no_access!
    end
  end

  post "/change" do
    if @account
      "Woot!"
    else
      response.oauth_no_access!
    end
  end

  get "/calc" do
    response.oauth_no_access! "math" unless request.oauth_scope.include?("math")
  end
  
  get "/restricted" do
    if @account
      "VIPs only"
    else
      response.oauth_no_access!
    end
  end
end
