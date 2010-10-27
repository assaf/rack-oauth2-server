require "rack/oauth2/models"
require "rack/oauth2/server/errors"
require "rack/oauth2/server/utils"
require "rack/oauth2/server/version"


module Rack
  module OAuth2

    # Implements an OAuth 2 Authorization Server, based on http://tools.ietf.org/html/draft-ietf-oauth-v2-10
    class Server

      def initialize(app, options = {}, &authenticator)
        @app, @authenticator = app, authenticator
        { :realm=>"All around",
          :access_token_path=>"/oauth/access_token",
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
      #
      # If you want to use your own filter, set restricted_path to a block that
      # accepts a Request and returns true if must be restricted. Or just use an
      # application filter, or check within the action.
      attr_accessor :restricted_path
      # Authorization realm. 
      attr_accessor :realm

      def call(env)
        logger = env["rack.logger"]
        request = OAuthRequest.new(env)

        # 3.  Obtaining End-User Authorization
        return request_authorization(request, logger) if request.path == authorize_path
        # ^ Request comes here, final decision reached, then capture response v
        if request.path.index(authorize_path) == 0
          response = @app.call(env)
          if env["oauth.response"]
            return authorization_response(env, logger)
          else
            return response
          end
        end

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
            token = Models::AccessToken.find(access_token)
            raise InvalidTokenError if token.nil? || token.revoked
            raise ExpiredTokenError if token.expires_at > Time.now.utc
            account = @authenticator.call(token.account_id, token.scope, request)
            raise InvalidTokenError unless account
            env["oauth.account_id"] = account
            env["oauth.scope"] = token.scope
            env["oauth.client_id"] = token.client_id
            logger.info "Authorized #{account}"
          rescue Error=>error
            # 5.2.  The WWW-Authenticate Response Header Field
            logger.info "HTTP authorization failed #{error.code}"
            return unauthorized(error)
          end
        elsif restricted_path && request.path.index(restricted_path) == 0
          logger.info "HTTP authorization header missing OAuth access token"
          return unauthorized
        end
        return @app.call(env)
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
          logger.error "Authorization request with invalid redirect_uri: #{request.GET["redirect_uri"]} #{error.message}"
          return bad_request(error.message)
        end
        state = request.GET["state"]

        begin
          # 3. Obtaining End-User Authorization
          client = get_client(request)
          raise RedirectUriMismatchError unless client.redirect_uri.nil? || client.redirect_uri == redirect_uri.to_s
          scope = request.GET["scope"]
          response_type = request.GET["response_type"].to_s
          raise UnsupportedResponseTypeError unless supported_authorization_types.include?(response_type)
          # Create object to track authorization request and let application
          # handle the rest.
          auth_request = Models::AuthRequest.create(client.id, scope, redirect_uri.to_s, response_type, state)
          request.env["oauth.request"] = auth_request.id.to_s
          request.env["oauth.client_id"] = client.id.to_s
          request.env["oauth.scope"] = scope.split
          logger.info "Request #{auth_request.id}: Client #{client.display_name} requested #{response_type} with scope #{scope}"
          return @app.call(request.env)
        rescue Error=>error
          logger.error "Authorization request error: #{error.code} #{error.message}"
          params = Rack::Utils.parse_query(redirect_uri.query).merge(:error=>error.code, :error_description=>error.message, :state=>state)
          redirect_uri.query = Rack::Utils.build_query(params)
          return redirect_to(redirect_uri)
        end
      end

      # Get here on completion of the authorization. Authorization response in
      # oauth.response either grants or denies authroization. In either case, we
      # redirect back with the proper response.
      def authorization_response(env, logger)
        auth_request = Models::AuthRequest.find(env["oauth.response"])
        redirect_uri = URI.parse(auth_request.redirect_uri)
        if account_id = env["oauth.account_id"]
          auth_request.grant! account_id
        else
          auth_request.deny!
        end
        # 3.1.  Authorization Response
        if auth_request.response_type == "code" && auth_request.grant_code
          logger.info "Request #{auth_request.id}: Client #{auth_request.client_id} granted access code #{auth_request.grant_code}"
          params = { :code=>auth_request.grant_code, :scope=>auth_request.scope, :state=>auth_request.state }
          params = Rack::Utils.parse_query(redirect_uri.query).merge(params)
          redirect_uri.query = Rack::Utils.build_query(params)
          return redirect_to(redirect_uri)
        elsif auth_request.response_type == "token" && auth_request.access_token
          logger.info "Request #{auth_request.id}: Client #{auth_request.client_id} granted access token #{auth_request.access_token}"
          params = { :access_token=>auth_request.access_token, :scope=>auth_request.scope, :state=>auth_request.state }
          redirect_uri.fragment = Rack::Utils.build_query(params)
          return redirect_to(redirect_uri)
        else
          logger.info "Request #{auth_request.id}: Client #{auth_request.client_id} denied authorization"
          params = Rack::Utils.parse_query(redirect_uri.query).merge(:error=>:access_denied, :state=>auth_request.state)
          redirect_uri.query = Rack::Utils.build_query(params)
          return redirect_to(redirect_uri)
        end
      end

      # 4.  Obtaining an Access Token
      def respond_with_access_token(request, logger)
        # 4.2.  Access Token Response
        begin
          raise InvalidRequestError, "Must be a POST request" unless request.post?
          raise UnsupportedGrantType unless request.POST["grant_type"] == "authorization_code"
          client = get_client(request)
          # 4.1.1.  Authorization Code
          grant = Models::AccessGrant.find(request.POST["code"])
          raise InvalidGrantError unless grant && client.id == grant.client_id
          raise InvalidGrantError unless client.redirect_uri.nil? || client.redirect_uri == Utils.parse_redirect_uri(request.POST["redirect_uri"]).to_s
          access_token = grant.authorize!
          logger.info "Access token #{access_token.token} granted to client #{client.display_name} from grant #{grant.id}"
          return [200, { "Content-Type"=>"application/json", "Cache-Control"=>"no-store" }, 
                  { :access_token=>access_token.token, :scope=>access_token.scope }.to_json]
        rescue Error=>error
          logger.error "Access token request error: #{error.code} #{error.message}"
          return [error.status, { "Content-Type"=>"application/json", "Cache-Control"=>"no-store" }, 
                  { :error=>error.code, :error_description=>error.message }.to_json]
        end
      end

      # Returns client from request based on credentials. Raises
      # InvalidClientError if client doesn't exist or secret doesn't match.
      def get_client(request)
        # 2.1  Client Password Credentials
        if request.basic?
          client_id, client_secret = request.credentials
        elsif request.post?
          client_id, client_secret = request.POST.values_at("client_id", "client_secret")
        else
          client_id, client_secret = request.GET.values_at("client_id", "client_secret")
        end
        client = Models::Client.find(client_id)
        raise InvalidClientError unless client && client.secret == client_secret
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
      def unauthorized(error = nil)
        challenge = 'OAuth realm="%s"' % realm
        challenge << ', error="%s", error_description="%s"' % [error.code, error.message] if error
        return [401, { "Content-Type"=>"text/plain", "Content-Length"=>"0", "WWW-Authenticate"=>challenge }, []]
      end

      # Wraps Rack::Request to expose Basic and OAuth authentication
      # credentials.
      class OAuthRequest < Rack::Request

        AUTHORIZATION_KEYS = %w{HTTP_AUTHORIZATION X-HTTP_AUTHORIZATION X_HTTP_AUTHORIZATION}

        # Returns authorization header.
        def authorization
          @authorization ||= @env.values_at(AUTHORIZATION_KEYS).compact.map(&:split).first
        end

        # True if authentication scheme is OAuth.
        def oauth?
          :oauth == authorization.first if authorization
        end

        # True if authentication scheme is Basic.
        def basic?
          :basic == authorization.first if authorization
        end

        # If Basic auth, returns username/password, if OAuth, returns access
        # token.
        def credentials
          @credentials ||= basic? ? authorization[1].unpack("m*").first.split(/:/, 2) :
                           oauth? ? authorization[1] : nil
        end
      end

    end

  end
end
