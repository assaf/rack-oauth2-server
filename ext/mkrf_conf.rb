puts "\n\n\n\n\nin mkrf_conf.rb!"
require 'rubygems'
require 'rubygems/command.rb'
require 'rubygems/dependency_installer.rb' 

begin
  Gem::Command.build_args = ARGV
rescue NoMethodError
end 

inst = Gem::DependencyInstaller.new
begin
  if RUBY_PLATFORM != "java"
    inst.install "bson_ext"
  end
rescue => err
  puts err.inspect
  puts err.backtrace.join("\n")
  exit(1)
end 

# create dummy rakefile to indicate success
f = File.open(File.join(File.dirname(__FILE__), "Rakefile"), "w")
f.write("task :default\n")
f.close
