$: << File.dirname(__FILE__) + "/lib"
require "rack/oauth2/server"
Rack::OAuth2::Server.database = Mongo::Connection.new["test"]

class Authorize < Sinatra::Base
  register Rack::OAuth2::Sinatra
  get "/oauth/authorize" do
    content_type "text/html"
    <<-HTML
    <h1>#{oauth.client.display_name} wants to access your account.</h1>
    <form action="/oauth/grant" method="post"><button>Let It!</button>
    <input type="hidden" name="auth" value="#{oauth.authorization}">
    </form>
    HTML
  end

  post "/oauth/grant" do
    oauth.grant! params[:auth], "Superman"
  end
end
# NOTE: This client must exist in your database. To get started, run:
#   oauth-server setup --db test
# And enter the URL
#   http://localhost:3000/oauth/admin
# Then plug the client ID/secret you get instead of these values, and run:
#   thin start
#   open http://localhost:3000/oauth/admin
Rack::OAuth2::Server::Admin.set :client_id, "4cd9cbc03321e8367d000001"
Rack::OAuth2::Server::Admin.set :client_secret, "c531191fb208aa34d6b44d6f69e61e97e56abceadb336ebb0f2f5757411a0a19"
Rack::OAuth2::Server::Admin.set :template_url, "http://localhost:3000/accounts/{id}"
app = Rack::Builder.new do
  map "/" do
    run Authorize.new
  end
  map "/oauth/admin" do
    run Rack::OAuth2::Server::Admin.new
  end
end
run app.to_app
