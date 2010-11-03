module Rack
  module OAuth2
    class Server

      # Access token. This is what clients use to access resources.
      #
      # An access token is a unique code, associated with a client, an identity
      # and scope. It may be revoked, or expire after a certain period.
      class AccessToken
        class << self
          # Find AccessToken from token. Does not return revoked tokens.
          def from_token(token)
            Server.new_instance self, collection.find_one({ :_id=>token, :revoked=>nil })
          end

          # Get an access token (create new one if necessary).
          def get_token_for(identity, scope, client_id)
            scope = scope.split.sort.join(" ") # Make sure always in same order.
            unless token = collection.find_one({ :identity=>identity.to_s, :scope=>scope, :client_id=>client_id })
              token = { :_id=>Server.secure_random, :identity=>identity.to_s, :scope=>scope, :client_id=>client_id,
                        :created_at=>Time.now.utc, :expires_at=>nil, :revoked=>nil }
              collection.insert token
            end
            Server.new_instance self, token
          end

          # Find all AccessTokens for an identity.
          def from_identity(identity)
            collection.find({ :identity=>identity }).map { |fields| Server.new_instance self, fields }
          end

          def collection
            Server.database["oauth2.access_tokens"]
          end
        end

        # Access token. As unique as they come.
        attr_reader :_id
        alias :token :_id
        # The identity we authorized access to.
        attr_reader :identity
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
        
        Server.create_indexes do
          # Used to revoke all pending access grants when revoking client.
          collection.create_index [[:client_id, Mongo::ASCENDING]]
          # Used to get/revoke access tokens for an identity, also to find and
          # return existing access token.
          collection.create_index [[:identity, Mongo::ASCENDING]]
        end
      end

    end
  end
end
