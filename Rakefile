require "rake/testtask"

spec = Gem::Specification.load(Dir["*.gemspec"].first)

desc "Build the Gem"
task :build do
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
  sh "git tag v#{spec.version}"
  sh "git push --tag"
  puts "Building and pushing gem .."
  sh "gem push #{spec.name}-#{spec.version}.gem"
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

RUBIES = %w{1.8.7 1.9.2}
namespace :test do
  task :all=>["test:sinatra", "test:rails2", "test:rails3"]
  desc "Run all tests against Sinatra"
  task :sinatra do
    sh "rake test FRAMEWORK=sinatra"
  end
  desc "Run all tests against Rails"
  task :rails do
    sh "rake test FRAMEWORK=rails"
  end
  desc "Run all tests against Rails 2.3.x"
  task :rails2 do
    sh "env BUNDLE_GEMFILE=Rails2 rake test FRAMEWORK=rails"
  end
  desc "Run all tests against Rails 3.x"
  task :rails3 do
    sh "env BUNDLE_GEMFILE=Rails3 bundle exec rake test FRAMEWORK=rails"
  end

  desc "Test in all supported RVMs"
  task :rubies do
    RUBIES.each do |ruby|
      puts "*** #{ruby} ***"
      sh "rvm #{ruby}@rack-oauth2-server rake test:all"
      puts
    end
  end
end
task :default=>"test:all"

begin 
  require "yard"
  YARD::Rake::YardocTask.new do |doc|
    doc.files = FileList["lib/**/*.rb"]
  end
rescue LoadError
end

task :clobber do
  rm_rf %w{doc .yardoc *.gem}
end
