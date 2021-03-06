module RequestThrottle
  mattr_accessor :version
  
  def self.included(controller)
    controller.extend ClassMethods
  end
  
  def self.init_req_count(key)
    # This must start at 0 for some reason
    Rails.cache.write(key, '0', :expires_in => 1.month)
  end

  def self.max_req_count_memcache_key(c_class, c_action)
    mk = "#{c_class}##{c_action}:max_req_count"
    mk << "?version=#{version}" if version
    mk
  end
  
  def self.req_count_memcache_key(c_class, c_action)
    mk = "#{c_class}##{c_action}:req_count"
    mk << "?version=#{version}" if version
    mk
  end
  
  def self.reset_req_count(c_class, c_action)
    key = RequestThrottle.req_count_memcache_key(c_class, c_action)
    init_req_count key
  end
  
  def self.set_max_req_count_in_memcache(c_class, c_action, max_req_count)
    key = max_req_count_memcache_key(c_class, c_action)
    if max_req_count
      Rails.cache.write(key, max_req_count, :expires_in => 12.hours)
    else
      Rails.cache.delete key
    end
  end
  
  module ClassMethods
    def request_throttle(action, max_req_count)
      if perform_caching
        around_filter AroundFilter.new(max_req_count), :only => action
        class_eval <<-EVAL
          def self.max_req_count_for_#{action}=(max_req_count)
            RequestThrottle.set_max_req_count_in_memcache(#{self.name}, #{action.inspect}, max_req_count)
          end
          def self.reset_req_count_for_#{action}
            RequestThrottle.reset_req_count(#{self.name}, #{action.inspect})
          end
        EVAL
      end
    end
  end
  
  class AroundFilter
    def initialize(base_max_req_count)
      @base_max_req_count = base_max_req_count
    end
    
    def decrement_memcache(cache_store, mk)
      if RAILS_GEM_VERSION =~ /^2\.1\./ &&
        cache_store.is_a?(ActiveSupport::Cache::MemCacheStore)
        # dodging a bug in with MemCacheStore#decrement in Rails 2.1.x
        Rails.cache.increment mk, -1
      else
        Rails.cache.decrement mk
      end
    end
    
    def filter(controller)
      mk = memcache_key controller
      init_req_count(mk) unless Rails.cache.increment(mk, 0)
      incremented_req_count = Rails.cache.increment(mk, 1).to_i
      if incremented_req_count > max_req_count(controller)
        controller.send(:render, :status => 503, :text => '')
        decrement_memcache controller.cache_store, mk
        return
      end
      begin
        yield
      ensure
        # This is in an ensure block because the decrement always has to
        # happen, even if the yielded code raises an error.

        # There's a slim chance that the count would expire and be reset to 0
        # by another mongrel when there's a decrement outstanding.
        # Decrementing from zero will make memcache rollover the number to
        # some extremely high int, so we double-check the count value before
        # decrementing just to be sure.
        req_count = Rails.cache.increment(mk, 0)
        if req_count && req_count > 0
          decrement_memcache controller.cache_store, mk
        end
      end
    end
    
    def init_req_count(mk)
      RequestThrottle.init_req_count mk
    end
    
    def max_req_count(controller)
      mrc = Rails.cache.read(
        RequestThrottle.max_req_count_memcache_key(
          controller.class, controller.action_name
        )
      )
      mrc || @base_max_req_count
    end
    
    def memcache_key(controller)
      RequestThrottle.req_count_memcache_key(
        controller.class, controller.action_name
      )
    end
  end
end
