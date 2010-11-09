class OauthController < ApplicationController
  before_filter do |c|
    c.send :head, c.oauth.deny! if c.oauth.scope.include?("time-travel") # Only Superman can do that
  end

  def authorize
    render :text=>"client: #{oauth.client.display_name}\nscope: #{oauth.scope.join(", ")}\nauthorization: #{oauth.authorization}"
  end

  def grant
    head oauth.grant!(params["authorization"], "Batman")
  end

  def deny
    head oauth.deny!(params["authorization"])
  end
end
