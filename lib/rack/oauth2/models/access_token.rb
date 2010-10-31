module Rack
  module OAuth2
    class Server

      # Access token. This is what clients use to access resources.
      #
      # An access token is a unique code, associated with a client, a resource
      # and scope. It may be revoked, or expire after a certain period.
      class AccessToken
        class << self
          # Find AccessToken from token. Does not return revoked tokens.
          def from_token(token)
            Server.new_instance self, collection.find_one({ :_id=>token, :revoked=>nil })
          end

          # Get an access token (create new one if necessary).
          def get_token_for(resource, scope, client_id)
            unless token = collection.find_one({ :resource=>resource, :scope=>scope, :client_id=>client_id })
              token = { :_id=>Server.secure_random, :resource=>resource, :scope=>scope, :client_id=>client_id,
                        :created_at=>Time.now.utc, :expires_at=>nil, :revoked=>nil }
              collection.insert token
            end
            Server.new_instance self, token
          end

          # Find all AccessTokens for a resource.
          def from_resource(resource)
            collection.find({ :resource=>resource }).map { |fields| Server.new_instance self, fields }
          end

          def collection
            Server.db["oauth2.access_tokens"]
          end
        end

        # Access token. As unique as they come.
        attr_reader :_id
        alias :token :_id
        # The resource we authorized access to.
        attr_reader :resource
        # Client that was granted this access token.
        attr_reader :client_id
        # The scope granted in this token.
        attr_reader :scope
        # When token was granted.
        attr_reader :created_at
        # When token expires for good.
        attr_reader :expires_at
        # Timestamp if revoked.
        attr_accessor :revoked

        # Revokes this access token.
        def revoke!
          self.revoked = Time.now.utc
          AccessToken.collection.update({ :_id=>token }, { :$set=>{ :revoked=>revoked } })
        end
        
        # Allows us to kill all pending grants on behalf of client/resource.
        #collection.create_index [[:client_id, Mongo::ASCENDING]]
        #collection.create_index [[:resource, Mongo::ASCENDING]]
      end

    end
  end
end
