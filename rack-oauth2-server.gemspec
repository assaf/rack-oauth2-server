$: << File.dirname(__FILE__) + "/lib"
require "rack/oauth2/server/version"

Gem::Specification.new do |spec|
  spec.name           = "rack-oauth2-server"
  spec.version        = Rack::OAuth2::Server::VERSION
  spec.author         = "Assaf Arkin"
  spec.email          = "assaf@labnotes.org"
  spec.homepage       = "http://github.com/assaf/#{spec.name}"
  spec.summary        = "OAuth 2.0 Authorization Server as a Rack module"
  spec.description    = "Because you don't allow strangers into your app, and OAuth 2.0 is the new awesome."
  spec.post_install_message = ""

  spec.files          = Dir["{bin,lib,rails,test}/**/*", "CHANGELOG", "MIT-LICENSE", "README.rdoc", "Rakefile", "Gemfile", "*.gemspec"]

  spec.has_rdoc         = true
  spec.extra_rdoc_files = "README.rdoc", "CHANGELOG"
  spec.rdoc_options     = "--title", "rack-oauth2-server #{spec.version}", "--main", "README.rdoc",
                          "--webcvs", "http://github.com/assaf/#{spec.name}"

  spec.required_ruby_version = '>= 1.8.7'
  spec.add_dependency "rack", "~>1"
  spec.add_dependency "mongo", "~>1"
  spec.add_dependency "bson_ext"
end
