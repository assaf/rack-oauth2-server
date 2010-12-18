module Rack
  module OAuth2
    class Server

      module Utils
        module_function

        # Parses the redirect URL, normalizes it and returns a URI object.
        #
        # Raises InvalidRequestError if not an absolute HTTP/S URL.
        def parse_redirect_uri(redirect_uri)
          raise InvalidRequestError, "Missing redirect URL" unless redirect_uri
          uri = URI.parse(redirect_uri).normalize rescue nil
          raise InvalidRequestError, "Redirect URL looks fishy to me" unless uri
          raise InvalidRequestError, "Redirect URL must be absolute URL" unless uri.absolute? && uri.host
          raise InvalidRequestError, "Redirect URL must point to HTTP/S location" unless uri.scheme == "http" || uri.scheme == "https"
          uri
        end

        # Given scope as either array or string, return array of same names,
        # unique and sorted.
        def normalize_scope(scope)
          (Array === scope ? scope.join(" ") : scope || "").split(/\s+/).compact.uniq.sort
        end

      end

    end
  end
end
