module RequestThrottle
  mattr_accessor :version
  
  def self.included(controller)
    controller.extend ClassMethods
  end
  
  def self.req_count_memcache_key(c_class, c_action)
    mk = "#{c_class}##{c_action}:req_count"
    mk << "?version=#{version}" if version
    mk
  end
  
  module ClassMethods
    def request_throttle(action, max_req_count)
      if perform_caching
        around_filter AroundFilter.new(max_req_count), :only => action
      end
    end
  end
  
  class AroundFilter
    def initialize(max_req_count)
      @max_req_count = max_req_count
    end
    
    def filter(controller)
      too_many = false
      mk = memcache_key controller
      req_count = Rails.cache.increment(mk, 0)
      controller.logger.info "req_count #{req_count.inspect}"
      if req_count
        req_count = req_count.to_i
        if req_count >= @max_req_count
          controller.send(:render, :status => 503, :text => '')
          too_many = true
        else
          Rails.cache.increment mk, 1
        end
      else
        # This must start at 0 for some reason
        Rails.cache.write(mk, '0', :expires_in => 1.month )
        Rails.cache.increment mk, 1
      end
      unless too_many
        begin
          yield
        ensure
          # This is in an ensure block because the decrement always has to
          # happen, even if the yielded code raises an error.
          
          # There's a slim chance that the count would expire and be reset to
          # 0 by another mongrel when there's a decrement outstanding.
          # Decrementing from zero will make memcache rollover the number to 
          # some extremely high int, so we double-check the count value before 
          # decrementing just to be sure.
          req_count = Rails.cache.increment(mk, 0)
          if req_count && req_count > 0
            Rails.cache.increment(mk, -1)
          end
        end
      end
    end
    
    def memcache_key(controller)
      RequestThrottle.req_count_memcache_key(
        controller.class, controller.action_name
      )
    end
  end
end
