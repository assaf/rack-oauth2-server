require "test/setup"

class AdminApiTest < Test::Unit::TestCase
  module Helpers
    def should_fail_authentication
      should "respond with status 401 (Unauthorized)" do
        assert_equal 401, last_response.status
      end
    end

    def should_forbid_access
      should "respond with status 403 (Forbidden)" do
        assert_equal 403, last_response.status
      end
    end
  end
  extend Helpers


  def without_scope
    token = Server.token_for("Superman", client.id, "nobody")
    header "Authorization", "OAuth #{token}"
  end

  def with_scope
    token = Server.token_for("Superman", client.id, "oauth-admin")
    header "Authorization", "OAuth #{token}"
  end

  def json
    JSON.parse(last_response.body)
  end


  context "force SSL" do
    setup do
      Server::Admin.force_ssl = true
      with_scope
    end

    context "HTTP request" do
      setup { get "/oauth/admin/api/clients" }

      should "redirect to HTTPS" do
        assert_equal 302, last_response.status
        assert_equal "https://example.org/oauth/admin/api/clients", last_response.location
      end
    end

    context "HTTPS request" do
      setup { get "https://example.org/oauth/admin/api/clients" }

      should "serve request" do
        assert_equal 200, last_response.status
        assert Array === json["list"]
      end
    end

    teardown { Server::Admin.force_ssl = false }
  end


  # -- /oauth/admin/api/clients

  context "all clients" do
    context "without authentication" do
      setup { get "/oauth/admin/api/clients" }
      should_fail_authentication
    end

    context "without scope" do
      setup { without_scope ; get "/oauth/admin/api/clients" }
      should_forbid_access
    end

    context "proper request" do
      setup { with_scope ; get "/oauth/admin/api/clients" }
      should "return OK" do
        assert_equal 200, last_response.status
      end
      should "return JSON document" do
        assert_equal "application/json", last_response.content_type.split(";").first
      end
      should "return list of clients" do
        assert Array === json["list"]
      end
      should "return known scope" do
        assert_equal %w{read write}, json["scope"]
      end
    end

    context "client list" do
      setup do
        with_scope
        get "/oauth/admin/api/clients"
        @first = json["list"].first
      end

      should "provide client identifier" do
        assert_equal client.id.to_s, @first["id"]
      end
      should "provide client secret" do
        assert_equal client.secret, @first["secret"]
      end
      should "provide redirect URI" do
        assert_equal client.redirect_uri, @first["redirectUri"]
      end
      should "provide display name" do
        assert_equal client.display_name, @first["displayName"]
      end
      should "provide site URL" do
        assert_equal client.link, @first["link"]
      end
      should "provide image URL" do
        assert_equal client.image_url, @first["imageUrl"]
      end
      should "provide created timestamp" do
        assert_equal client.created_at.to_i, @first["created"]
      end
      should "provide link to client resource"do
        assert_equal ["/oauth/admin/api/client", client.id].join("/"), @first["url"]
      end
      should "provide link to revoke resource"do
        assert_equal ["/oauth/admin/api/client", client.id, "revoke"].join("/"), @first["revoke"]
      end
      should "provide scope for client" do
        assert_equal %w{oauth-admin read write}, @first["scope"]
      end
      should "tell if not revoked" do
        assert @first["revoked"].nil?
      end
    end

    context "revoked client" do
      setup do
        client.revoke!
        with_scope
        get "/oauth/admin/api/clients"
        @first = json["list"].first
      end

      should "provide revoked timestamp" do
        assert_equal client.revoked.to_i, @first["revoked"]
      end
    end

    context "tokens" do
      setup do
        tokens = []
        1.upto(10).map do |days|
          Timecop.travel -days*86400 do
            tokens << Server.token_for("Superman#{days}", client.id)
          end
        end
        # Revoke one token today (within past 7 days), one 10 days ago (beyond)
        Timecop.travel -7 * 86400 do
          Server.get_access_token(tokens[0]).revoke!
        end
        Server.get_access_token(tokens[1]).revoke!
        with_scope ; get "/oauth/admin/api/clients"
      end

      should "return total number of tokens" do
        assert_equal 11, json["tokens"]["total"]
      end
      should "return number of tokens created past week" do
        assert_equal 7, json["tokens"]["week"]
      end
      should "return number of revoked token past week" do
        assert_equal 1, json["tokens"]["revoked"]
      end
    end
  end


  # -- /oauth/admin/api/client/:id

  context "single client" do
    context "without authentication" do
      setup { get "/oauth/admin/api/client/#{client.id}" }
      should_fail_authentication
    end

    context "without scope" do
      setup { without_scope ; get "/oauth/admin/api/client/#{client.id}" }
      should_forbid_access
    end

    context "with scope" do
      setup { with_scope ; get "/oauth/admin/api/client/#{client.id}" }

      should "return OK" do
        assert_equal 200, last_response.status
      end
      should "return JSON document" do
        assert_equal "application/json", last_response.content_type.split(";").first
      end
      should "provide client identifier" do
        assert_equal client.id.to_s, json["id"]
      end
      should "provide client secret" do
        assert_equal client.secret, json["secret"]
      end
      should "provide redirect URI" do
        assert_equal client.redirect_uri, json["redirectUri"]
      end
      should "provide display name" do
        assert_equal client.display_name, json["displayName"]
      end
      should "provide site URL" do
        assert_equal client.link, json["link"]
      end
      should "provide image URL" do
        assert_equal client.image_url, json["imageUrl"]
      end
      should "provide created timestamp" do
        assert_equal client.created_at.to_i, json["created"]
      end
      should "provide link to client resource"do
        assert_equal ["/oauth/admin/api/client", client.id].join("/"), json["url"]
      end
      should "provide link to revoke resource"do
        assert_equal ["/oauth/admin/api/client", client.id, "revoke"].join("/"), json["revoke"]
      end
    end
  end

end
