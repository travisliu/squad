require 'json'
require 'rack'
require 'nest'
require 'seg'
require 'ohm_util'

class Squad
  DEFAULT_HEADER = {"Content-Type" => 'application/json;charset=UTF-8'}

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

  def self.routes; @routes ||= {} end

  def resources(name, &block)
    self.class.routes[name] = Resource.factor(&block)
  end

  def call(env); dup.call!(env) end

  def call!(env)
    request = Rack::Request.new(env)
    seg = Seg.new(request.path_info)

    inbox = {}
    seg.capture(:segment, inbox)
    segment = inbox[:segment].to_sym
    raise BadRequestError unless klass = self.class.routes[segment]

    resource = klass.new(segment)
    resource.run(seg)
    resource.render(request)
    [resource.status, resource.header, [resource.to_json]]
  rescue Error => e
    [e.status, e.header, [JSON.dump(e.body)]]
  rescue Exception => e
    puts "message: #{e.message}, b: #{e.backtrace}"
    error = Error.new
    [error.status, error.header, [JSON.dump(error.body)]]
  end

  class Error < StandardError
    def status; 500 end
    def header; DEFAULT_HEADER end
    def body; {message: 'error'} end
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
    attr :header
    attr :id

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
      default_actions

      while seg.capture(:segment, inbox)
        segment = inbox[:segment].to_sym
        @request_methods = {}

        if new? && !defined?(@bulk_name)
          if bulk = self.class.bulks[segment]
            @bulk_name = segment
            return instance_eval(&bulk)
          else
            @id = segment
            load!
            default_element_action
            next
          end
        end

        if !defined?(@element_name) && !defined?(@collection_name)
          if element = self.class.elements[segment]
            @element_name = segment
            return instance_eval(&element)
          elsif collection = self.class.collections[segment]
            @collection_name = segment
            return instance_eval(&collection)
          end
        end

        raise BadRequestError
      end
    end

    def render(request)
      raise NotImplementedError unless method_block = @request_methods[request.request_method]
      load! unless id.nil?
      execute(request.params, &method_block)
      instance_exec(request) { |request| process_request request }
    end

    def execute(params, &block)
      @results = yield params
    end

    def element_type?; !defined?(@results) || !@results.kind_of?(Collection) end

    def self.factor(&block)
      klass = dup
      klass.class_eval(&block)
      klass
    end

    def initialize(name, attributes = {})
      @attributes = Hash[self.class.attributes.map{|key| [key, nil]}]
      @resource_name = name
      update_attributes(attributes)
      @status = nil
      @header = DEFAULT_HEADER
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

    def self.indices; @indices ||= [] end
    def self.index(attribute)
      indices << attribute unless indices.include?(attribute)
    end

    def self.collections; @collections ||= {} end
    def self.collection(name)
      collections[name] = Proc.new do
        show do |params|
          resource = Squad.routes[name].new(name)
          resource.query("#{@resource_name}_id", @id)
        end
      end
    end

    def self.reference(name)
      field = :"#{name}_id"
      attribute field
      index field
    end

    def self.process_request(&block)
      define_method(:process_request, block)
    end

    def resource; self.class end

    def find(id)
      resource.new(@resource_name, {"id" => id}).load!
    end

    def all; Collection.new(self, key[:all].call("SMEMBERS")) end

    def query(attribute, value)
      ids = key[:indices][attribute][value].call("SMEMBERS")
      Collection.new(self, ids)
    end

    def load!
      result = key[id].call("HGETALL")
      raise NotFoundError if result.size == 0
      update_attributes(Hash[*result])
      return self
    end

    def update_attributes(atts)
      @attributes.each do |attribute, value|
        send(:"#{attribute}=", atts[attribute.to_s]) if atts.has_key?(attribute.to_s)
      end
      @id = atts["id"] if atts["id"]
    end

    def save
      feature = {name: @resource_name}
      feature["id"] = @id unless new?

      indices = {}
      resource.indices.each do |field|
        next unless (value = send(field))
        indices[field] = Array(value).map(&:to_s)
      end

      @id = OhmUtil.script(redis,
        OhmUtil::LUA_SAVE,
        0,
        feature.to_json,
        serialize_attributes.to_json,
        indices.to_json,
        {}.to_json
      )
    end

    def delete
      OhmUtil.script(redis,
        OhmUtil::LUA_DELETE, 0, {
          "name" => @resource_name,
          "id" => id,
          "key" => key[id].to_s
        }.to_json,
        {}.to_json,
        {}.to_json
      )

      @attributes.each do |key, value|
        attributes[key] = nil
      end
      @id = nil
    end

    def attributes; @attributes end

    def reproduce(attributes)
      self.class.new(@resource_name, OhmUtil.dict(attributes))
    end

    def to_hash
      hash = attributes
      hash[:id] = @id unless @id.nil?

      return hash
    end

    def to_json
      if element_type?
        JSON.dump(self.to_hash)
      else
        @results.to_json
      end
    end

    def key;   @key ||= Nest.new(@resource_name, redis) end
    def redis; Squad.redis end

    private
      attr_writer :id

      def new?; !defined?(@id) end
      def serialize_attributes
        result = []

        attributes.each do |key, value|
          result.push(key, value.to_s) if value
        end

        result
      end

      def show(&block);    @request_methods['GET']    = block end
      def create(&block);  @request_methods['POST']   = block end
      def update(&block);  @request_methods['PUT']    = block end
      def destory(&block); @request_methods['DELETE'] = block end

      def default_actions
        @request_methods = {}

        show do |params|
          if params.size == 0
            all
          else
            query(*params.first)
          end
        end

        create do |params|
          update_attributes(params)
          save
          created
        end
      end

      def default_element_action
        show { |params| }

        update do |params|
          update_attributes(params)
          save
        end

        destory { |params| delete }
      end
  end

  class Collection
    include Enumerable

    def initialize(resource, ids)
      @resource = resource
      @ids      = ids
    end

    def each
      @ids.each { |id| @resource.redis.queue("HGETALL", @resource.key[id])}

      data = @resource.redis.commit
      return if data.nil?

      data.each_with_index do |atts, idx|
        yield @resource.reproduce(atts + ['id', @ids[idx]])
      end
    end

    def to_json
      JSON.dump(self.map { |e| e.to_hash })
    end
  end
end
