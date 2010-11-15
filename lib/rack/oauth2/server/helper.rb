module Rack
  module OAuth2
    class Server

      # Helper methods that provide access to the OAuth state during the
      # authorization flow, and from authenticated requests. For example:
      #
      #   def show
      #     logger.info "#{oauth.client.display_name} accessing #{oauth.scope}"
      #   end
      class Helper

        def initialize(request, response)
          @request, @response = request, response
        end

        # Returns the access token. Only applies if client authenticated.
        #
        # @return [String, nil] Access token, if authenticated
        def access_token
          @access_token ||= @request.env["oauth.access_token"]
        end

        # True if client authenticated.
        #
        # @return [true, false] True if authenticated
        def authenticated?
          !!access_token
        end

        # Returns the authenticated identity. Only applies if client
        # authenticated.
        #
        # @return [String, nil] Identity, if authenticated
        def identity
          @identity ||= @request.env["oauth.identity"]
        end

        # Returns the Client object associated with this request. Available if
        # client authenticated, or while processing authorization request.
        #
        # @return [Client, nil] Client if authenticated, or while authorizing
        def client
          if access_token
            @client ||= Server.get_client(Server.get_access_token(access_token).client_id)
          elsif authorization
            @client ||= Server.get_client(Server.get_auth_request(authorization).client_id)
          end
        end

        # Returns scope associated with this request. Available if client
        # authenticated, or while processing authorization request.
        #
        # @return [Array<String>, nil] Scope names, e.g ["read, "write"]
        def scope
          if access_token
            @scope ||= Server::Utils.normalize_scopes(Server.get_access_token(access_token).scope)
          elsif authorization
            @scope ||= Server::Utils.normalize_scopes(Server.get_auth_request(authorization).scope)
          end
        end

        # Rejects the request and returns 401 (Unauthorized). You can just
        # return 401, but this also sets the WWW-Authenticate header the right
        # value.
        #
        # @return 401
        def no_access!
          @response["oauth.no_access"] = "true"
          @response.status = 401
        end
        
        # Rejects the request and returns 403 (Forbidden). You can just
        # return 403, but this also sets the WWW-Authenticate header the right
        # value. Indicates which scope the client needs to make this request.
        #
        # @param [String] scope The missing scope, e.g. "read"
        # @return 403
        def no_scope!(scope)
          @response["oauth.no_scope"] = scope.to_s
          @response.status = 403
        end

        # Returns the authorization request handle. Available when starting an
        # authorization request (i.e. /oauth/authorize).
        #
        # @return [String] Authorization handle
        def authorization
          @request_id ||= @request.env["oauth.authorization"] || @request.params["authorization"]
        end

        # Sets the authorization request handle. Use this during the
        # authorization flow.
        #
        # @param [String] authorization handle
        def authorization=(authorization)
          @scope, @client = nil
          @request_id = authorization
        end

        # Grant authorization request. Call this at the end of the authorization
        # flow to signal that the user has authorized the client to access the
        # specified identity. Don't render anything else.  Argument required if
        # authorization handle is not passed in the request parameter
        # +authorization+.
        #
        # @param [String, nil] authorization Authorization handle
        # @param [String] identity Identity string
        # @return 200
        def grant!(auth, identity = nil)
          auth, identity = authorization, auth unless identity
          @response["oauth.authorization"] = auth.to_s
          @response["oauth.identity"] = identity.to_s
          @response.status = 200
        end

        # Deny authorization request. Call this at the end of the authorization
        # flow to signal that the user has not authorized the client. Don't
        # render anything else. Argument required if authorization handle is not
        # passed in the request parameter +authorization+.
        #
        # @param [String, nil] auth Authorization handle
        # @return 401
        def deny!(auth = nil)
          auth ||= authorization
          @response["oauth.authorization"] = auth.to_s
          @response.status = 403
        end

        # Returns all access tokens associated with this identity.
        #
        # @param [String] identity Identity string
        # @return [Array<AccessToken>]
        def list_access_tokens(identity)
          Rack::OAuth2::Server.list_access_tokens(identity)
        end

        def inspect
          authorization ? "Authorization request for #{scope.join(",")} on behalf of #{client.display_name}" :
          authenticated? ? "Authenticated as #{identity}" : nil
        end

      end

    end
  end
end
