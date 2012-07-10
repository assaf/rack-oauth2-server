require "rack"
require "rack/oauth2/models"
require "rack/oauth2/server/errors"
require "rack/oauth2/server/utils"
require "rack/oauth2/server/helper"
require "iconv"
require "json"

module Rack
  module OAuth2

    # Implements an OAuth 2 Authorization Server, based on http://tools.ietf.org/html/draft-ietf-oauth-v2-10
    class Server

      # Same as gem version number.
      VERSION = IO.read(::File.expand_path("../../../VERSION", ::File.dirname(__FILE__))).strip

      class << self
        # Return AuthRequest from authorization request handle.
        #
        # @param [String] authorization Authorization handle (e.g. from
        # oauth.authorization)
        # @return [AuthReqeust]
        def get_auth_request(authorization)
          AuthRequest.find(authorization)
        end

        # Returns Client from client identifier.
        #
        # @param [String] client_id Client identifier (e.g. from oauth.client.id)
        # @return [Client]
        def get_client(client_id)
          return client_id if Client === client_id
          Client.find(client_id)
        end

        # Registers and returns a new Client. Can also be used to update
        # existing client registration, by passing identifier (and secret) of
        # existing client record. That way, your setup script can create a new
        # client application and run repeatedly without fail.
        #
        # @param [Hash] args Arguments for registering client application
        # @option args [String] :id Client identifier. Use this to update
        # existing client registration (in combination wih secret)
        # @option args [String] :secret Client secret. Use this to update
        # existing client registration.
        # @option args [String] :display_name Name to show when authorizing
        # access (e.g.  "My Awesome Application")
        # @option args [String] link Link to client application's Web site
        # @option args [String] image_url URL of image to show alongside display
        # name.
        # @option args [String] redirect_uri Redirect URL: authorization
        # requests for this client will always redirect back to this URL.
        # @option args [Array] scope Scope that client application can request
        # (list of names).
        # @option args [Array] notes Free form text, for internal use.
        #
        # @example Registering new client application
        #   Server.register :display_name=>"My Application",
        #     :link=>"http://example.com", :scope=>%w{read write},
        #     :redirect_uri=>"http://example.com/oauth/callback"
        # @example Migration using configuration file
        #   config = YAML.load_file(Rails.root + "config/oauth.yml")
        #   Server.register config["id"], config["secret"],
        #     :display_name=>"My  Application", :link=>"http://example.com",
        #     :scope=>config["scope"],
        #     :redirect_uri=>"http://example.com/oauth/callback"
        def register(args)
          if args[:id] && args[:secret] && (client = get_client(args[:id]))
            fail "Client secret does not match" unless client.secret == args[:secret]
            client.update args
          else
            Client.create(args)
          end
        end

        # Creates and returns a new access grant. Actually, returns only the
        # authorization code which you can turn into an access token by
        # making a request to /oauth/access_token.
        #
        # @param [String,Integer] identity User ID, account ID, etc
        # @param [String] client_id Client identifier
        # @param [Array, nil] scope Array of string, nil if you want 'em all
        # @param [Integer, nil] expires_in How many seconds before access grant
        # expires (default to 5 minutes)
        # @return [String] Access grant authorization code
        def access_grant(identity, client_id, scope = nil, expires_in = nil)
          client = get_client(client_id) or fail "No such client"
          AccessGrant.create(identity, client, scope || client.scope, nil, expires_in).code
        end

        # Returns AccessToken from token.
        #
        # @param [String] token Access token (e.g. from oauth.access_token)
        # @return [AccessToken]
        def get_access_token(token)
          AccessToken.from_token(token)
        end

        # Returns AccessToken for the specified identity, client application and
        # scope. You can use this method to request existing access token, new
        # token generated if one does not already exists.
        #
        # @param [String,Integer] identity Identity, e.g. user ID, account ID
        # @param [String] client_id Client application identifier
        # @param [Array, nil] scope Array of names, nil if you want 'em all
        # @param [Integer, nil] expires How many seconds before access token
        # expires, defaults to never. If zero or nil, token never expires.
        # @return [String] Access token
        def token_for(identity, client_id, scope = nil, expires_in = nil)
          client = get_client(client_id) or fail "No such client"
          AccessToken.get_token_for(identity, client, scope || client.scope, expires_in).token
        end

        # Returns all AccessTokens for an identity.
        #
        # @param [String] identity Identity, e.g. user ID, account ID
        # @return [Array<AccessToken>]
        def list_access_tokens(identity)
          AccessToken.from_identity(identity)
        end

        # Registers and returns a new Issuer. Can also be used to update
        # existing Issuer, by passing the identifier of an existing Issuer record.
        # That way, your setup script can create a new client application and run
        # repeatedly without fail.
        #
        # @param [Hash] args Arguments for registering Issuer
        # @option args [String] :identifier Issuer identifier. Use this to update
        # an existing Issuer
        # @option args [String] :hmac_secret The HMAC secret for this Issuer
        # @option args [String] :public_key The RSA public key (in PEM format) for this Issuer
        # @option args [Array] :notes Free form text, for internal use.
        #
        # @example Registering new Issuer
        #   Server.register_issuer :hmac_secret=>"foo", :notes=>"Company A"
        # @example Migration using configuration file
        #   config = YAML.load_file(Rails.root + "config/oauth.yml")
        #   Server.register_issuer config["id"],
        #   :hmac_secret=>"bar", :notes=>"Company A"
        def register_issuer(args)
          if args[:identifier] && (issuer = get_issuer(args[:identifier]))
            issuer.update(args)
          else
            Issuer.create(args)
          end
        end

        # Returns an Issuer from it's identifier.
        #
        # @param [String] identifier the Issuer's identifier
        # @return [Issuer]
        def get_issuer(identifier)
          Issuer.from_identifier(identifier)
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
      # - :database -- Mongo::DB instance (this is a global option).
      # - :expires_in -- Number of seconds an auth token will live. If nil or
      #   zero, access token never expires.
      # - :host -- Only check requests sent to this host.
      # - :path -- Only check requests for resources under this path.
      # - :param_authentication -- If true, supports authentication using
      #   query/form parameters.
      # - :realm -- Authorization realm that will show up in 401 responses.
      #   Defaults to use the request host name.
      # - :logger -- The logger to use. Under Rails, defaults to use the Rails
      #   logger.  Will use Rack::Logger if available.
      # - :collection_prefix -- Prefix to use for MongoDB collections created by rack-oauth2-server. Defaults to "oauth2".
      #
      # Authenticator is a block that receives either two or four parameters.
      # The first two are username and password. The other two are the client
      # identifier and scope. It authenticated, it returns an identity,
      # otherwise it can return nil or false. For example:
      #   oauth.authenticator = lambda do |username, password|
      #     user = User.find_by_username(username)
      #     user if user && user.authenticated?(password)
      #   end
      #
      # Assertion handler is a hash of blocks keyed by assertion_type.  Blocks receive
      # three parameters: the client, the assertion, and the scope.  If authenticated, 
      # it returns an identity.  Otherwise it can return nil or false.  For example:
      #   oauth.assertion_handler['facebook.com'] = lambda do |client, assertion, scope|
      #     facebook = URI.parse('https://graph.facebook.com/me?access_token=' + assertion)
      #     response = Net::HTTP.get_response(facebook)
      #
      #     user_data = JSON.parse(response.body)
      #     user   = User.from_facebook_data(user_data)
      #   end
      # Assertion handlers are optional; if one is not present for a given assertion
      # type, no error will result.
      #
      Options = Struct.new(:access_token_path, :authenticator, :assertion_handler, :authorization_types,
        :authorize_path, :database, :host, :param_authentication, :path, :realm, 
        :expires_in,:logger, :collection_prefix)

      # Global options. This is what we set during configuration (e.g. Rails'
      # config/application), and options all handlers inherit by default.
      def self.options
        @options
      end

      @options = Options.new

      def initialize(app, options = nil, &authenticator)
        @app = app
        @options = options || Server.options
        @options.authenticator ||= authenticator
        @options.assertion_handler ||= {}
        @options.access_token_path ||= "/oauth/access_token"
        @options.authorize_path ||= "/oauth/authorize"
        @options.authorization_types ||=  %w{code token}
        @options.param_authentication ||= false
        @options.collection_prefix ||= "oauth2"
      end

      # Options specific for this handle. @see Options
      attr_reader :options

      def call(env)
        request = OAuthRequest.new(env)
        return @app.call(env) if options.host && options.host != request.host
        return @app.call(env) if options.path && request.path.index(options.path) != 0

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
          token   = request.GET["oauth_token"] || request.POST["oauth_token"]
          token ||= request.GET['access_token'] || request.POST['access_token']
        end

        if token
          begin
            access_token = AccessToken.from_token(token)
            raise InvalidTokenError if access_token.nil? || access_token.revoked
            raise ExpiredTokenError if access_token.expires_at && access_token.expires_at <= Time.now.to_i
            request.env["oauth.access_token"] = token

            request.env["oauth.identity"] = access_token.identity
            access_token.access!
            logger.info "RO2S: Authorized #{access_token.identity}" if logger
          rescue OAuthError=>error
            # 5.2.  The WWW-Authenticate Response Header Field
            logger.info "RO2S: HTTP authorization failed #{error.code}" if logger
            return unauthorized(request, error)
          rescue =>ex
            logger.info "RO2S: HTTP authorization failed #{ex.message}" if logger
            return unauthorized(request)
          end

          # We expect application to use 403 if request has insufficient scope,
          # and return appropriate WWW-Authenticate header.
          response = @app.call(env)
          if response[0] == 403
            scope = Utils.normalize_scope(response[1].delete("oauth.no_scope"))
            challenge = 'OAuth realm="%s", error="insufficient_scope", scope="%s"' % [(options.realm || request.host), scope.join(" ")]
            response[1]["WWW-Authenticate"] = challenge
            return response
          else
            return response
          end
        else
          response = @app.call(env)
          if response[1] && response[1].delete("oauth.no_access")
            logger.debug "RO2S: Unauthorized request" if logger
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
              logger.error "RO2S: Invalid authorization request #{auth_request}" if logger
              return bad_request("Invalid authorization request")
            end
            response_type = auth_request.response_type # Needed for error handling
            client = self.class.get_client(auth_request.client_id)
            # Pass back to application, watch for 403 (deny!)
            logger.info "RO2S: Client #{client.display_name} requested #{auth_request.response_type} with scope #{auth_request.scope.join(" ")}" if logger
            request.env["oauth.authorization"] = auth_request.id.to_s
            response = @app.call(request.env)
            raise AccessDeniedError if response[0] == 403
            return response

          else

            # 3.  Obtaining End-User Authorization
            begin
              redirect_uri = Utils.parse_redirect_uri(request.GET["redirect_uri"])
            rescue InvalidRequestError=>error
              logger.error "RO2S: Authorization request with invalid redirect_uri: #{request.GET["redirect_uri"]} #{error.message}" if logger
              return bad_request(error.message)
            end

            # 3. Obtaining End-User Authorization
            response_type = request.GET["response_type"].to_s # Need this first, for error handling
            client = get_client(request, :dont_authenticate => true)
            raise RedirectUriMismatchError unless client.redirect_uri.nil? || client.redirect_uri == redirect_uri.to_s
            raise UnsupportedResponseTypeError unless options.authorization_types.include?(response_type)
            requested_scope = Utils.normalize_scope(request.GET["scope"])
            allowed_scope = client.scope
            raise InvalidScopeError unless (requested_scope - allowed_scope).empty?
            # Create object to track authorization request and let application
            # handle the rest.
            auth_request = AuthRequest.create(client, requested_scope, redirect_uri.to_s, response_type, state)
            uri = URI.parse(request.url)
            uri.query = "authorization=#{auth_request.id.to_s}"
            return redirect_to(uri, 303)
          end
        rescue OAuthError=>error
          logger.error "RO2S: Authorization request error #{error.code}: #{error.message}" if logger
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
          auth_request.grant! headers["oauth.identity"], options.expires_in
        end
        # 3.1.  Authorization Response
        if auth_request.response_type == "code"
          if auth_request.grant_code
            logger.info "RO2S: Client #{auth_request.client_id} granted access code #{auth_request.grant_code}" if logger
            params = { :code=>auth_request.grant_code, :scope=>auth_request.scope.join(" "), :state=>auth_request.state }
          else
            logger.info "RO2S: Client #{auth_request.client_id} denied authorization" if logger
            params = { :error=>:access_denied, :state=>auth_request.state }
          end
          params = Rack::Utils.parse_query(redirect_uri.query).merge(params)
          redirect_uri.query = Rack::Utils.build_query(params)
        else # response type if token
          if auth_request.access_token
            logger.info "RO2S: Client #{auth_request.client_id} granted access token #{auth_request.access_token}" if logger
            params = { :access_token=>auth_request.access_token, :scope=>auth_request.scope.join(" "), :state=>auth_request.state }
          else
            logger.info "RO2S: Client #{auth_request.client_id} denied authorization" if logger
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
          when "none"
            # 4.1 "none" access grant type (i.e. two-legged OAuth flow)
            requested_scope = request.POST["scope"] ? Utils.normalize_scope(request.POST["scope"]) : client.scope
            access_token = AccessToken.create_token_for(client, requested_scope, nil, options.expires_in)
          when "authorization_code"
            # 4.1.1.  Authorization Code
            grant = AccessGrant.from_code(request.POST["code"])
            raise InvalidGrantError, "Wrong client" unless grant && client.id == grant.client_id
            unless client.redirect_uri.nil? || client.redirect_uri.to_s.empty?
              raise InvalidGrantError, "Wrong redirect URI" unless grant.redirect_uri == Utils.parse_redirect_uri(request.POST["redirect_uri"]).to_s
            end
            raise InvalidGrantError, "This access grant expired" if grant.expires_at && grant.expires_at <= Time.now.to_i
            access_token = grant.authorize!(options.expires_in)
          when "password"
            raise UnsupportedGrantType unless options.authenticator
            # 4.1.2.  Resource Owner Password Credentials
            username, password = request.POST.values_at("username", "password")
            raise InvalidGrantError, "Missing username/password" unless username && password
            requested_scope = request.POST["scope"] ? Utils.normalize_scope(request.POST["scope"]) : client.scope
            allowed_scope = client.scope
            raise InvalidScopeError unless (requested_scope - allowed_scope).empty?
            args = [username, password]
            args << client.id << requested_scope unless options.authenticator.arity == 2
            identity = options.authenticator.call(*args)
            raise InvalidGrantError, "Username/password do not match" unless identity
            access_token = AccessToken.get_token_for(identity, client, requested_scope, options.expires_in)
          when "assertion"
            # 4.1.3. Assertion
            requested_scope = request.POST["scope"] ? Utils.normalize_scope(request.POST["scope"]) : client.scope
            assertion_type, assertion = request.POST.values_at("assertion_type", "assertion")
            raise InvalidGrantError, "Missing assertion_type/assertion" unless assertion_type && assertion
            # TODO: Add other supported assertion types (i.e. SAML) here
            if assertion_type == "urn:ietf:params:oauth:grant-type:jwt-bearer"
              identity = process_jwt_assertion(assertion)
              access_token = AccessToken.get_token_for(identity, client, requested_scope, options.expires_in)
            elsif options.assertion_handler[assertion_type]
              args = [client, assertion, requested_scope]
              identity = options.assertion_handler[assertion_type].call(*args)
              raise InvalidGrantError, "Unknown assertion for #{assertion_type}" unless identity
              access_token = AccessToken.get_token_for(identity, client, requested_scope, options.expires_in)
            else
              raise InvalidGrantError, "Unsupported assertion_type" if assertion_type != "urn:ietf:params:oauth:grant-type:jwt-bearer"
            end
          else
            raise UnsupportedGrantType
          end
          logger.info "RO2S: Access token #{access_token.token} granted to client #{client.display_name}, identity #{access_token.identity}" if logger
          response = { :access_token=>access_token.token }
          response[:scope] = access_token.scope.join(" ")
          return [200, { "Content-Type"=>"application/json", "Cache-Control"=>"no-store" }, [response.to_json]]
          # 4.3.  Error Response
        rescue OAuthError=>error
          logger.error "RO2S: Access token request error #{error.code}: #{error.message}" if logger
          return unauthorized(request, error) if InvalidClientError === error && request.basic?
          return [400, { "Content-Type"=>"application/json", "Cache-Control"=>"no-store" }, 
                  [{ :error=>error.code, :error_description=>error.message }.to_json]]
        end
      end

      # Returns client from request based on credentials. Raises
      # InvalidClientError if client doesn't exist or secret doesn't match.
      def get_client(request, options={})
        # 2.1  Client Password Credentials
        if request.basic?
          client_id, client_secret = request.credentials
        elsif request.post?
          client_id, client_secret = request.POST.values_at("client_id", "client_secret")
        else
          client_id, client_secret = request.GET.values_at("client_id", "client_secret")
        end
        client = self.class.get_client(client_id)
        raise InvalidClientError if !client
        unless options[:dont_authenticate]
          raise InvalidClientError unless client.secret == client_secret
        end
        raise InvalidClientError if client.revoked
        return client
      rescue BSON::InvalidObjectId
        raise InvalidClientError
      end

      # Rack redirect response.
      # The argument is typically a URI object, and the status should be a 302 or 303.
      def redirect_to(uri, status = 302)
        return [status, { "Content-Type"=>"text/plain", "Location"=>uri.to_s }, ["You are being redirected"]]
      end

      def bad_request(message)
        return [400, { "Content-Type"=>"text/plain" }, [message]]
      end

      # Returns WWW-Authenticate header.
      def unauthorized(request, error = nil)
        challenge = 'OAuth realm="%s"' % (options.realm || request.host)
        challenge << ', error="%s", error_description="%s"' % [error.code, error.message] if error
        return [401, { "WWW-Authenticate"=>challenge }, [error && error.message || ""]]
      end

      # Processes a JWT assertion
      def process_jwt_assertion(assertion)
        begin
          require 'jwt'
          require 'json'
          require 'openssl'
          require 'time'
          # JWT.decode only returns the claims. Gotta get the header ourselves
          header = JSON.parse(JWT.base64url_decode(assertion.split('.')[0]))
          algorithm = header['alg']
          payload = JWT.decode(assertion, nil, false)

          raise InvalidGrantError, "missing issuer claim" if !payload.has_key?('iss')

          issuer_identifier = payload['iss']
          issuer = Issuer.from_identifier(issuer_identifier)
          raise InvalidGrantError, 'Invalid issuer' if issuer.nil?
          if algorithm =~ /^HS/
            validated_payload = JWT.decode(assertion, issuer.hmac_secret, true)
          elsif algorithm =~ /^RS/
            validated_payload = JWT.decode(assertion, OpenSSL::PKey::RSA.new(issuer.public_key), true)
          end

          raise InvalidGrantError, "missing principal claim" if !validated_payload.has_key?('prn')
          raise InvalidGrantError, "missing audience claim" if !validated_payload.has_key?('aud')
          raise InvalidGrantError, "missing expiration claim" if !validated_payload.has_key?('exp')

          expires = validated_payload['exp'].to_i
          # add a 10 minute fudge factor for clock skew between servers
          skewed_expires_time = expires + (10 * 60)
          now = Time.now.utc.to_i
          raise InvalidGrantError, "expired claims" if skewed_expires_time <= now
          principal = validated_payload['prn']
          principal
        rescue JWT::DecodeError => de
          raise InvalidGrantError, de.message
        rescue JSON::ParserError => pe
          raise InvalidGrantError, "Invalid segment encoding"
        end
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
