# Squad 

Simple, efficient RESTful framework in Ruby with Redis.

Squad uses Redis to store resources inspired by [Ohm](https://github.com/soveran/ohm), and provides a simple DSL to easily develop APIs.

## Getting started 
### Installation
``` conosle
gem install Squad
```

### Usage

Squad assumes Redis was started with address `localhost` and port `6379`. If you need to connect to a remote server or different port, try: 
``` ruby 
Squad.settings[:redis] = Redic.new 'redis://10.1.0.1:6379'
```

Hear's an example that has two resources users and products. 
``` ruby
# cat hello_squad.rb
require "squad"

Squad.application do 
  resources :users do
    attribute :name
    attribute :email
   
    collection :posts
  end

  resources :posts do
    attribute :title
    attribute :content

    reference :users
  end
end
```
All resources have the id attribute built in, you don't need to declare it. 

To run it, you can create a `config.ru` file
``` ruby
# cat config.ru
require 'hello_squad.rb'

run Squad 
```
Then run `rackup`. 

Now, you already get basic CURD and relation functionality as RESTful API.
``` 
GET /users
POST /users
GET /users/:id
PUT /users/:id
DELETE /users/:id
GET /users/:id/posts
```

### Custom action
You can operate the single element in custom action.
``` ruby
require "squad"

Squad.application do
  resources :users do
    attribute :name
    attribute :email

    element :showcase do
      # GET /users/:id/showcase
      show do |params|
        self.email[1..3] = 'xxx' 
      end

      # PUT /users/:id/showcase
      update do |params|
        self.email = params["email"]
        save
      end

      # DELETE /users/:id/showcase
      destory do |params|
        delete if self.email == params["email"]
      end
    end

    bulk :signup do
      # POST /users/signup
      create do |params|
        if params["email"].include?("@gmail.com")
          update_attributes(params)
          save
          created
        else
          bad_request 
        end
      end
    end
  end
end
```

### Index
Index helps you quick lookup elements.

``` ruby
require "squad"

Squad.application do
  resources :users do
    attribute :name
    attribute :email

    # GET /users/?name=travis
    index :name
  end
end
```

You can have a customize query as well. 
``` ruby
require "squad"

Squad.application do
  resources :users do
    attribute :name
    attribute :email

    index :name

    bulk :gmail do
      # There is `all` method can be used here to get all user elements.
      # GET /users/gmail
      show do |params|
        query("name", params["name"]).select |e|
          e.email.include?("@gmail.com") 
        end
      end
    end
  end
end
```
### Processing request
If you need to do something with your request you can (for example, using the request body)

``` ruby
require "squad"

Squad.application do
  resources :users do
    attribute :extra_data

    process_request do |request|
        send(:extra_data=, request.body.read)
    end
  end
end
```
