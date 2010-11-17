require "sinatra/base"
require "json"
require "rack/oauth2/server"
require "rack/oauth2/sinatra"

module Rack
  module OAuth2
    class Server
      class Admin < ::Sinatra::Base

        class << self

          # Rack module that mounts the specified class on the specified path,
          # and passes all other request to the application.
          class Mount
            class << self
              def mount(klass, path)
                @klass = klass
                @path = path
                @match = /^#{Regexp.escape(path)}(\/.*|$)?/
              end

              attr_reader :klass, :path, :match
            end

            def initialize(app)
              @pass = app
              @admin = self.class.klass.new
            end

            def call(env)
              path = env["PATH_INFO"].to_s
              script_name = env['SCRIPT_NAME']
              if path =~ self.class.match && rest = $1
                env.merge! "SCRIPT_NAME"=>(script_name + self.class.path), "PATH_INFO"=>rest
                return @admin.call(env)
              else
                return @pass.call(env)
              end
            end
          end

          # Returns Rack handle that mounts Admin on the specified path, and
          # forwards all other requests back to the application.
          #
          # @param [String, nil] path The path to mount on, defaults to
          # /oauth/admin
          # @return [Object] Rack module
          #
          # @example To include Web admin in Rails 2.x app:
          #   config.middleware.use Rack::OAuth2::Server::Admin.mount
          def mount(path = "/oauth/admin")
            mount = Class.new(Mount)
            mount.mount Admin, "/oauth/admin"
            mount
          end

        end


        # Client application identified, require to authenticate.
        set :client_id, nil
        # Client application secret, required to authenticate.
        set :client_secret, nil
        # Endpoint for requesing authorization, defaults to /oauth/admin.
        set :authorize, nil
        # Will map an access token identity into a URL in your application,
        # using the substitution value "{id}", e.g.
        # "http://example.com/users/#{id}")
        set :template_url, nil
        # Forces all requests to use HTTPS (true by default except in
        # development mode).
        set :force_ssl, !development?
        # Common scope shown and added by default to new clients.
        set :scope, []


        set :logger, defined?(::Rails) && ::Rails.logger
        # Number of tokens to return in each page.
        set :tokens_per_page, 100
        set :public, ::File.dirname(__FILE__) + "/../admin"
        set :method_override, true
        mime_type :js, "text/javascript"
        mime_type :tmpl, "text/x-jquery-template"

        register Rack::OAuth2::Sinatra

        # Force HTTPS except for development environment.
        before do
          redirect request.url.sub(/^http:/, "https:") if settings.force_ssl && request.scheme != "https"
        end


        # -- Static content --

        # It's a single-page app, this is that single page.
        get "/" do
          send_file settings.public + "/views/index.html"
        end

        # Service JavaScript, CSS and jQuery templates from the gem.
        %w{js css views}.each do |path|
          get "/#{path}/:name" do
            send_file settings.public + "/#{path}/" + params[:name]
          end
        end


        # -- Getting an access token --

        # To get an OAuth token, you need client ID and secret, two values we
        # didn't pass on to the JavaScript code, so it has no way to request
        # authorization directly. Instead, it redirects to this URL which in turn
        # redirects to the authorization endpoint. This redirect does accept the
        # state parameter, which will be returned after authorization.
        get "/authorize" do
          redirect_uri = "#{request.scheme}://#{request.host}:#{request.port}#{request.script_name}"
          query = { :client_id=>settings.client_id, :client_secret=>settings.client_secret, :state=>params[:state],
                    :response_type=>"token", :scope=>"oauth-admin", :redirect_uri=>redirect_uri }
          auth_url = settings.authorize || "#{request.scheme}://#{request.host}:#{request.port}/oauth/authorize"
          redirect "#{auth_url}?#{Rack::Utils.build_query(query)}"
        end


        # -- API --
       
        oauth_required "/api/clients", "/api/client/:id", "/api/client/:id/revoke", "/api/token/:token/revoke", :scope=>"oauth-admin"

        get "/api/clients" do
          content_type "application/json"
          json = { :list=>Server::Client.all.map { |client| client_as_json(client) },
                   :scope=>Server::Utils.normalize_scope(settings.scope),
                   :history=>"#{request.script_name}/api/clients/history",
                   :tokens=>{ :total=>Server::AccessToken.count, :week=>Server::AccessToken.count(:days=>7),
                              :revoked=>Server::AccessToken.count(:days=>7, :revoked=>true) } }
          json.to_json
        end

        get "/api/clients/history" do
          content_type "application/json"
          { :data=>Server::AccessToken.historical }.to_json
        end

        post "/api/clients" do
          begin
            client = Server::Client.create(validate_params(params))
            redirect "#{request.script_name}/api/client/#{client.id}"
          rescue
            halt 400, $!.message
          end
        end

        get "/api/client/:id" do
          content_type "application/json"
          client = Server::Client.find(params[:id])
          json = client_as_json(client, true)

          page = [params[:page].to_i, 1].max
          offset = (page - 1) * settings.tokens_per_page
          total = Server::AccessToken.count(:client_id=>client.id)
          tokens = Server::AccessToken.for_client(params[:id], offset, settings.tokens_per_page)
          json[:tokens] = { :list=>tokens.map { |token| token_as_json(token) } }
          json[:tokens][:total] = total
          json[:tokens][:page] = page
          json[:tokens][:next] = "#{request.script_name}/client/#{params[:id]}?page=#{page + 1}" if total > page * settings.tokens_per_page
          json[:tokens][:previous] = "#{request.script_name}/client/#{params[:id]}?page=#{page - 1}" if page > 1
          json[:tokens][:total] = Server::AccessToken.count(:client_id=>client.id)
          json[:tokens][:week] = Server::AccessToken.count(:client_id=>client.id, :days=>7)
          json[:tokens][:revoked] = Server::AccessToken.count(:client_id=>client.id, :days=>7, :revoked=>true)

          json.to_json
        end

        get "/api/client/:id/history" do
          content_type "application/json"
          client = Server::Client.find(params[:id])
          { :data=>Server::AccessToken.historical(:client_id=>client.id) }.to_json
        end

        put "/api/client/:id" do
          client = Server::Client.find(params[:id])
          begin
            client.update validate_params(params)
            redirect "#{request.script_name}/api/client/#{client.id}"
          rescue
            halt 400, $!.message
          end
        end

        delete "/api/client/:id" do
          Server::Client.delete(params[:id])
          200
        end

        post "/api/client/:id/revoke" do
          client = Server::Client.find(params[:id])
          client.revoke!
          200
        end

        post "/api/token/:token/revoke" do
          token = Server::AccessToken.from_token(params[:token])
          token.revoke!
          200
        end

        helpers do
          def validate_params(params)
            display_name = params[:displayName].to_s.strip
            halt 400, "Missing display name" if display_name.empty?
            link = URI.parse(params[:link].to_s.strip).normalize rescue nil
            halt 400, "Link is not a URL (must be http://....)" unless link
            halt 400, "Link must be an absolute URL with HTTP/S scheme" unless link.absolute? && %{http https}.include?(link.scheme)
            redirect_uri = URI.parse(params[:redirectUri].to_s.strip).normalize rescue nil
            halt 400, "Redirect URL is not a URL (must be http://....)" unless redirect_uri
            halt 400, "Redirect URL must be an absolute URL with HTTP/S scheme" unless
              redirect_uri.absolute? && %{http https}.include?(redirect_uri.scheme)
            unless params[:imageUrl].nil? || params[:imageUrl].to_s.empty?
              image_url = URI.parse(params[:imageUrl].to_s.strip).normalize rescue nil
              halt 400, "Image URL must be an absolute URL with HTTP/S scheme" unless
                image_url.absolute? && %{http https}.include?(image_url.scheme)
            end
            scope = Server::Utils.normalize_scope(params[:scope])
            { :display_name=>display_name, :link=>link.to_s, :image_url=>image_url.to_s,
              :redirect_uri=>redirect_uri.to_s, :scope=>scope, :notes=>params[:notes] }
          end

          def client_as_json(client, with_stats = false)
            { "id"=>client.id.to_s, "secret"=>client.secret, :redirectUri=>client.redirect_uri,
              :displayName=>client.display_name, :link=>client.link, :imageUrl=>client.image_url,
              :notes=>client.notes, :scope=>client.scope,
              :url=>"#{request.script_name}/api/client/#{client.id}",
              :revoke=>"#{request.script_name}/api/client/#{client.id}/revoke",
              :history=>"#{request.script_name}/api/client/#{client.id}/history",
              :created=>client.created_at, :revoked=>client.revoked }
          end

          def token_as_json(token)
            { :token=>token.token, :identity=>token.identity, :scope=>token.scope, :created=>token.created_at,
              :expired=>token.expires_at, :revoked=>token.revoked,
              :link=>settings.template_url && settings.template_url.gsub("{id}", token.identity),
              :revoke=>"#{request.script_name}/api/token/#{token.token}/revoke" }
          end
        end

      end
    end
  end
end
