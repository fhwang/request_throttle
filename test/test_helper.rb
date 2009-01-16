require 'memcache'

module TestProcesses
  def self.tc_class_names_to_mongrel_configs
    {
      'RequestThrottle_2_2_2_Test' => {
        :ports => [7000,7001], :rails_env => 'mem_cache_store', 
        :rails_gem_version => '2.2.2'
      },
      'RequestThrottle_2_1_2_LibmemcachedStoreTest' => {
        :ports => [8000,8001], :rails_env => 'libmemcached_store', 
        :rails_gem_version => '2.1.2'
      },
      'RequestThrottle_2_1_2_MemCacheStoreTest' => {
        :ports => [9000,9001], :rails_env => 'mem_cache_store', 
        :rails_gem_version => '2.1.2'
      }
    }
  end

  def self.start_all
    threads = []
    threads << Thread.new do
      `memcached -p 11211`
    end
    tc_class_names_to_mongrel_configs.values.each do |mongrel_config|
      re = mongrel_config[:rails_env]
      rgv = mongrel_config[:rails_gem_version]
      mongrel_config[:ports].each do |p|
        threads << Thread.new(p, re, rgv) do |port, rails_env, rails_gem|
          `cd test/sample_app && RAILS_GEM_VERSION=#{rails_gem} ./script/server -p #{port} -e #{rails_env}`
        end
      end
    end
    threads.each do |t| t.join; end
  end
end
