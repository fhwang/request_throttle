class PostsController < ApplicationController
  request_throttle :create, 1, :version => 'abcd'
  
  def initialize
    @memcache_key = "posts_count"
    init_post_count unless post_count_exists?
  end
  
  def index
    count = Rails.cache.increment(@memcache_key, 0)
    render :text => count.to_s
  end
  
  def create
    sleep 1
    count = Rails.cache.increment(@memcache_key, 1)
    render :text => count.to_s
  end
  
  protected
  
  def init_post_count
    Rails.cache.write(@memcache_key, '0', :expires_in => 1.month)
  end
  
  def post_count_exists?
    Rails.cache.increment(@memcache_key, 0)
  end
end
