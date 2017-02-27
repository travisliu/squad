require 'json'
require 'rack'
require 'nest'
require './lib/ohm_util.rb'

class Kolo
  def initialize(&block)
    instance_eval(&block)
  end

  def self.redis; @redis = settings[:redis] || Redic.new end
  def self.settings; @settings ||= {} end

  def self.application(&block)
    @app = new(&block) 
  end

	def self.call(env)
    @app.call(env)
	end

  def routes; @routes ||= {} end

  def resources(name, &block)
    routes[name] = Resource.factor(&block)
  end

  def call(env)
    request = Rack::Request.new(env)
    seg = Seg.new(request.path_info)
    
    inbox = {}
    resource = nil 
    while seg.capture(:segment, inbox)
      segment = inbox[:segment].to_sym

      if resource.nil? && klass = routes[segment] 
        resource = klass.new(segment)
      elsif resource.run(segment)
      end
    end
    
    return resource.render(request)
  end

  class Resource 

    def run(segment)  
      if !defined?(@element_name) && element = self.class.elements[segment]
        @element_name = segment
        return instance_eval(&element)
      elsif !defined?(@action_name) && action = self.class.actions[segment] 
        @action_name = segment
				
        return instance_eval(&action)
      end
      @id = segment
    end

    def render(request)
      # throw out error if method not found
      return unless method_block = @request_methods[request.request_method]
      
      body = JSON.dump(execute( request.params, &method_block))
      [200, {}, [body]]
    end

    def execute(params)
      if @id.nil?

      else

      end
      yield params
    end

    def self.factor(&block)
      klass = dup
      klass.class_eval(&block)
      klass 
    end

    def initialize(name)
      @resource_name = name
      default_actions
    end

    def self.attribute(name)
      attributes << name unless attributes.include? name
    end
    
    def self.attributes; @attributes ||= [] end
    
    def self.actions; @actions ||= {} end

    def self.action(name, &block)
      actions[name] = block
    end
    
    def self.elements; @elements ||= {} end
    
    def self.element(name, &block)
      elements[name] = block
    end
    
    def [](id)
      { id: 1, email: 'test@gmail.com', password: '!pw1234'}
    end

    private 
      def redis; Kolo.redis end

      def get(&block);    @request_methods['GET']    = block end
      def post(&block);   @request_methods['POST']   = block end
      def put(&block);    @request_methods['PUT']    = block end
      def delete(&block); @request_methods['DELETE'] = block end
      
      def default_actions
        @request_methods = {} 

        get do |params|
          attributes
        end

        post do |params|
        end

        put do |params|
        end
      
        delete do |params|
        end
      end

      def []
        attributes 
      end
  end
end
