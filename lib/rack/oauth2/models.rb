require "mongo"
require "openssl"


require "rack/oauth2/models/client"
require "rack/oauth2/models/auth_request"
require "rack/oauth2/models/access_grant"
require "rack/oauth2/models/access_token"

module Rack
  module OAuth2
    class Server

      class << self
        # A Mongo::DB object.
        attr_accessor :database
        
        # Create new instance of the klass and populate its attributes.
        def new_instance(klass, fields)
          return unless fields
          instance = klass.new
          fields.each do |name, value|
            instance.instance_variable_set :"@#{name}", value
          end
          instance
        end

        # Long, random and hexy.
        def secure_random
          OpenSSL::Random.random_bytes(32).unpack("H*")[0]
        end

      end

    end
  end
end
