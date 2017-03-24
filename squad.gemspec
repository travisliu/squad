Gem::Specification.new do |s|
  s.name = "squad"
  s.version = "0.1"
  s.summary = %{Simple, efficient RESTful framework in Ruby with Redis}
  s.description = %Q{Squad uses Redis to store resources inspired by Ohm, and provides a simple DSL to easily develop APIs.}
  s.authors = ["Travis Liu"]
  s.email = ["travisliu.tw@gmail.com"]
  s.homepage = "https://github.com/travisliu/squad"
  s.license = "MIT"

  s.files = `git ls-files`.split("\n")

  s.rubyforge_project = "squad"
  
  s.add_dependency "rack", "~> 2.0"
  s.add_dependency "redic", "~> 1.5"
  s.add_dependency "nest", "~> 3"
  s.add_dependency "stal"

  s.add_development_dependency "cutest"
  s.add_development_dependency "rack-test"
end
