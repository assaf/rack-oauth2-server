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
        def access_token
          @access_token ||= @request.env["oauth.access_token"]
        end

        # True if client authenticated.
        def authenticated?
          !!access_token
        end

        # Returns the authenticated resource. Only applies if client
        # authenticated.
        def resource
          @resource ||= @request.env["oauth.resource"]
        end

        # Returns the Client object associated with this request. Available if
        # client authenticated, or while processing authorization request.
        def client
          if access_token
            @client ||= Server.get_client(Server.get_access_token(access_token).client_id)
          elsif authorization
            @client ||= Server.get_client(Server.get_auth_request(authorization).client_id)
          end
        end

        # Returns scope associated with this request. Returns an array of scope
        # names (e.g. ["read", "write"]). Available if client authenticated, or
        # while processing authorization request.
        def scope
          if access_token
            @scope ||= Server.get_access_token(access_token).scope.split
          elsif authorization
            @scope ||= Server.get_auth_request(authorization).scope.split
          end
        end

        # Rejects the request and returns 401 (Unauthorized). You can just
        # return 401, but this also sets the WWW-Authenticate header the right
        # value.
        def no_access!
          @response["oauth.no_access"] = true
          @response.status = 401
        end
        
        # Rejects the request and returns 403 (Forbidden). You can just
        # return 403, but this also sets the WWW-Authenticate header the right
        # value. Indicates which scope the client needs to make this request.
        def no_scope!(scope)
          @response["oauth.no_scope"] = scope
          @response.status = 403
        end

        # Returns the authorization request handle. Available when starting an
        # authorization request (i.e. /oauth/authorize).
        def authorization
          @request_id ||= @request.env["oauth.authorization"]
        end

        # Sets the authorization request handle. Use this during the
        # authorization flow.
        def authorization=(authorization)
          @scope, @client = nil
          @request_id = authorization
        end

        # Grant authorization request. Call this at the end of the authorization
        # flow to signal that the user has authorized the client to access the
        # specified resource. Don't render anything else.
        def grant!(authorization, resource)
          @response["oauth.authorization"] = authorization
          @response["oauth.resource"] = resource.to_s
          @response.status = 200
        end

        # Deny authorization request. Call this at the end of the authorization
        # flow to signal that the user has not authorized the client. Don't
        # render anything else.
        def deny!(authorization)
          @response["oauth.authorization"] = authorization
          @response.status = 401
        end

        # Returns all access tokens associated with this resource.
        def list_access_tokens(resource)
          Rack::OAuth2::Server.list_access_tokens(resource)
        end

        def inspect
          authorization ? "Authorization request for #{scope.join(",")} on behalf of #{client.display_name}" :
          authenticated? ? "Authenticated as #{resource}" : nil
        end

      end

    end
  end
end
