require "sinatra/base"
require "json"
require "rack/oauth2/sinatra"

module Rack
  module OAuth2
    class Admin < ::Sinatra::Base

      # Need client ID to get access token to access this console.
      set :client_id, nil
      # Need client secret to get access token to access this console.
      set :client_secret, nil
      # Use this URL to authorize access to this console. If not set, goes to
      # /oauth/authorize.
      set :authorize, nil

      # Number of tokens to return in each page.
      set :tokens_per_page, 100
      set :public, ::File.dirname(__FILE__) + "/admin"
      mime_type :js, "text/javascript"
      mime_type :tmpl, "text/x-jquery-template"


      helpers Rack::OAuth2::Sinatra::Helpers
      extend Rack::OAuth2::Sinatra

      # Force HTTPS except for development environment.
      before do
        redirect request.url.sub(/^http:/, "https:") unless request.scheme == "https"
      end unless development?


      # -- Static content --

      # It's a single-page app, this is that single page.
      get "/oauth/admin" do
        send_file settings.public + "/views/index.html"
      end

      # Service JavaScript, CSS and jQuery templates from the gem.
      %w{js css views}.each do |path|
        get "/oauth/admin/#{path}/:name" do
          send_file settings.public + "/#{path}/" + params[:name]
        end
      end


      # -- Getting an access token --

      # To get an OAuth token, you need client ID and secret, two values we
      # didn't pass on to the JavaScript code, so it has no way to request
      # authorization directly. Instead, it redirects to this URL which in turn
      # redirects to the authorization endpoint. This redirect does accept the
      # state parameter, which will be returned after authorization.
      get "/oauth/admin/authorize" do
        redirect_uri = "#{request.scheme}://#{request.host}:#{request.port}/oauth/admin"
        query = { :client_id=>settings.client_id, :client_secret=>settings.client_secret, :state=>params[:state],
                  :response_type=>"token", :scope=>"oauth-admin", :redirect_uri=>redirect_uri }
        auth_url = settings.authorize || "#{request.scheme}://#{request.host}:#{request.port}/oauth/authorize"
        redirect "#{auth_url}?#{Rack::Utils.build_query(query)}"
      end


      # -- API --
     
      # All API paths are under /oauth/admin/api.
      oauth_required "/oauth/admin/api", :scope=>"oauth-admin"

      get "/oauth/admin/api/clients" do
        content_type "application/json"
        json = { :list=>Server::Client.all.map { |client| client_as_json(client) },
                 :tokens=>{ :total=>Server::AccessToken.count, :week=>Server::AccessToken.count(:days=>7),
                            :revoked=>Server::AccessToken.count(:days=>7, :revoked=>true) } }
        json.to_json
      end

      post "/oauth/admin/api/clients" do
        begin
          client = Server::Client.create(validate_params(params))
          redirect "/oauth/admin/api/client/#{client.id}"
        rescue
          halt 400, $!.message
        end
      end

      get "/oauth/admin/api/client/:id" do
        content_type "application/json"
        client = Server::Client.find(params[:id])
        json = client_as_json(client, true)

        page = (params[:page] || 1).to_i
        offset = (page - 1) * settings.tokens_per_page
        total = Server::AccessToken.count(:client_id=>client.id)
        tokens = Server::AccessToken.for_client(params[:id], offset, settings.tokens_per_page)
        json[:tokens] = { :list=>tokens.map { |token| token_as_json(token) } }
        json[:tokens][:total] = total
        json[:tokens][:next] = "/oauth/admin/client/#{params[:id]}?page=#{page + 1}" if total > page * settings.tokens_per_page
        json[:tokens][:previous] = "/oauth/admin/client/#{params[:id]}?page=#{page - 1}" if page > 1
        json[:tokens][:total] = Server::AccessToken.count(:client_id=>client.id)
        json[:tokens][:week] = Server::AccessToken.count(:client_id=>client.id, :days=>7)
        json[:tokens][:revoked] = Server::AccessToken.count(:client_id=>client.id, :days=>7, :revoked=>true)

        json.to_json
      end

      put "/oauth/admin/api/client/:id" do
        client = Server::Client.find(params[:id])
        begin
          client.update validate_params(params)
          redirect "/oauth/admin/api/client/#{client.id}"
        rescue
          halt 400, $!.message
        end
      end

      post "/oauth/admin/api/client/:id/revoke" do
        client = Server::Client.find(params[:id])
        client.revoke!
        200
      end

      post "/oauth/admin/api/token/:token/revoke" do
        token = Server::AccessToken.from_token(params[:token])
        token.revoke!
        200
      end

      helpers do
        def validate_params(params)
          display_name = params[:displayName].to_s.strip
          halt 400, "Missing display name" if display_name.empty?
          link = URI.parse(params[:link]).normalize rescue nil
          halt 400, "Link is not a URL (must be http://....)" unless link
          halt 400, "Link must be an absolute URL with HTTP/S scheme" unless link.absolute? && %{http https}.include?(link.scheme)
          redirect_uri = URI.parse(params[:redirectUri]).normalize rescue nil
          halt 400, "Redirect URL is not a URL (must be http://....)" unless redirect_uri
          halt 400, "Redirect URL must be an absolute URL with HTTP/S scheme" unless redirect_uri.absolute? && %{http https}.include?(redirect_uri.scheme)
          image_url = URI.parse(params[:imageUrl]).normalize rescue nil
          halt 400, "Image URL is not a URL (must be http://....)" unless image_url
          halt 400, "Image URL must be an absolute URL with HTTP scheme" unless image_url.absolute? && image_url.scheme == "http"
          { :display_name=>display_name, :link=>link.to_s, :image_url=>image_url.to_s, :redirect_uri=>redirect_uri.to_s }
        end

        def client_as_json(client, with_stats = false)
          { "id"=>client.id.to_s, "secret"=>client.secret, :redirectUri=>client.redirect_uri,
            :displayName=>client.display_name, :link=>client.link, :imageUrl=>client.image_url,
            :url=>"/oauth/admin/api/client/#{client.id}", :revoke=>"/oauth/admin/api/client/#{client.id}/revoke",
            :created=>client.created_at, :revoked=>client.revoked }
          # TODO: add statistics when retrieving single client
        end

        def token_as_json(token)
          { :token=>token.token, :identity=>token.identity, :scope=>token.scope, :created=>token.created_at,
            :expired=>token.expires_at, :revoked=>token.revoked, :revoke=>"/oauth/admin/api/token/#{token.token}/revoke" }
        end
      end

    end
  end
end
