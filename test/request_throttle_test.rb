require 'rubygems'
require 'monitor'
require 'net/http'  
require 'test/test_helper'
require 'test/unit'

module RequestThrottleTestMethods
  include MonitorMixin

  @@memcache_checked = false
  
  def check_processes
    unless @@memcache_checked
      memcache = MemCache.new 'localhost:11211'
      begin
        memcache.get 'asdf'
      rescue MemCache::MemCacheError
        raise "Looks like you don't have memcache running. Try \"rake test:prepare\""
      end
      @@memcache_checked = true
    end
    unless @mongrels_checked
      ports.each do |port|
        http = Net::HTTP.new 'localhost', port
        begin
          resp, data = http.get '/'
        rescue Errno::ECONNREFUSED
          startup = "RAILS_GEM_VERSION=#{rails_gem_version} ./script/server -p #{port} -e #{rails_env}"
          raise "Need the app to be running at port #{port}. Try \"cd test/sample_app && #{startup}\""
        end
      end
      @mongrels_checked = true
    end
  end
  
  def accepted_posts_count
    Net::HTTP.get('localhost', '/posts', ports.first).to_i
  end
  
  def assert_posts_accepted(difference)
    count_at_start = accepted_posts_count
    yield
    count_at_end = accepted_posts_count
    assert_equal( difference, count_at_end - count_at_start )
  end
    
  def mongrel_config
    TestProcesses.tc_class_names_to_mongrel_configs[self.class.name]
  end
  
  def ports; mongrel_config[:ports]; end
    
  def rails_env; mongrel_config[:rails_env]; end
  
  def rails_gem_version; mongrel_config[:rails_gem_version]; end
  
  def try_post(port)
    req = Net::HTTP::Post.new '/posts/create'
    res = Net::HTTP.new('localhost', port).start do |http|
      http.read_timeout = 600
      http.request req
    end
    res
  end
  
  def test_only_one_at_a_time
    assert_posts_accepted(2) do
      thread1 = Thread.new do
        @started_thread1 = true
        res = try_post ports.first
        raise res.inspect unless res.class == Net::HTTPOK
        @finished_thread1 = true
      end
      sleep 0.1 until @started_thread1
      sleep 0.1 # maybe this helps us get to try_post(7000) before
                # try_post(7001)
      res = try_post ports.last
      raise res.inspect unless res.class == Net::HTTPServiceUnavailable
      thread1.join
      assert @finished_thread1
      res = try_post ports.last
      raise res.inspect unless res.class == Net::HTTPOK
    end
  end
end

class RequestThrottle_2_2_2_Test < Test::Unit::TestCase
  include RequestThrottleTestMethods
  
  def setup
    check_processes
    @reset_max_req_count = false
    rails_code = "PostsController.max_req_count_for_create = nil"
    `cd test/sample_app && RAILS_GEM_VERSION=#{rails_gem_version} ./script/runner -e #{rails_env} "#{rails_code}"`
  end
  
  def teardown
    if @reset_max_req_count
      rails_code = "PostsController.max_req_count_for_create = 1"
      `cd test/sample_app && RAILS_GEM_VERSION=#{rails_gem_version} ./script/runner -e #{rails_env} "#{rails_code}"`
    end
  end
  
  def test_one_hundred
    assert_posts_accepted(100) do
      @count = 0
      threads = []
      100.times do
        threads << Thread.new do
          port = (rand >= 0.5) ? 7000 : 7001
          res = try_post port
          while res.class == Net::HTTPServiceUnavailable
            sleep 0.5
            res = try_post port
          end
          synchronize do
            @count += 1
            if @count % 10 == 0
              puts "count is #{@count}"
            end
          end
        end
      end
      threads.each do |thread| thread.join; end
    end
  end

  def test_set_throttle_count_from_script_runner
    @reset_max_req_count = true
    rails_code = "PostsController.max_req_count_for_create = 2"
    `cd test/sample_app && RAILS_GEM_VERSION=#{rails_gem_version} ./script/runner -e #{rails_env} "#{rails_code}"`
    assert_posts_accepted(2) do
      thread_7000 = Thread.new do
        @started_7000 = true
        res = try_post 7000
        raise res.inspect unless res.class == Net::HTTPOK
      end
      sleep 0.1 until @started_7000
      sleep 0.1 # maybe this helps us get to try_post(7000) before try_post(7001)
      res = try_post 7001
      raise res.inspect unless res.class == Net::HTTPOK
      thread_7000.join
    end
  end
  
  def test_reset_request_count
    assert_posts_accepted(2) do
      thread_7000 = Thread.new do
        @started_7000 = true
        res = try_post 7000
        raise res.inspect unless res.class == Net::HTTPOK
      end
      sleep 0.1 until @started_7000
      sleep 0.1 # maybe this helps us get to try_post(7000) before try_post(7001)
      rails_code = "PostsController.reset_req_count_for_create"
      `cd test/sample_app && RAILS_GEM_VERSION=#{rails_gem_version} ./script/runner -e #{rails_env} "#{rails_code}"`
      res = try_post 7001
      raise res.inspect unless res.class == Net::HTTPOK
      thread_7000.join
    end
  end
end

class RequestThrottle_2_1_2_LibmemcachedStoreTest < Test::Unit::TestCase
  include RequestThrottleTestMethods
  
  def setup
    check_processes
  end
end

class RequestThrottle_2_1_2_MemCacheStoreTest < Test::Unit::TestCase
  include RequestThrottleTestMethods
  
  def setup
    check_processes
  end
end
