class Kolo

  def initialize(block)
    instance_eval(&block)
  end

  def self.application(&block)
    new(block) 
  end

  def models; @models ||= {} end

  def resources(name, &block)
    models[name] = Model.new(block)
  end

  def call(env)
  end

  class Model 

    def initialize(block)
      instance_eval(&block)
    end

    def attribute(name)
      attributes << name unless attributes.include? name
    end
    
    def attributes; @attributes ||= [] end
    
    def elements; @elements ||= {} end
    
    def element(name, &block)
      elements[name] = block
    end

    def show(&block)
      # yield({})
    end
    
    def call(params = {})
    end
  end
end
