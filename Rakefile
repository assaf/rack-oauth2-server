require "rake/testtask"

spec = Gem::Specification.load(Dir["*.gemspec"].first)

GEMFILE_MAP = {"Rails2" => "Rails 2.3", "Rails3" => "Rails 3.x", "Sinatra1.1" => "Sinatra 1.1", "Sinatra1.2" => "Sinatra 1.2", "Sinatra1.3" => "Sinatra 1.3"}

desc "Install dependencies"
task :setup do
  GEMFILE_MAP.each do |gemfile, name|
    puts "Installing gems for testing with #{name} ..."
    sh "env BUNDLE_GEMFILE=#{gemfile} bundle install"
  end
end

desc "Run all tests"
Rake::TestTask.new do |task|
  task.test_files = FileList['test/**/*_test.rb']
  if Rake.application.options.trace
    #task.warning = true
    task.verbose = true
  elsif Rake.application.options.silent
    task.ruby_opts << "-W0"
  else
    task.verbose = true
  end
    task.ruby_opts << "-I."
end

namespace :test do
  GEMFILE_MAP.each do |gemfile, name|
    desc "Run all tests against #{name}"
    task gemfile.downcase.gsub(/\./, "_") do
      sh "env BUNDLE_GEMFILE=#{gemfile} bundle exec rake"
    end
  end
  task :all=>GEMFILE_MAP.map {|gemfile, name| "test:#{gemfile.downcase.gsub(/\./, "_")}"}
end

desc "Run this in development mode when updating the CoffeeScript file"
task :coffee do
  sh "coffee -w -o lib/rack/oauth2/admin/js/ lib/rack/oauth2/admin/js/application.coffee"
end

task :compile do
  sh "coffee -c -l -o lib/rack/oauth2/admin/js/ lib/rack/oauth2/admin/js/application.coffee"
end

desc "Build the Gem"
task :build=>:compile do
  sh "gem build #{spec.name}.gemspec"
end

desc "Install #{spec.name} locally"
task :install=>:build do
  sudo = "sudo" unless File.writable?( Gem::ConfigMap[:bindir])
  sh "#{sudo} gem install #{spec.name}-#{spec.version}.gem"
end

desc "Push new release to gemcutter and git tag"
task :push=>["test:all", "build"] do
  sh "git push"
  puts "Tagging version #{spec.version} .."
  sh "git tag -a v#{spec.version}"
  sh "git push --tag"
  puts "Building and pushing gem .."
  sh "gem push #{spec.name}-#{spec.version}.gem"
end

task :default do
  ENV["FRAMEWORK"] = "rails"
  begin
    require "rails" # check for Rails3
  rescue LoadError
    begin
      require "initializer" # check for Rails2
    rescue LoadError
      ENV["FRAMEWORK"] = "sinatra"
    end
  end
  task("test").invoke
end


begin 
  require "yard"
  YARD::Rake::YardocTask.new do |doc|
    doc.files = FileList["lib/**/*.rb"]
  end
rescue LoadError
end

task :clean do
  rm_rf %w{doc .yardoc *.gem}
end
