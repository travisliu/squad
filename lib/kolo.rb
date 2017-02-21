require 'json'
require 'nest'
require './lib/ohm_util.rb'

class Kolo
  def initialize(&block)
    instance_eval(&block)
  end

  def self.application(&block)
    new(&block) 
  end

  def routes; @routes ||= {} end

  def resources(name, &block)
    routes[name] = Resource.new(&block)
  end

  def call(env)
    path = '/users/1/nickname'
    request_method = 'GET'
    seg = Seg.new(path)

    inbox = {}
    resource = nil 
    while seg.capture(:segment, inbox)
      segment = inbox[:segment].to_sym
      if resource.nil? && resource = routes[segment] 
      elsif resource.run(segment)
      end
    end
    
    return resource.render(request_method)
  end

  class Resource 

    def run(segment)  
      if !defined?(@element_name) && element = elements[segment]
        @element_name = segment
        return instance_eval(&element)
      elsif !defined?(@action_name) && action = actions[segment] 
        @action_name = segment
        puts "action_name: #{@action_name}"
        return instance_eval(&action)
      end
      @id = segment
    end

    def render(method)
      # throw out error if method not found
      return unless method_block = @request_methods[method]
      
      data = execute('abc', &method_block)
      puts "result #{JSON.dump(data)}"
    end

    def execute(params)
      if @id.nil?

      else

      end
      yield params
    end

    def initialize(&block)
      instance_eval(&block)
      default_actions
    end

    def attribute(name)
      attributes << name unless attributes.include? name
    end
    
    def attributes; @attributes ||= [] end
    
    def actions; @actions ||= {} end

    def action(name, &block)
      actions[name] = block
    end
    
    def elements; @elements ||= {} end
    
    def element(name, &block)
      elements[name] = block
    end
    
    def [](id)
      { id: 1, email: 'test@gmail.com', password: '!pw1234'}
    end

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
