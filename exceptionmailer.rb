require 'pony'
require 'erb'

module Rack
  class ExceptionMailer
    
    def initialize(app, options)
      @app =                    app
      @to =                     Array(options[:to]) # could be an array or just a string
      @from =                   options[:from] || 'errors@yourdomain.com' # should be string
      @subject =                options[:subject] || "Error Caught in Rack Application" # again, a string
      @template =               ERB.new(TEMPLATE) # the template built in here (non-mutable { for the moment })
    end
  
    def call(env)
      status, headers, body =
        begin
          @app.call(env)
        rescue => boom
          # TODO don't allow exceptions from send_notification to propogate
          begin
            send_notification boom, env
          rescue
            # just ignore it. we only care about the initial exception
          end
          
          raise
        end
      send_notification env['mail.exception'], env if env['mail.exception']
      [status, headers, body]
    end
    
    def send_notification(exception, env)
      body = @template.result(binding) # not sure about this "binding" thing
      
      # loop through each :to address and fire off an email with the error
      @to.each do |to|
        Pony.mail :to => to, :from => @from, :subject  => @subject, :body => body
      end
      
    end
    
    # don't really understand this but hey, why not?!
    def extract_body(env)
      if io = env['rack.input']
        io.rewind if io.respond_to?(:rewind)
        io.read
      end
    end
    
    
    TEMPLATE = (<<-'EMAIL').gsub(/^ {4}/, '')
    A <%= exception.class.to_s %> occured: <%= exception.to_s %>
    <% if body = extract_body(env) %>

    ===================================================================
    Request Body:
    ===================================================================

    <%= body.gsub(/^/, '  ') %>
    <% end %>

    ===================================================================
    Rack Environment:
    ===================================================================

      PID:                     <%= $$ %>
      PWD:                     <%= Dir.getwd %>

      <%= env.to_a.
        sort{|a,b| a.first <=> b.first}.
        map{ |k,v| "%-25s%p" % [k+':', v] }.
        join("\n  ") %>

    <% if exception.respond_to?(:backtrace) %>
    ===================================================================
    Backtrace:
    ===================================================================

      <%= exception.backtrace.join("\n  ") %>
    <% end %>
    EMAIL
  end
end