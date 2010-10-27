class SimpleApp < Sinatra::Base
  use Rack::Logger
  use Rack::OAuth2::Server, :restricted_path=>"/private/"
  set :sessions, true

  class << self
    # What we show the end user when requesting authentication.
    attr_accessor :end_user_sees
  end

  get "/oauth/authorize" do
    client = Rack::OAuth2::Models::Client.find(request.env["oauth.client_id"])
    self.class.end_user_sees = { :client=>client.display_name, :scope=>request.env["oauth.scope"] }
    session[:oauth] = request.env["oauth.request"]
  end

  get "/oauth/authorize/grant" do
    request.env["oauth.response"] = session[:oauth]
    request.env["oauth.account_id"] = 491
  end

  get "/oauth/authorize/deny" do
    request.env["oauth.response"] = session[:oauth]
  end
end
