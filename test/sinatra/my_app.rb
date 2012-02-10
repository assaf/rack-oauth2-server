require "rack/oauth2/sinatra"

class MyApp < Sinatra::Base
  use Rack::Logger
  set :sessions, true
  set :show_exceptions, false

  register Rack::OAuth2::Sinatra
  oauth.authenticator = lambda do |username, password|
    "Batman" if username == "cowbell" && password == "more"
  end
  oauth.host = "example.org"
  oauth.database = DATABASE
  oauth.collection_prefix = "oauth2_prefix"

  # 3.  Obtaining End-User Authorization
 
  before "/oauth/*" do 
    halt oauth.deny! if oauth.scope.include?("time-travel") # Only Superman can do that
  end

  get "/oauth/authorize" do
    "client: #{oauth.client.display_name}\nscope: #{oauth.scope.join(", ")}\nauthorization: #{oauth.authorization}"
  end

  post "/oauth/grant" do
    oauth.grant! "Batman"
  end

  post "/oauth/deny" do
    oauth.deny!
  end


  # 5.  Accessing a Protected Resource

  before { @user = oauth.identity if oauth.authenticated? }

  get "/public" do
    if oauth.authenticated?
      "HAI from #{oauth.identity}"
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
    oauth.list_access_tokens("Batman").map(&:token).join(" ")
  end
  
end
