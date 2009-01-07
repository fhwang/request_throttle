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
          raise "Need the app to be running at port #{port}. Try \"cd test/sample_app && ./script/server -p #{port}\""
        end
      end
      @full_setup = true
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
  
  def test_only_one_at_a_time
    assert_posts_accepted(2) do
      thread_7000 = Thread.new do
        res = nil
        synchronize do
          @started_7000 = true
          res = try_post 7000
        end
        raise res.inspect unless res.class == Net::HTTPOK
        @finished_7000 = true
      end
      sleep 0.1 until @started_7000
      res = try_post 7001
      raise res.inspect unless res.class == Net::HTTPServiceUnavailable
      thread_7000.join
      assert @finished_7000
      res = try_post 7001
      raise res.inspect unless res.class == Net::HTTPOK
    end
  end
end
