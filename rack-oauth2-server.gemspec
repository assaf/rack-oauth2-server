$: << File.dirname(__FILE__) + "/lib"

Gem::Specification.new do |spec|
  spec.name           = "rack-oauth2-server"
  spec.version        = IO.read("VERSION")
  spec.author         = "Assaf Arkin"
  spec.email          = "assaf@labnotes.org"
  spec.homepage       = "http://github.com/assaf/#{spec.name}"
  spec.summary        = "OAuth 2.0 Authorization Server as a Rack module"
  spec.description    = "Because you don't allow strangers into your app, and OAuth 2.0 is the new awesome."
  spec.post_install_message = "To get started, run the command oauth2-server"

  spec.files          = Dir["{bin,lib,rails,test}/**/*", "CHANGELOG", "VERSION", "MIT-LICENSE", "README.md", "Rakefile", "Gemfile", "*.gemspec"]
  spec.executable     = "oauth2-server"

  spec.extra_rdoc_files = "README.md", "CHANGELOG"
  spec.rdoc_options     = "--title", "rack-oauth2-server #{spec.version}", "--main", "README.md",
                          "--webcvs", "http://github.com/assaf/#{spec.name}"
  spec.license          = "MIT"

  spec.required_ruby_version = '>= 1.8.7'
  spec.add_dependency "rack", "~>1.4.5"
  spec.add_dependency "mongo", "~>1"
  spec.add_dependency "bson_ext"
  spec.add_dependency "sinatra", "~>1.3"
  spec.add_dependency "json"
  spec.add_dependency "jwt", "~>0.1.8"
  spec.add_dependency "iconv"
  spec.add_development_dependency 'rake', '~>10.0.4'
  spec.add_development_dependency 'rack-test', '~>0.6.2'
  spec.add_development_dependency 'shoulda', '~>3.4.0'
  spec.add_development_dependency 'timecop', '~>0.5.9.1'
  spec.add_development_dependency 'ap', '~>0.1.1'
  spec.add_development_dependency 'crack', '~>0.3.2'
  spec.add_development_dependency 'rails', '~>3.2'
end
