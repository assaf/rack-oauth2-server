require "rack"
require "rack/oauth2/models"
require "rack/oauth2/server/errors"
require "rack/oauth2/server/utils"
require "rack/oauth2/server/helper"


module Rack
  module OAuth2

    # Implements an OAuth 2 Authorization Server, based on http://tools.ietf.org/html/draft-ietf-oauth-v2-10
    class Server

      # Same as gem version number.
      VERSION = IO.read(::File.expand_path("../../../VERSION", ::File.dirname(__FILE__)))

      class << self
        # Return AuthRequest from authorization request handle.
        def get_auth_request(authorization)
          AuthRequest.find(authorization)
        end

        # Returns Client from client identifier.
        def get_client(client_id)
          Client.find(client_id)
        end

        # Returns AccessToken from token.
        def get_access_token(token)
          AccessToken.from_token(token)
        end

        # Returns all AccessTokens for an identity.
        def list_access_tokens(identity)
          AccessToken.from_identity(identity)
        end

      end

      # Options are:
      # - :access_token_path -- Path for requesting access token. By convention
      #   defaults to /oauth/access_token.
      # - :authenticator -- For username/password authorization. A block that
      #   receives the credentials and returns identity string (e.g. user ID) or
      #   nil.
      # - :authorization_types -- Array of supported authorization types.
      #   Defaults to ["code", "token"], and you can change it to just one of
      #   these names.
      # - :authorize_path --  Path for requesting end-user authorization. By
      #   convention defaults to /oauth/authorize.
      # - :database -- Mongo::DB instance.
      # - :host -- Only check requests sent to this host.
      # - :path -- Only check requests for resources under this path.
      # - :param_authentication -- If true, supports authentication using
      #   query/form parameters.
      # - :realm -- Authorization realm that will show up in 401 responses.
      #   Defaults to use the request host name.
      # - :logger -- The logger to use. Under Rails, defaults to use the Rails
      #   logger.  Will use Rack::Logger if available.
      Options = Struct.new(:access_token_path, :authenticator, :authorization_types,
        :authorize_path, :database, :host, :param_authentication, :path, :realm, :logger)

      def initialize(app, options = Options.new, &authenticator)
        @app = app
        @options = options
        @options.authenticator ||= authenticator
        @options.access_token_path ||= "/oauth/access_token"
        @options.authorize_path ||= "/oauth/authorize"
        @options.authorization_types ||=  %w{code token}
        @options.param_authentication = false
      end

      # @see Options
      attr_reader :options

      def call(env)
        request = OAuthRequest.new(env)
        return @app.call(env) if options.host && options.host != request.host
        return @app.call(env) if options.path && request.path.index(options.path) != 0

        begin
          # Use options.database if specified.
          org_database, Server.database = Server.database, options.database || Server.database
          logger = options.logger || env["rack.logger"]

          # 3.  Obtaining End-User Authorization
          # Flow starts here.
          return request_authorization(request, logger) if request.path == options.authorize_path
          # 4.  Obtaining an Access Token
          return respond_with_access_token(request, logger) if request.path == options.access_token_path

          # 5.  Accessing a Protected Resource
          if request.authorization
            # 5.1.1.  The Authorization Request Header Field
            token = request.credentials if request.oauth?
          elsif options.param_authentication && !request.GET["oauth_verifier"] # Ignore OAuth 1.0 callbacks
            # 5.1.2.  URI Query Parameter
            # 5.1.3.  Form-Encoded Body Parameter
            token = request.GET["oauth_token"] || request.POST["oauth_token"]
          end

          if token
            begin
              access_token = AccessToken.from_token(token)
              raise InvalidTokenError if access_token.nil? || access_token.revoked
              raise ExpiredTokenError if access_token.expires_at && access_token.expires_at <= Time.now.utc
              request.env["oauth.access_token"] = token
              request.env["oauth.identity"] = access_token.identity
              logger.info "Authorized #{access_token.identity}" if logger
            rescue OAuthError=>error
              # 5.2.  The WWW-Authenticate Response Header Field
              logger.info "HTTP authorization failed #{error.code}" if logger
              return unauthorized(request, error)
            rescue =>ex
              logger.info "HTTP authorization failed #{ex.message}" if logger
              return unauthorized(request)
            end

            # We expect application to use 403 if request has insufficient scope,
            # and return appropriate WWW-Authenticate header.
            response = @app.call(env)
            if response[0] == 403
              scopes = Utils.normalize_scopes(response[1]["oauth.no_scope"])
              challenge = 'OAuth realm="%s", error="insufficient_scope", scope="%s"' % [(options.realm || request.host), scopes.join(" ")]
              response[1]["WWW-Authenticate"] = challenge
              return response
            else
              return response
            end
          else
            response = @app.call(env)
            if response[1] && response[1].delete("oauth.no_access")
              # OAuth access required.
              return unauthorized(request)
            elsif response[1] && response[1]["oauth.authorization"]
              # 3.  Obtaining End-User Authorization
              # Flow ends here.
              return authorization_response(response, logger)
            else
              return response
            end
          end
        ensure
          Server.database = org_database
        end
      end

    protected

      # Get here for authorization request. Check the request parameters and
      # redirect with an error if we find any issue. Otherwise, create a new
      # authorization request, set in oauth.request and pass control to the
      # application.
      def request_authorization(request, logger)
        state = request.GET["state"]
        begin

          if request.GET["authorization"]
            auth_request = self.class.get_auth_request(request.GET["authorization"]) rescue nil
            if !auth_request || auth_request.revoked
              logger.error "Invalid authorization request #{auth_request}" if logger
              return bad_request("Invalid authorization request")
            end
            response_type = auth_request.response_type # Needed for error handling
            client = self.class.get_client(auth_request.client_id)
            # Pass back to application, watch for 403 (deny!)
            logger.info "Request #{auth_request.id}: Client #{client.display_name} requested #{auth_request.response_type} with scope #{auth_request.scope}" if logger
            request.env["oauth.authorization"] = auth_request.id.to_s
            response = @app.call(request.env)
            raise AccessDeniedError if response[0] == 403
            return response

          else

            # 3.  Obtaining End-User Authorization
            begin
              redirect_uri = Utils.parse_redirect_uri(request.GET["redirect_uri"])
            rescue InvalidRequestError=>error
              logger.error "Authorization request with invalid redirect_uri: #{request.GET["redirect_uri"]} #{error.message}" if logger
              return bad_request(error.message)
            end

            # 3. Obtaining End-User Authorization
            response_type = request.GET["response_type"].to_s # Need this first, for error handling
            client = get_client(request)
            raise RedirectUriMismatchError unless client.redirect_uri.nil? || client.redirect_uri == redirect_uri.to_s
            raise UnsupportedResponseTypeError unless options.authorization_types.include?(response_type)
            requested_scope = Utils.normalize_scopes(request.GET["scope"])
            allowed_scopes = client.scopes
            raise InvalidScopeError unless (requested_scope - allowed_scopes).empty?
            # Create object to track authorization request and let application
            # handle the rest.
            auth_request = AuthRequest.create(client.id, requested_scope, redirect_uri.to_s, response_type, state)
            uri = URI.parse(request.url)
            uri.query = "authorization=#{auth_request.id.to_s}"
            return [303, { "Location"=>uri.to_s }, []]
          end
        rescue OAuthError=>error
          logger.error "Authorization request error: #{error.code} #{error.message}" if logger
          params = { :error=>error.code, :error_description=>error.message, :state=>state }
          if response_type == "token"
            redirect_uri.fragment = Rack::Utils.build_query(params)
          else # response type is code, or invalid
            params = Rack::Utils.parse_query(redirect_uri.query).merge(params)
            redirect_uri.query = Rack::Utils.build_query(params)
          end
          return redirect_to(redirect_uri)
        end
      end

      # Get here on completion of the authorization. Authorization response in
      # oauth.response either grants or denies authroization. In either case, we
      # redirect back with the proper response.
      def authorization_response(response, logger)
        status, headers, body = response
        auth_request = self.class.get_auth_request(headers["oauth.authorization"])
        redirect_uri = URI.parse(auth_request.redirect_uri)
        if status == 403
          auth_request.deny!
        else
          auth_request.grant! headers["oauth.identity"]
        end
        # 3.1.  Authorization Response
        if auth_request.response_type == "code"
          if auth_request.grant_code
            logger.info "Request #{auth_request.id}: Client #{auth_request.client_id} granted access code #{auth_request.grant_code}" if logger
            params = { :code=>auth_request.grant_code, :scope=>auth_request.scope.join(" "), :state=>auth_request.state }
          else
            logger.info "Request #{auth_request.id}: Client #{auth_request.client_id} denied authorization" if logger
            params = { :error=>:access_denied, :state=>auth_request.state }
          end
          params = Rack::Utils.parse_query(redirect_uri.query).merge(params)
          redirect_uri.query = Rack::Utils.build_query(params)
        else # response type if token
          if auth_request.access_token
            logger.info "Request #{auth_request.id}: Client #{auth_request.client_id} granted access token #{auth_request.access_token}" if logger
            params = { :access_token=>auth_request.access_token, :scope=>auth_request.scope.join(" "), :state=>auth_request.state }
          else
            logger.info "Request #{auth_request.id}: Client #{auth_request.client_id} denied authorization" if logger
            params = { :error=>:access_denied, :state=>auth_request.state }
          end
          redirect_uri.fragment = Rack::Utils.build_query(params)
        end
        return redirect_to(redirect_uri)
      end

      # 4.  Obtaining an Access Token
      def respond_with_access_token(request, logger)
        return [405, { "Content-Type"=>"application/json" }, ["POST only"]] unless request.post?
        # 4.2.  Access Token Response
        begin
          client = get_client(request)
          case request.POST["grant_type"]
          when "authorization_code"
            # 4.1.1.  Authorization Code
            grant = AccessGrant.from_code(request.POST["code"])
            raise InvalidGrantError unless grant && client.id == grant.client_id
            raise InvalidGrantError unless grant.redirect_uri.nil? || grant.redirect_uri == Utils.parse_redirect_uri(request.POST["redirect_uri"]).to_s
            access_token = grant.authorize!
          when "password"
            raise UnsupportedGrantType unless options.authenticator
            # 4.1.2.  Resource Owner Password Credentials
            username, password = request.POST.values_at("username", "password")
            raise InvalidGrantError unless username && password
            identity = options.authenticator.call(username, password)
            raise InvalidGrantError unless identity
            requested_scope = Utils.normalize_scopes(request.POST["scope"])
            allowed_scopes = client.scopes
            raise InvalidScopeError unless (requested_scope - allowed_scopes).empty?
            access_token = AccessToken.get_token_for(identity, requested_scope, client.id)
          else raise UnsupportedGrantType
          end
          logger.info "Access token #{access_token.token} granted to client #{client.display_name}, identity #{access_token.identity}" if logger
          response = { :access_token=>access_token.token }
          response[:scope] = access_token.scope.join(" ")
          return [200, { "Content-Type"=>"application/json", "Cache-Control"=>"no-store" }, response.to_json]
          # 4.3.  Error Response
        rescue OAuthError=>error
          logger.error "Access token request error: #{error.code} #{error.message}" if logger
          return unauthorized(request, error) if InvalidClientError === error && request.basic?
          return [400, { "Content-Type"=>"application/json", "Cache-Control"=>"no-store" }, 
                  { :error=>error.code, :error_description=>error.message }.to_json]
        end
      end

      # Returns client from request based on credentials. Raises
      # InvalidClientError if client doesn't exist or secret doesn't match.
      def get_client(request)
        # 2.1  Client Password Credentials
        if request.basic?
          client_id, client_secret = request.credentials
        elsif request.form_data?
          client_id, client_secret = request.POST.values_at("client_id", "client_secret")
        else
          client_id, client_secret = request.GET.values_at("client_id", "client_secret")
        end
        client = self.class.get_client(client_id)
        raise InvalidClientError unless client && client.secret == client_secret
        raise InvalidClientError if client.revoked
        return client
      rescue BSON::InvalidObjectId
        raise InvalidClientError
      end

      # Rack redirect response. The argument is typically a URI object.
      def redirect_to(uri)
        return [302, { "Location"=>uri.to_s }, []]
      end

      def bad_request(message)
        return [400, { "Content-Type"=>"text/plain" }, [message]]
      end

      # Returns WWW-Authenticate header.
      def unauthorized(request, error = nil)
        challenge = 'OAuth realm="%s"' % (options.realm || request.host)
        challenge << ', error="%s", error_description="%s"' % [error.code, error.message] if error
        return [401, { "WWW-Authenticate"=>challenge }, []]
      end

      # Wraps Rack::Request to expose Basic and OAuth authentication
      # credentials.
      class OAuthRequest < Rack::Request

        AUTHORIZATION_KEYS = %w{HTTP_AUTHORIZATION X-HTTP_AUTHORIZATION X_HTTP_AUTHORIZATION}

        # Returns authorization header.
        def authorization
          @authorization ||= AUTHORIZATION_KEYS.inject(nil) { |auth, key| auth || @env[key] }
        end

        # True if authentication scheme is OAuth.
        def oauth?
          authorization[/^oauth/i] if authorization
        end

        # True if authentication scheme is Basic.
        def basic?
          authorization[/^basic/i] if authorization
        end

        # If Basic auth, returns username/password, if OAuth, returns access
        # token.
        def credentials
          basic? ? authorization.gsub(/\n/, "").split[1].unpack("m*").first.split(/:/, 2) :
          oauth? ? authorization.gsub(/\n/, "").split[1] : nil
        end
      end

    end

  end
end
