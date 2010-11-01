class OauthController < ApplicationController
  def authorize
    session["oauth.authorization"] = oauth.authorization
    render :text=>"client: #{oauth.client.display_name}\nscope: #{oauth.scope.join(", ")}"
  end

  def grant
    head oauth.grant!(session["oauth.authorization"], "Superman")
  end

  def deny
    head oauth.deny!(session["oauth.authorization"])
  end
end
