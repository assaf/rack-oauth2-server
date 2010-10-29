require "rack/oauth2/models"
require "rack/oauth2/server/errors"
require "rack/oauth2/server/utils"
require "rack/oauth2/server/version"
require "rack/oauth2/server/request_helpers"
require "rack/oauth2/server/response_helpers"


module Rack
  module OAuth2

    # Implements an OAuth 2 Authorization Server, based on http://tools.ietf.org/html/draft-ietf-oauth-v2-10
    class Server

      def initialize(app, options = {}, &authenticator)
        @app, @authenticator = app, authenticator
        { :access_token_path=>"/oauth/access_token",
          :authorize_path=>"/oauth/authorize",
          :supported_authorization_types=>%w{code token} }.merge(options).each do |key, value|
          instance_variable_set :"@#{key}", value
        end
      end

      # Path for requesting access token, defaults to /oauth/access_token.
      attr_accessor :access_token_path
      # Path for requesting end-user authorization, defaults to
      # /oauth/authorize.
      attr_accessor :authorize_path
      # Supported authorization types:
      # * code -- Client can request authorization code
      # * token -- Client can request access token
      # You can change this if you don't want to support authorization code, or
      # want to require obtaining authorization code first (i.e. don't allow token).
      #
      # Defaults to [code, token].
      attr_accessor :supported_authorization_types
      # All request within this path require authentication. For example, to
      # require authentication on /api/v1/project, /api/v2/task and all other
      # resources there, set restricted_path to /api/v1/.
      attr_accessor :restricted_path
      # Authorization realm. 
      attr_accessor :realm
      # Array listing all supported scopes, e.g. %w{read write}.
      attr_accessor :scopes
      # Logger to use, otherwise looks for rack.logger.
      attr_accessor :logger

      def call(env)
        logger = @logger || env["rack.logger"]
        request = OAuthRequest.new(env)

        # 3.  Obtaining End-User Authorization
        # Flow starts here.
        return request_authorization(request, logger) if request.path == authorize_path
        # 4.  Obtaining an Access Token
        return respond_with_access_token(request, logger) if request.path == access_token_path

        # 5.  Accessing a Protected Resource
        if request.authorization
          # 5.1.1.  The Authorization Request Header Field
          access_token = request.credentials if request.oauth?
        else
          # 5.1.2.  URI Query Parameter
          # 5.1.3.  Form-Encoded Body Parameter
          access_token = request.GET["oauth_token"] || request.POST["oauth_token"]
        end

        if access_token
          begin
            token = Models::AccessToken.from_token(access_token)
            raise InvalidTokenError if token.nil? || token.revoked
            raise ExpiredTokenError if token.expires_at && token.expires_at <= Time.now.utc
            request.env["oauth.resource"] = token.resource
            request.env["oauth.scope"] = token.scope.to_s.split
            request.env["oauth.client_id"] = token.client_id.to_s
            logger.info "Authorized #{token.resource}" if logger
          rescue Error=>error
            # 5.2.  The WWW-Authenticate Response Header Field
            logger.info "HTTP authorization failed #{error.code}" if logger
            return unauthorized(request, error)
          rescue =>ex
            logger.info "HTTP authorization failed #{ex.message}" if logger
            return unauthorized(request)
          end
        elsif restricted_path && request.path.index(restricted_path) == 0
          logger.info "HTTP authorization header missing OAuth access token" if logger
          return unauthorized(request, InvalidTokenError.new)
        end

        response = @app.call(env)
        if response[1] && scope = response[1]["oauth.no_access"]
          # 5.2.  The WWW-Authenticate Response Header Field
          if scope.empty?
            return unauthorized(request)
          else
            scope = scope.join(" ") if scope.respond_to?(:join)
            challenge = 'OAuth realm="%s", error="insufficient_scope", scope="%s"' % [(realm || request.host), scope]
            return [403, { "WWW-Authenticate"=>challenge }, []]
          end
        elsif response[1] && response[1]["oauth.request"]
          # 3.  Obtaining End-User Authorization
          # Flow ends here.
          return authorization_response(response[1], logger)
        else
          return response
        end
      end

    protected

      # Get here for authorization request. Check the request parameters and
      # redirect with an error if we find any issue. Otherwise, create a new
      # authorization request, set in oauth.request and pass control to the
      # application.
      def request_authorization(request, logger)
        # 3.  Obtaining End-User Authorization
        begin
          redirect_uri = Utils.parse_redirect_uri(request.GET["redirect_uri"])
        rescue InvalidRequestError=>error
          logger.error "Authorization request with invalid redirect_uri: #{request.GET["redirect_uri"]} #{error.message}" if logger
          return bad_request(error.message)
        end
        state = request.GET["state"]

        begin
          # 3. Obtaining End-User Authorization
          client = get_client(request)
          raise RedirectUriMismatchError unless client.redirect_uri.nil? || client.redirect_uri == redirect_uri.to_s
          requested_scope = request.GET["scope"].to_s.split.uniq.join(" ")
          response_type = request.GET["response_type"].to_s
          raise UnsupportedResponseTypeError unless supported_authorization_types.include?(response_type)
          if scopes
            allowed_scopes = scopes.respond_to?(:split) ? scopes.split : scopes
            raise InvalidScopeError unless requested_scope.split.all? { |v| allowed_scopes.include?(v) }
          end
          # Create object to track authorization request and let application
          # handle the rest.
          auth_request = Models::AuthRequest.create(client.id, requested_scope, redirect_uri.to_s, response_type, state)
          request.env["oauth.request"] = auth_request.id.to_s
          request.env["oauth.client_id"] = client.id.to_s
          request.env["oauth.scope"] = requested_scope.split
          logger.info "Request #{auth_request.id}: Client #{client.display_name} requested #{response_type} with scope #{requested_scope}" if logger
          return @app.call(request.env)
        rescue Error=>error
          logger.error "Authorization request error: #{error.code} #{error.message}" if logger
          params = Rack::Utils.parse_query(redirect_uri.query).merge(:error=>error.code, :error_description=>error.message, :state=>state)
          redirect_uri.query = Rack::Utils.build_query(params)
          return redirect_to(redirect_uri)
        end
      end

      # Get here on completion of the authorization. Authorization response in
      # oauth.response either grants or denies authroization. In either case, we
      # redirect back with the proper response.
      def authorization_response(response, logger)
        auth_request = Models::AuthRequest.find(response["oauth.request"])
        redirect_uri = URI.parse(auth_request.redirect_uri)
        if resource = response["oauth.resource"]
          auth_request.grant! response["oauth.resource"]
        else
          auth_request.deny!
        end
        # 3.1.  Authorization Response
        if auth_request.response_type == "code" && auth_request.grant_code
          logger.info "Request #{auth_request.id}: Client #{auth_request.client_id} granted access code #{auth_request.grant_code}" if logger
          params = { :code=>auth_request.grant_code, :scope=>auth_request.scope, :state=>auth_request.state }
          params = Rack::Utils.parse_query(redirect_uri.query).merge(params)
          redirect_uri.query = Rack::Utils.build_query(params)
          return redirect_to(redirect_uri)
        elsif auth_request.response_type == "token" && auth_request.access_token
          logger.info "Request #{auth_request.id}: Client #{auth_request.client_id} granted access token #{auth_request.access_token}" if logger
          params = { :access_token=>auth_request.access_token, :scope=>auth_request.scope, :state=>auth_request.state }
          redirect_uri.fragment = Rack::Utils.build_query(params)
          return redirect_to(redirect_uri)
        else
          logger.info "Request #{auth_request.id}: Client #{auth_request.client_id} denied authorization" if logger
          params = Rack::Utils.parse_query(redirect_uri.query).merge(:error=>:access_denied, :state=>auth_request.state)
          redirect_uri.query = Rack::Utils.build_query(params)
          return redirect_to(redirect_uri)
        end
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
            grant = Models::AccessGrant.from_code(request.POST["code"])
            raise InvalidGrantError unless grant && client.id == grant.client_id
            raise InvalidGrantError unless grant.redirect_uri.nil? || grant.redirect_uri == Utils.parse_redirect_uri(request.POST["redirect_uri"]).to_s
            access_token = grant.authorize!
          when "password"
            raise UnsupportedGrantType unless @authenticator
            # 4.1.2.  Resource Owner Password Credentials
            username, password = request.POST.values_at("username", "password")
            requested_scope = request.POST["scope"].to_s.split.uniq.join(" ")
            raise InvalidGrantError unless username && password
            resource = @authenticator.call(username, password)
            raise InvalidGrantError unless resource
            if scopes
              allowed_scopes = scopes.respond_to?(:split) ? scopes.split : scopes
              raise InvalidScopeError unless requested_scope.split.all? { |v| allowed_scopes.include?(v) }
            end
            access_token = Models::AccessToken.get_token_for(resource, requested_scope.to_s, client.id)
          else raise UnsupportedGrantType
          end
          logger.info "Access token #{access_token.token} granted to client #{client.display_name}, resource #{access_token.resource}" if logger
          response = { :access_token=>access_token.token }
          response[:scope] = access_token.scope unless access_token.scope.empty?
          return [200, { "Content-Type"=>"application/json", "Cache-Control"=>"no-store" }, response.to_json]
          # 4.3.  Error Response
        rescue Error=>error
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
        client = Models::Client.find(client_id)
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
        challenge = 'OAuth realm="%s"' % (realm || request.host)
        challenge << ', error="%s", error_description="%s"' % [error.code, error.message] if error
        return [401, { "WWW-Authenticate"=>challenge }, []]
      end

      # Wraps Rack::Request to expose Basic and OAuth authentication
      # credentials.
      class OAuthRequest < Rack::Request
        include Server::RequestHelpers

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
