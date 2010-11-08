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


  def setup
    super
  end

  def without_scope
    token = Rack::OAuth2::Server::AccessToken.get_token_for("Superman", "nobody", client.id)
    header "Authorization", "OAuth #{token.token}"
  end

  def with_scope
    token = Rack::OAuth2::Server::AccessToken.get_token_for("Superman", "oauth-admin", client.id)
    header "Authorization", "OAuth #{token.token}"
  end

  def json
    JSON.parse(last_response.body)
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

    context "with scope" do
      setup { with_scope ; get "/oauth/admin/api/clients" }
      should "return OK" do
        assert_equal 200, last_response.status
      end
      should "return JSON document" do
        assert_equal "application/json;charset=utf-8", last_response.content_type
      end
      should "return list of clients" do
        assert Array === json["list"]
      end
    end

    context "client" do
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
            tokens << Rack::OAuth2::Server::AccessToken.get_token_for("Superman", days.to_s, client.id)
          end
        end
        # Revoke one token today (within past 7 days), one 10 days ago (beyond)
        tokens.first.revoke!
        tokens.last.revoke!
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
        assert_equal "application/json;charset=utf-8", last_response.content_type
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
