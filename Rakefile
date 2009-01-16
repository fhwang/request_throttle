require 'rake'
require 'rake/testtask'
require 'rake/rdoctask'
require 'test/test_helper'

desc 'Default: run unit tests.'
task :default => :test

namespace :test do
  task :prepare do
    TestProcesses.start_all
  end
end

Rake::TestTask.new(:test) do |t|
  t.libs << 'lib'
  t.pattern = 'test/**/*_test.rb'
  t.verbose = true
end

desc 'Generate documentation for the request_throttle plugin.'
Rake::RDocTask.new(:rdoc) do |rdoc|
  rdoc.rdoc_dir = 'rdoc'
  rdoc.title    = 'RequestThrottle'
  rdoc.options << '--line-numbers' << '--inline-source'
  rdoc.rdoc_files.include('README')
  rdoc.rdoc_files.include('lib/**/*.rb')
end
