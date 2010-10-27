module Rack
  module OAuth2
    module Models

      class Client

        class << self
          # Authenticate a client request. This method takes three arguments,
          # Find Client from client identifier.
          def find(client_id)
            id = BSON::ObjectId(client_id.to_s)
            Models.new_instance self, collection.find_one(id)
          end

          # Create a new client. Client is in control of their display name, site
          # and redirect URL.
          def create(display_name, link, redirect_uri)
            link = Server::Utils.parse_redirect_uri(link).to_s
            redirect_uri = Server::Utils.parse_redirect_uri(redirect_uri).to_s if redirect_uri
            fields = { :secret=>Models.secure_random, :display_name=>display_name, :link=>link,
                       :redirect_uri=>redirect_uri, :created_at=>Time.now.utc, :revoked=>nil }
            fields[:_id] = collection.insert(fields)
            Models.new_instance self, fields
          end

          def collection
            Models.db["oauth2.clients"]
          end
        end

        # Client identifier.
        attr_reader :_id
        alias :id :_id
        # Client secret: random, long, and hexy.
        attr_reader :secret
        # User see this.
        attr_reader :display_name
        # Link to client's Web site.
        attr_reader :link
        # Redirect URL. Supplied by the client if they want to restrict redirect
        # URLs (better security).
        attr_reader :redirect_uri
        # Does what it says on the label.
        attr_reader :created_at
        # Timestamp if revoked.
        attr_accessor :revoked

        # Revoke all authorization requests, access grants and access tokens for
        # this client. Ward off the evil.
        def revoke!
          self.revoked = Time.now.utc
          Client.collection.update({ :_id=>id }, { :$set=>{ :revoked=>revoked } })
          AuthRequest.collection.update({ :client_id=>id }, { :$set=>{ :revoked=>revoked })
          AccessGrant.collection.update({ :client_id=>id }, { :$set=>{ :revoked=>revoked } })
          AccessToken.collection.update({ :client_id=>id }, { :$set=>{ :revoked=>revoked } })
        end

        #collection.create_index [[:display_name, Mongo::ASCENDING]]
        #collection.create_index [[:link, Mongo::ASCENDING]]
      end

    end
  end
end
