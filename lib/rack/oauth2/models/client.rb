module Rack
  module OAuth2
    class Server

      class Client

        class << self
          # Authenticate a client request. This method takes three arguments,
          # Find Client from client identifier.
          def find(client_id)
            id = BSON::ObjectId(client_id.to_s)
            Server.new_instance self, collection.find_one(id)
          rescue BSON::InvalidObjectId
          end

          # Create a new client. Client provides the following properties:
          # # :display_name -- Name to show (e.g. UberClient)
          # # :link -- Link to client Web site (e.g. http://uberclient.dot)
          # # :image_url -- URL of image to show alongside display name
          # # :redirect_uri -- Registered redirect URI.
          # # :scope -- List of names the client is allowed to request.
          # # :notes -- Free form text.
          # 
          # This method does not validate any of these fields, in fact, you're
          # not required to set them, use them, or use them as suggested. Using
          # them as suggested would result in better user experience.  Don't ask
          # how we learned that.
          def create(args)
            redirect_uri = Server::Utils.parse_redirect_uri(args[:redirect_uri]).to_s if args[:redirect_uri]
            scope = Server::Utils.normalize_scope(args[:scope])
            fields =  { :display_name=>args[:display_name], :link=>args[:link],
                        :image_url=>args[:image_url], :redirect_uri=>redirect_uri,
                        :notes=>args[:notes].to_s, :scope=>scope,
                        :created_at=>Time.now.to_i, :revoked=>nil }
            if args[:id] && args[:secret]
              fields[:_id], fields[:secret] = BSON::ObjectId(args[:id].to_s), args[:secret]
              collection.insert(fields, :safe=>true)
            else
              fields[:secret] = Server.secure_random
              fields[:_id] = collection.insert(fields)
            end
            Server.new_instance self, fields
          end

          # Lookup client by ID, display name or URL.
          def lookup(field)
            id = BSON::ObjectId(field.to_s)
            Server.new_instance self, collection.find_one(id)
          rescue BSON::InvalidObjectId
            Server.new_instance self, collection.find_one({ :display_name=>field }) || collection.find_one({ :link=>field })
          end

          # Returns all the clients in the database, sorted alphabetically.
          def all
            collection.find({}, { :sort=>[[:display_name, Mongo::ASCENDING]] }).
              map { |fields| Server.new_instance self, fields }
          end

          # Deletes client with given identifier (also, all related records).
          def delete(client_id)
            id = BSON::ObjectId(client_id.to_s)
            Client.collection.remove({ :_id=>id })
            AuthRequest.collection.remove({ :client_id=>id })
            AccessGrant.collection.remove({ :client_id=>id })
            AccessToken.collection.remove({ :client_id=>id })
          end

          def collection
            Server.database["oauth2.clients"]
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
        # Preferred image URL for this icon.
        attr_reader :image_url
        # Redirect URL. Supplied by the client if they want to restrict redirect
        # URLs (better security).
        attr_reader :redirect_uri
        # List of scope the client is allowed to request.
        attr_reader :scope
        # Free form fields for internal use.
        attr_reader :notes
        # Does what it says on the label.
        attr_reader :created_at
        # Timestamp if revoked.
        attr_accessor :revoked
        # Counts how many access tokens were granted.
        attr_reader :tokens_granted
        # Counts how many access tokens were revoked.
        attr_reader :tokens_revoked

        # Revoke all authorization requests, access grants and access tokens for
        # this client. Ward off the evil.
        def revoke!
          self.revoked = Time.now.to_i
          Client.collection.update({ :_id=>id }, { :$set=>{ :revoked=>revoked } })
          AuthRequest.collection.update({ :client_id=>id }, { :$set=>{ :revoked=>revoked } })
          AccessGrant.collection.update({ :client_id=>id }, { :$set=>{ :revoked=>revoked } })
          AccessToken.collection.update({ :client_id=>id }, { :$set=>{ :revoked=>revoked } })
        end

        def update(args)
          fields = [:display_name, :link, :image_url, :notes].inject({}) { |h,k| v = args[k]; h[k] = v if v; h }
          fields[:redirect_uri] = Server::Utils.parse_redirect_uri(args[:redirect_uri]).to_s if args[:redirect_uri]
          fields[:scope] = Server::Utils.normalize_scope(args[:scope])
          self.class.collection.update({ :_id=>id }, { :$set=>fields })
          self.class.find(id)
        end

        Server.create_indexes do
          # For quickly returning clients sorted by display name, or finding
          # client from a URL.
          collection.create_index [[:display_name, Mongo::ASCENDING]]
          collection.create_index [[:link, Mongo::ASCENDING]]
        end
      end

    end
  end
end
