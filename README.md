# Rack::OAuth2::Server

OAuth 2.0 Authorization Server as a Rack module. Because you don't allow strangers into your app, and [OAuth
2.0](http://tools.ietf.org/html/draft-ietf-oauth-v2-10) is the new awesome.

![Build status](http://travis-ci.org/assaf/rack-oauth2-server.png?branch=master)

For more background, [check out the presentation slides](http://speakerdeck.com/u/assaf/p/oauth-20).


## Adding OAuth 2.0 To Your Application

### Step 1: Setup Your Database

The authorization server needs to keep track of clients, authorization requests, access grants and access tokens. That
could only mean one thing: a database.

The current release uses [MongoDB](http://www.mongodb.org/). You're going to need a running server and open connection in
the form of a `Mongo::DB` object.  Because MongoDB is schema-less, there's no need to run migrations.

If MongoDB is not your flavor, you can easily change the models to support a different database engine. All the
persistence logic is located in `lib/rack/oauth2/models` and kept simple by design. And if you did the work to support a
different database engine, send us a pull request.


### Step 2: Use The Server

For Rails 2.3/3.0, `Rack::OAuth2::Server` automatically adds itself as middleware when required, but you do need to
configure it from within `config/environment.rb` (or one of the specific environment files). For example:

```
Rails::Initializer.run do |config|
  . . .
  config.after_initialize do
    config.oauth.database = Mongo::Connection.new["my_db"]
    config.oauth.authenticator = lambda do |username, password|
      user = User.find(username)
      user.id if user && user.authenticated?(password)
    end
  end
end
```

For Sinatra and Padrino, first require `rack/oauth2/sinatra` and register `Rack::OAuth2::Sinatra` into your application.
For example:

```
require "rack/oauth2/sinatra"

class MyApp < Sinatra::Base
  register Rack::OAuth2::Sinatra

  oauth.database = Mongo::Connection.new["my_db"]
  oauth.scope = %w{read write}
  oauth.authenticator = lambda do |username, password|
    user = User.find(username)
    user if user && user.authenticated?(password)
  end

  . . .
end
```

With any other Rack server, you can `use Rack::OAuth2::Server` and pass your own `Rack::OAuth2::Server::Options` object.

The configuration options are:

- `:access_token_path`- Path for requesting access token. By convention defaults to `/oauth/access_token`.
- `:authenticator` - For username/password authorization. A block that receives the credentials and returns identity
  string (e.g. user ID) or nil.
- `:authorization_types` - Array of supported authorization types. Defaults to `["code", "token"]``, and you can change
  it to just one of these names.
- `:authorize_path` -  Path for requesting end-user authorization. By convention defaults to `/oauth/authorize`.
- `:database` - `Mongo::DB` instance (this is a global setting).
- `:expires_in` - Number of seconds an auth token will live. If `nil` or zero, access token never expires.
- `:host` - Only check requests sent to this host.
- `:path` - Only check requests for resources under this path.
- `:param_authentication` - If true, supports authentication using query/form parameters.
- `:realm` - Authorization realm that will show up in 401 responses. Defaults to use the request host name.
- `:logger` - The logger to use. Under Rails, defaults to use the Rails logger.  Will use `Rack::Logger` if available.
- `:collection_prefix` - Prefix to use for MongoDB collections created by rack-oauth2-server. Defaults to `oauth2`.

If you only intend to use the UI authorization flow, you don't need to worry about the authenticator. If you want to
allow client applications to create access tokens by passing the end-user's username/password, then you need an
authenticator. This feature is necessary for some client applications, and quite handy during development/testing.

The authenticator is a block that receives either two or four parameters.  The first two are username and password. The
other two are the client identifier and scope. It authenticated, it returns an identity, otherwise it can return nil or
false. For example:

```
oauth.authenticator = lambda do |username, password|
  user = User.find_by_username(username)
  user.id if user && user.authenticated?(password)
end
```

### Step 3: Let Users Authorize

Authorization requests go to `/oauth/authorize`. Rack::OAuth2::Server intercepts these requests and validates the client
ID, redirect URI, authorization type and scope. If the request fails validation, the user is redirected back to the
client application with a suitable error code.

If the request passes validation, `Rack::OAuth2::Server` sets the request header `oauth.authorization` to the
authorization handle, and passes control to your application. Your application will ask the user to grant or deny the
authorization request.

Once granted, your application signals the grant by setting the response header `oauth.authorization` to the
authorization handle it got before, and setting the response header `oauth.identity` to the authorized identity. This is
typicaly the user ID or account ID, but can be anything you want, as long as it's a string. Rack::OAuth2::Server
intercepts this response and redirects the user back to the client application with an authorization code or access
token.

To signal that the user denied the authorization requests your application sets the response header
`oauth.authorization` as before, and returns the status code 403 (Forbidden). Rack::OAuth2::Server will then redirect
the user back to the client application with a suitable error code.

In Rails, the entire flow would look something like this:

```
class OauthController < ApplicationController
  def authorize
    if current_user
      render :action=>"authorize"
    else
      redirect_to :action=>"login", :authorization=>oauth.authorization
    end
  end

  def grant
    head oauth.grant!(current_user.id)
  end

  def deny
    head oauth.deny!
  end
end
```

Rails actions must render something. The oauth method returns a helper object (`Rack::OAuth2::Server::Helper`) that
cannot render anything, but can set the right response headers and return a status code, which we then pass on to the
`head` method.

In Sinatra/Padrino, it would look something like this:

```
get "/oauth/authorize" do
  if current_user
    render "oauth/authorize"
  else
    redirect "/oauth/login?authorization=#{oauth.authorization}"
  end
end

post "/oauth/grant" do
  oauth.grant! "Superman"
end

post "/oauth/deny" do
  oauth.deny!
end
```

The view would look something like this:

```
<h2>The application <% link_to h(oauth.client.display_name), oauth.client.link %>
  is requesting to <%= oauth.scope.to_sentence %> your account.</h2>
<form action="/oauth/grant">
  <button>Grant</button>
  <input type="hidden" name="authorization" value="<%= oauth.authorization %>">
</form>
<form action="/oauth/deny">
  <button>Deny</button>
  <input type="hidden" name="authorization" value="<%= oauth.authorization %>">
</form>
```


### Step 4: Protect Your Path

Rack::OAuth2::Server intercepts all incoming requests and looks for an Authorization header that uses `OAuth`
authentication scheme, like so:

```
Authorization: OAuth e57807eb99f8c29f60a27a75a80fec6e
```

It can also support the `oauth_token` query parameter or form field, if you set `param_authentication` to true. This
option is off by default to prevent conflict with OAuth 1.0 callback.

If Rack::OAuth2::Server finds a valid access token in the request, it sets the request header `oauth.identity` to the
value you supplied during authorization (step 3). You can use `oauth.identity` to resolve the access token back to user,
account or whatever you put there.

If the access token is invalid or revoked, it returns 401 (Unauthorized) to the client. However, if there's no access
token, the request goes through. You might want to protect some URLs but not others, or allow authenticated and
unauthenticated access, the former returning more data or having higher rate limit, etc.

It is up to you to reject requests that must be authenticated but are not. You can always just return status code 401,
but it's better to include a proper `WWW-Authenticate` header, which you can do by setting the response header
`oauth.no_access` to true, or using `oauth_required` to setup a filter.

You may also want to reject requests that don't have the proper scope. You can return status code 403, but again it's
better to include a proper `WWW-Authenticate` header with the required scope. You can do that by setting the response
header `oauth.no_scope` to the scope name, or using `oauth_required` with the scope option.

In Rails, it would look something like this:

```
class MyController < ApplicationController

  before_filter :set_current_user
  oauth_required :only=>:private
  oauth_required :only=>:calc, :scope=>"math"

  # Authenticated/un-authenticated get different responses.
  def public
    if oauth.authenticated?
      render :action=>"more-details"
    else
      render :action=>"less-details"
    end
  end

  # Must authenticate to retrieve this.
  def private
    render
  end

  # Must authenticate with scope math to do this.
  def calc
    render :text=>"2+2=4"
  end

protected

  def set_current_user
    @current_user = User.find(oauth.identity) if oauth.authenticated?
  end

end
```

In Sinatra/Padrino, it would look something like this:

```
before do
  @current_user = User.find(oauth.identity) if oauth.authenticated?
end

oauth_required "/private"
oauth_required "/calc", :scope=>"math"

# Authenticated/un-authenticated get different responses.
get "/public" do
  if oauth.authenticated?
    render "more-details"
  else
    render "less-details"
  end
end

# Must authenticate to retrieve this.
get "/private" do
  render "secrets"
end

# Must authenticate with scope math to do this.
get "/calc" do
  render "2 + 2 = 4"
end
```


### Step 5: Register Some Clients

Before a client application can request access, there must be a client record in the database. Registration provides the
client application with a client ID and secret. The client uses these to authenticate itself.

The client provides its display name, site URL and image URL. These should be shown to the end-user to let them know
which client application they're granting access to.

Clients can also register a redirect URL. This is optional but highly recommended for better security, preventing other
applications from hijacking the client's ID/secret.

You can register clients using the command line tool `oauth2-server`:

```
$ oauth2-server register --db my_db
```

Or you can register clients using the Web-based OAuth console, see below.

Programatically, registering a new client is as simple as:

```
$ ./script/console
Loading development environment (Rails 2.3.8)
> client = Rack::OAuth2::Server.register(:display_name=>"UberClient",
   :link=>"http://example.com/",
   :image_url=>"http://farm5.static.flickr.com/4122/4890273282_58f7c345f4.jpg",
   :scope=>%{read write},
   :redirect_uri=>"http://example.com/oauth/callback")
> puts "Your client identifier: #{client.id}"
> puts "Your client secret: #{client.secret}"
```

You may want your application to register its own client application, always with the same client ID and secret, which
are also stored in a configuration file. For example, your `db/seed.rb` may contain:

```
oauth2 = YAML.load_file(Rails.root + "config/oauth2.yml")
Rack::OAuth2::Server.register(id: oauth2["client_id"], secret: oauth2["client_secret"],
  display_name: "UberClient", link: "http://example.com",
  redirect_uri: "http://example.com/oauth/callback", scope: oauth2["scope"].split)
```

When you call `register` with `id` and `secret` parameters it either registers a new client with these specific ID and
sceret, or if a client already exists, updates its other properties.


### Step 6: Pimp Your API

I'll let you figure that one for yourself.


## Two-legged OAuth flow

Rack::OAuth2::Server also supports the so-called "two-legged" OAuth flow, which does not require the end user
authorization process. This is typically used in server to server scenarios where no user is involved. To utilize the
two-legged flow, send the grant_type of "none" along with the client_id and client_secret to the access token path, and
a new access token will be generated (assuming the client_id and client_secret check out).


## OAuth Web Admin

We haz it, and it's pretty rad!

![Web admin](http://labnotes.org/wp-content/uploads/2010/11/OAuth-Admin-All-Clients.png)

To get the Web admin running, you'll need to do the following. First, you'll need to register a new client application
that can access the OAuth Web admin, with the scope `oauth-scope` and redirect_uri that points to where you plan the Web
admin to live. This URL must end with `/admin`, for example, `http://example.com/oauth/admin`.

The easiest way to do this is to run the `oauth2-sever` command line tool:

```
$ oauth2-server setup --db my_db
```

Next, in your application, make sure to ONLY AUTHORIZE ADMINISTRATORS to access the Web admin, by granting them access
to the `oauth-admin` scope. For example:

```
def grant
  # Only admins allowed to authorize the scope oauth-admin
  if oauth.scope.include?("oauth-admin") && !current_user.admin?
    head oauth.deny!
  else
    head oauth.grant!(current_user.id)
  end
end
```

Make sure you do that, or you'll allow anyone access to the OAuth Web admin.

After this, remember to include the server admin module in your initializer (environemnt.rb or application.rb), because
this is an optional feature:

```
require "rack/oauth2/server/admin"
```

Next, mount the OAuth Web admin as part of your application, and feed it the client ID/secret. For example, for Rails
2.3.x add this to `config/environment.rb`:

```
Rails::Initializer.run do |config|
  . . .
  config.after_initialize do
    config.middleware.use Rack::OAuth2::Server::Admin.mount
    Rack::OAuth2::Server::Admin.set :client_id, "4dca20453e4859cb000007"
    Rack::OAuth2::Server::Admin.set :client_secret, "981fa734e110496fcf667cbf52fbaf03"
    Rack::OAuth2::Server::Admin.set :scope, %w{read write}
  end
end
```

For Rails 3.0.x, add this to you `config/application.rb`:

```
  module MyApp
    class Application < Rails::Application
      config.after_initialize do
        Rack::OAuth2::Server::Admin.set :client_id, "4dca20453e4859cb000007"
        Rack::OAuth2::Server::Admin.set :client_secret, "981fa734e110496fcf667cbf52fbaf03"
        Rack::OAuth2::Server::Admin.set :scope, %w{read write}
      end
    end
  end
```

And add the follownig to `config/routes.rb`:

mount Rack::OAuth2::Server::Admin=>"/oauth/admin"

For Sinatra, Padrino and other Rack-based applications, you'll want to mount like so (e.g. in `config.ru`):

```
Rack::Builder.new do
  map("/oauth/admin") { run Rack::OAuth2::Server::Admin }
  map("/") { run MyApp }
end
Rack::OAuth2::Server::Admin.set :client_id, "4dca20453e4859cb000007"
Rack::OAuth2::Server::Admin.set :client_secret, "981fa734e110496fcf667cbf52fbaf03"
Rack::OAuth2::Server::Admin.set :scope, %w{read write}
```

Next, open your browser to `http://example.com/oauth/admin`, or wherever you mounted the Web admin.


### Web Admin Options

You can set the following options:

- `client_id` - Client application identified, require to authenticate.
- `client_secret` - Client application secret, required to authenticate.
- `authorize` - Endpoint for requesing authorization, defaults to `/oauth/admin`.
- `template_url` - Will map an access token identity into a URL in your application, using the substitution value
  `{id}`, e.g.  `http://example.com/users/#{id}`)
- `force_ssl` - Forces all requests to use HTTPS (true by default except in development mode).
- `scope` - Common scope shown and added by default to new clients (array of names, e.g. `["read", "write"]``).


### Web Admin API

The OAuth Web admin is a single-page client application that operates by accessing the OAuth API. The API is mounted at
`/oauth/admin/api` (basically /api relative to the UI), you can access it yourself if you have an access token with the
scope `oauth-admin`.

The API is undocumented, but between the very simple Sinatra code that provides he API, and just as simple Sammy.js code
that consumes it, it should be easy to piece together.


## OAuth 2.0 With Curl

The premise of OAuth 2.0 is that you can use it straight from the command line.  Let's start by creating an access
token. Aside from the UI authorization flow, OAuth 2.0 allows you to authenticate with username/password. You'll need to
register an authenticator, see step 2 above for details.

Now make a request using the client credentials and your account username/password, e.g.:

```
$ curl -i http://localhost:3000/oauth/access_token \
  -F grant_type=password \
  -F client_id=4dca20453e4859cb000007 \
  -F client_secret=981fa734e110496fcf667cbf52fbaf03 \
  -F "scope=read write" \
  -F username=assaf@labnotes.org \
  -F password=not.telling
```

This will spit out a JSON document, something like this:

```
{ "scope":"import discover contacts lists",
  "access_token":"e57807eb99f8c29f60a27a75a80fec6e" }
```

Grab the `access_token` value and use it. The access token is good until you delete it from the database. Making a
request using the access token:

```
$ curl -i http://localhost:3000/api/read -H "Authorization: OAuth e57807eb99f8c29f60a27a75a80fec6e"
```

Although not recommended, you can also pass the token as a query parameter, or when making POST request, as a form
field:

```
$ curl -i http://localhost:3000/api/read?oauth_token=e57807eb99f8c29f60a27a75a80fec6e
$ curl -i http://localhost:3000/api/update -F name=Superman -F oauth_token=e57807eb99f8c29f60a27a75a80fec6e
```

You'll need to set the option `param_authentication` to true. Watch out, since this query parameter could conflict with
OAuth 1.0 authorization responses that also use `oauth_token` for a different purpose.

Here's a neat trick. You can create a `.curlrc` file and load it using the `-K` option:

```
$ cat .curlrc
header = "Authorization: OAuth e57807eb99f8c29f60a27a75a80fec6e"
$ curl -i http://localhost:3000/api/read -K .curlrc
```

If you create `.curlrc` in your home directory, `curl` will automatically load it.  Convenient, but dangerous, you might
end up sending the access token to any server you `curl`. Useful for development, testing, just don't use it with any
production access tokens.


## Methods You'll Want To Use From Your App

You can use the Server module to create, fetch and otherwise work with access tokens and grants. Available methods
include:

- `access_grant` - Creates and returns a new access grant. You can use that for one-time token, e.g. users who forgot
  their password and need to login using an email message.
- `token_for` -- Returns access token for particular identity. You can use that to give access tokens to clients other
  than through the OAuth 2.0 protocol, e.g.  if you let users authenticate using Facebook Connect or Twitter OAuth.
- `get_access_token` -- Resolves access token (string) into access token (`AccessToken` object).
- `list_access_tokens` -- Returns all access tokens for a given identity, which you'll need if you offer a UI for uses
  to review and revoke access tokens they previously granted.
- `get_client -- Resolves client identifier into a `Client` object.
- `register` -- Registers a new client application. Can also be used to change existing registration (if you know the
  client's ID and secret). Idempotent, so perfect for running during setup and migration.
- `get_auth_request` -- Resolves authorization request handle into an `AuthRequest` object. Could be useful during the
  authorization flow.


## Mandatory ASCII Diagram

This is briefly what the authorization flow looks like, how the workload is split between Rack::OAuth2::Server and your
application, and the protocol the two use to control the authorization flow:

```
                           Rack::OAuth2::Server
              -----------------------    -----------------------
Client app    | /oauth/authorize    |    | Set request.env     |
redirect   -> |                     | -> |                     | ->
              | authenticate client |    | oauth.authorization |
              -----------------------    -----------------------

                                  Your code
   --------------------     ----------------------    -----------------------
   | Authenticate user |    | Ask user to grant/ |    | Set response        |
-> |                   | -> | deny client access | -> |                     | ->
   |                   |    | to their account   |    | oauth.authorization |
   |                   |    |                    |    | oauth.identity      |
   --------------------     ----------------------    -----------------------

    Rack::OAuth2::Server
   -----------------------
   | Create access grant |
-> | or access token for | -> Redirect back
   | oauth.identity      |    to client app
   -----------------------
```


## Understanding the Models

### Client

The `Rack::OAuth2::Server::Client` model represents the credentials of a client application. There are two pairs: the
client identifier and secret, which the client uses to identify itself to the authorization server, and the display name
and URL, which the client uses to identify itself to the end user.

The client application is not tied to a single `Client` record. Specifically, if the client credentials are compromised,
you'll want to revoke it and create a new `Client` with new pair of identifier/secret. You can leave the revoked
instance around.

Calling `revoke!` on the client revokes access using these credential pair, and also revokes any outstanding
authorization requests, access grants and access tokens created using these credentials.

You may also want to register a redirect URI. If registered, the client is only able to request authorization that
redirect back to that redirect URI.

### Authorization Request

The authorization process may involve multiple requests, and the application must maintain the authorization request
details from beginning to end.

To keep the application simple, all the necessary information for a single authorization request is stored in the
`Rack::OAuth2::Server::AuthRequest` model. The application only needs to keep track of the authorization request
identifier.

Granting an authorization request (by calling `grant!`) creates an access grant or access token, depending on the
requested response type, and associates it with the identity.

### Access Grant

An access grant (`Rack::OAuth2::Server::AccessGrant`) is a nonce use to generate access token. This model keeps track of
the nonce (the "authorization code") and all the data it needs to create an access token.

### Access Token

An access token allows the client to access the resource with the given scope on behalf of a given identity. It keeps
track of the account identifier (supplied by the application), client identifier and scope (both supplied by the
client).

An `Rack::OAuth2::Server::AccessToken` is created by copying values from an `AuthRequest` or `AccessGrant`, and remains
in effect until revoked. (OAuth 2.0 access tokens can also expire, but we don't support expiration at the moment)


## Credits

Rack::OAuth2::Server was written to provide authorization/authentication for the Flowtown API. Thanks to
[Flowtown](http://flowtown.com) for making it happen and allowing it to be open sourced.

Rack::OAuth2::Server is available under the MIT license.
