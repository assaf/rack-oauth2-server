module Rack
  module OAuth2
    class UUIDGenerator
      # The uuid string is not valid
      class UnknownUUIDLibrary < Rack::OAuth2::Server::OAuthError
        def initialize
          super :unknown_uuid_library, "You have requested UUID Primary Key but the UUID library is not present."
        end
      end

      # The uuid string is not valid
      class InvalidUUID < Rack::OAuth2::Server::OAuthError
        def initialize
          super :invalid_uuid, "The uuid string you provided is invalid."
        end
      end

      class << self
        def generate
          fail UnknownUUIDLibrary unless Object.const_defined?('UUID')

          UUID.generate
        end

        def from_string(value)
          fail InvalidUUID unless UUID.validate(value)
          fail UnknownUUIDLibrary unless Object.const_defined?('UUID')

          value
        end
      end
    end
  end
end
