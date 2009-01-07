# Filters added to this controller apply to all controllers in the application.
# Likewise, all the methods added will be available for all controllers.

class ApplicationController < ActionController::Base
  session :off
  self.allow_forgery_protection = false
  
  helper :all # include all helpers, all the time
  
  include RequestThrottle
end
