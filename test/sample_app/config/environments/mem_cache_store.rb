config.cache_classes = false

# Full error reports are disabled and caching is turned on
config.action_controller.consider_all_requests_local = false
config.action_controller.perform_caching             = true

# Don't care if the mailer can't send
config.action_mailer.raise_delivery_errors = false

#session store, new memcache namespace between server restarts
memcache_options = {
  :compression => false,
  :debug => false,
  :namespace => "request_throttle_sample_app",
  :readonly => false,
  :urlencode => false
}

memcache_servers = [ '127.0.0.1:11211' ]

# memcache caching
config.cache_store = :mem_cache_store, memcache_servers, memcache_options

# memcache session store
config.action_controller.session_store = :mem_cache_store
