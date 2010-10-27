module Rack
  module OAuth2
    class Server

      # Base class for all OAuth errors. These map to error codes in the spec.
      class Error < StandardError

        def initialize(code, status, message)
          super message
          @code = code.to_sym
          @status = status
        end

        # The OAuth error code.
        attr_reader :code
        # The HTTP status code.
        attr_reader :status
      end

      # Access token expired, client expected to request new one using refresh
      # token.
      class ExpiredTokenError < Error
        # TODO: for this to work, actually need refresh token
        def initialize
          super :expired_token, 401, "The access token has expired."
        end
      end

      # Access token expired, client cannot refresh and needs new authorization.
      class InvalidTokenError < Error
        def initialize
          super :invalid_token, 401, "The access token is no longer valid."
        end
      end

      # Invalid_request, the request is missing a required parameter, includes an
      # unsupported parameter or parameter value, repeats the same parameter, uses
      # more than one method for including an access token, or is otherwise
      # malformed.
      class InvalidRequestError < Error
        def initialize(message)
          super :invalid_request, 400, message || "The request has the wrong parameters."
        end
      end

      # This access grant type is not supported by this server.
      class UnsupportedGrantType < Error
        def initialize
          super :unsupported_grant_type, 401, "This access grant type is not supported by this server."
        end
      end

      # The requested response type is not supported by the authorization server.
      class UnsupportedResponseTypeError < Error
        def initialize
          super :unsupported_response_type, 401, "The requested response type is not supported."
        end
      end

      # The authenticated client is not authorized to use the access grant type provided.
      class UnauthorizedClientError < Error
        def initialize
          super :unauthorized_client, 401, "You are not allowed to access this resource."
        end
      end

      # The client identifier provided is invalid, the client failed to
      # authenticate, the client did not include its credentials, provided
      # multiple client credentials, or used unsupported credentials type.
      class InvalidClientError < Error
        def initialize
          super :invalid_client, 401, "Client ID and client secret do not match."
        end
      end
     
      # The provided access grant is invalid, expired, or revoked (e.g.  invalid
      # assertion, expired authorization token, bad end-user password credentials,
      # or mismatching authorization code and redirection URI).
      class InvalidGrantError < Error
        def initialize
          super :invalid_grant, 401, "This access grant is no longer valid."
        end
      end

      # The redirection URI provided does not match a pre-registered value.
      class RedirectUriMismatchError < Error
        def initialize
          super :redirect_uri_mismatch, 401, "Must use the same redirect URI you registered with us."
        end
      end

    end
  end
end
