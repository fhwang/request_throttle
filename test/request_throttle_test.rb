require 'rubygems'
require 'memcache'
require 'monitor'
require 'net/http'  
require 'test/unit'

class RequestThrottleTest < Test::Unit::TestCase
  include MonitorMixin
  
  def setup
    unless @full_setup
      memcache = MemCache.new 'localhost:11211'
      begin
        memcache.get 'asdf'
      rescue MemCache::MemCacheError
        raise "Looks like you don't have memcache running. Try \"memcached -d -p 11211\""
      end
      [7000,7001].each do |port|
        http = Net::HTTP.new 'localhost', port
        begin
          resp, data = http.get '/'
        rescue Errno::ECONNREFUSED
          raise "Need the app to be running at port #{port}. Try \"cd test/sample_app && ./script/server -e 2_2_2 -p #{port}\""
        end
      end
      rails_code = "PostsController.max_req_count_for_create = nil"
      `cd test/sample_app && ./script/runner -e 2_2_2 "#{rails_code}"`
      @full_setup = true
    end
    @reset_max_req_count = false
  end
  
  def teardown
    if @reset_max_req_count
      rails_code = "PostsController.max_req_count_for_create = 1"
      `cd test/sample_app && ./script/runner -e 2_2_2 "#{rails_code}"`
    end
  end
  
  def accepted_posts_count
    Net::HTTP.get('localhost', '/posts', '7000').to_i
  end
  
  def assert_posts_accepted(difference)
    count_at_start = accepted_posts_count
    yield
    count_at_end = accepted_posts_count
    assert_equal( difference, count_at_end - count_at_start )
  end
  
  def try_post(port)
    req = Net::HTTP::Post.new '/posts/create'
    res = Net::HTTP.new('localhost', port).start do |http|
      http.read_timeout = 600
      http.request req
    end
    res
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
  
  def test_only_one_at_a_time
    assert_posts_accepted(2) do
      thread_7000 = Thread.new do
        @started_7000 = true
        res = try_post 7000
        raise res.inspect unless res.class == Net::HTTPOK
        @finished_7000 = true
      end
      sleep 0.1 until @started_7000
      sleep 0.1 # maybe this helps us get to try_post(7000) before try_post(7001)
      res = try_post 7001
      raise res.inspect unless res.class == Net::HTTPServiceUnavailable
      thread_7000.join
      assert @finished_7000
      res = try_post 7001
      raise res.inspect unless res.class == Net::HTTPOK
    end
  end

  def test_set_throttle_count_from_script_runner
    @reset_max_req_count = true
    rails_code = "PostsController.max_req_count_for_create = 2"
    `cd test/sample_app && ./script/runner -e 2_2_2 "#{rails_code}"`
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
end
