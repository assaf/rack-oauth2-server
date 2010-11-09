class ApiController < ApplicationController

  oauth_required :only=>[:private, :change]
  oauth_required :only=>[:calc], :scope=>"math"

  def public
    if oauth.authenticated?
      render :text=>"HAI from #{oauth.identity}"
    else
      render :text=>"HAI"
    end
  end

  def private
    render :text=>"Shhhh"
  end

  def change
    render :text=>"Woot!"
  end

  def calc
    render :text=>"2+2=4"
  end

  def list_tokens
    render :text=>oauth.list_access_tokens("Batman").map(&:token).join(" ")
  end

  def user
    render :text=>current_user.to_s
  end

protected

  def current_user
     @current_user ||= oauth.identity if oauth.authenticated?
  end
  
end
