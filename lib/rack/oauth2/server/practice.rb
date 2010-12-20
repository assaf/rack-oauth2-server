require "rack/oauth2/server/admin"

module Rack
  module OAuth2
    class Server
      
      class Practice < ::Sinatra::Base
        register Rack::OAuth2::Sinatra

        get "/" do
          <<-HTML
<html>
  <head>
    <title>OAuth 2.0 Practice Server</title>
  </head>
  <body>
    <h1>Welcome to OAuth 2.0 Practice Server</h1>
    <p>This practice server is for testing your OAuth 2.0 client library.</p>
    <dl>
      <dt>Authorization end-point:</dt>
      <dd>http://#{request.host}:#{request.port}/oauth/authorize</dd>
      <dt>Access token end-point:<//dt>
      <dd>http://#{request.host}:#{request.port}/oauth/access_token</dd>
      <dt>Resource requiring authentication:</dt>
      <dd>http://#{request.host}:#{request.port}/secret</dd>
      <dt>Resource requiring authorization and scope "sudo":</dt>
      <dd>http://#{request.host}:#{request.port}/make</dd>
    </dl>
    <p>The scope can be "nobody", "sudo", "oauth-admin" or combination of the three.</p>
    <p>You can manage client applications and tokens from the <a href="/oauth/admin">OAuth console</a>.</p>
  </body>
</html>
          HTML
        end

        # -- Simple authorization --

        get "/oauth/authorize" do
          <<-HTML
<html>
  <head>
    <title>OAuth 2.0 Practice Server</title>
  </head>
  <body>
    <h1><a href="#{oauth.client.link}">#{oauth.client.display_name}</a> wants to access your account with the scope #{oauth.scope.join(", ")}</h1>
    <form action="/oauth/grant" method="post" style="display:inline-block">
      <button>Grant</button>
      <input type="hidden" name="authorization" value="#{oauth.authorization}">
    </form>
    <form action="/oauth/deny" method="post" style="display:inline-block">
      <button>Deny</button>
      <input type="hidden" name="authorization" value="#{oauth.authorization}">
    </form>
  </body>
</html>
          HTML
        end
        post "/oauth/grant" do
          oauth.grant! "Superman"
        end
        post "/oauth/deny" do
          oauth.deny!
        end

        # -- Protected resources --

        oauth_required "/secret"
        get "/private" do
          "You're awesome!"
        end

        oauth_required "/make", :scope=>"sudo"
        get "/write" do
          "Sandwhich"
        end
      end
    end
  end
end
