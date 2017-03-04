require 'json'
require 'rack'
require 'nest'
require 'ohm_util'

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
    seg.capture(:segment, inbox)  
    segment = inbox[:segment].to_sym
    raise BadRequestError unless klass = routes[segment]

    resource = klass.new(segment)
    resource.run(seg)
    execute(request.params, &resource.request_method(request))
    [resource.status, {}, [resource.to_json]]
  rescue Error => e
    [e.status, e.header, [e.message]]
  rescue Exception => e
    error = Error.new
    [error.status, error.header, error.message]
  end

  def execute(params, &block)
    yield params
  end

  class Error < StandardError
    def status; 500 end
    def header;  {} end
    def message; [] end
  end
  class NotImplementedError < Error
    def status; 501 end
  end
  class BadRequestError < Error
    def status; 400 end
  end
  class NotFoundError < Error
    def status; 404 end
  end

  class Resource 
    def id;     @id end
    def status; @status || ok end

    # status code sytax suger
    def ok;                    @status = 200 end
    def created;               @status = 201 end
    def no_cotent;             @status = 204 end
    def bad_request;           @status = 400 end
    def not_found;             @status = 404 end
    def internal_server_error; @status = 500 end
    def not_implemented;       @status = 501 end
    def bad_gateway;           @status = 502 end

    def run(seg)  
      inbox = {}
      while seg.capture(:segment, inbox)
        segment = inbox[:segment].to_sym

        if !defined?(@element_name) && element = self.class.elements[segment]
          @element_name = segment
          return instance_eval(&element)
        elsif !defined?(@bulk_name) && bulk = self.class.bulks[segment] 
          @bulk_name = segment
          
          return instance_eval(&bulk)
        end
        @id = segment
      end
    end

    def request_method(request)
      raise NotImplementedError unless method_block = @request_methods[request.request_method]
      load! unless id.nil?
      method_block
    end

    def self.factor(&block)
      klass = dup
      klass.class_eval(&block)
      klass 
    end

    def initialize(name)
      @resource_name = name
      @attributes = Hash[self.class.attributes.map{|key| [key, nil]}]
      @status = nil 
      default_actions
    end

    def self.attribute(name)
      attributes << name unless attributes.include? name
      define_method(name) do 
        @attributes[name]
      end
      define_method(:"#{name}=") do |value|
        @attributes[name] = value
      end
    end
    
    def self.attributes; @attributes ||= [] end
    
    def self.bulks; @bulks ||= {} end

    def self.bulk(name, &block)
      bulks[name] = block
    end
    
    def self.elements; @elements ||= {} end
    
    def self.element(name, &block)
      elements[name] = block
    end
    
    def load!
      result = key[id].call("HGETALL") 
      raise NotFoundError if result.size == 0
      update_attributes(Hash[*result])
    end

    def update_attributes(atts)
      @attributes.each do |key, value|
        attributes[key] = atts[key.to_s] if atts.has_key?(key.to_s)
      end
    end

    def save
      feature = {name: @resource_name}
      feature["id"] = @id if defined?(@id)
      @id = OhmUtil.script( redis,
                            OhmUtil::LUA_SAVE,
                            0,
                            feature.to_json,
                            serialize_attributes.to_json,
                            {}.to_json,
                            {}.to_json)
    end  

    def attributes; @attributes end

    def to_json
      JSON.dump(attributes.merge({id: id}))
    end

    private 
      def redis; Kolo.redis end
      def key;   @key ||= Nest.new(@resource_name, redis) end

      def serialize_attributes
        result = []
        
        attributes.each do |key, value| 
          result.push(key, value.to_s) if value
        end

        result
      end

      def show(&block);   @request_methods['GET']    = block end
      def create(&block); @request_methods['POST']   = block end
      def update(&block); @request_methods['PUT']    = block end
      def delete(&block); @request_methods['DELETE'] = block end
      
      def default_actions
        @request_methods = {} 

        show do |params|
        end

        create do |params|
          update_attributes(params)
          save
          created
        end
      end

      def []
        attributes 
      end
  end
end
