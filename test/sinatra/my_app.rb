require "rack/oauth2/sinatra"

class MyApp < Sinatra::Base
  use Rack::Logger
  set :sessions, true

  register Rack::OAuth2::Sinatra
  oauth[:scopes] = %w{read write}
  oauth[:authenticator] = lambda do |username, password|
    "Superman" if username == "cowbell" && password == "more"
  end
  oauth[:database] = DATABASE


  # 3.  Obtaining End-User Authorization

  get "/oauth/authorize" do
    session["oauth.authorization"] = oauth.authorization
    "client: #{oauth.client.display_name}\nscope: #{oauth.scope.join(", ")}"
  end

  post "/oauth/grant" do
    oauth.grant! session["oauth.authorization"], "Superman"
  end

  post "/oauth/deny" do
    oauth.deny! session["oauth.authorization"]
  end


  # 5.  Accessing a Protected Resource

  before { @user = oauth.resource if oauth.authenticated? }

  get "/public" do
    if oauth.authenticated?
      "HAI from #{oauth.resource}"
    else
      "HAI"
    end
  end

  oauth_required "/private", "/change"

  get "/private" do
    "Shhhh"
  end

  post "/change" do
    "Woot!"
  end

  oauth_required "/calc", :scope=>"math"

  get "/calc" do
  end

  get "/user" do
    @user
  end

  get "/list_tokens" do
    oauth.list_access_tokens("Superman").map(&:token).join(" ")
  end
  
end

