require "cutest"
require_relative "../lib/kolo"

def mock_request(app, url, method, payload = nil)
  env = Rack::MockRequest.env_for( url,
    "REQUEST_METHOD" => method,
    :input => payload
  )
  
  app.call(env)
end

prepare do 
  Kolo.settings[:redis] = Redic.new 'redis://database:6379/2'
end

setup do
  Kolo.settings[:redis].call "FLUSHDB"
end

test "basic create, read, update and destory functionality" do |params|
  app = Kolo.application do 
    resources :users do
      attribute :name
      attribute :email
    end
  end
  
  _, _, response = mock_request(app, "/users", "POST", "name=kolo&email=kolo@gmail.com")
  user = JSON.parse(response.first)

  _, _, response = mock_request(app, "/users/#{user["id"]}", "GET")
  result = JSON.parse(response.first) 
  assert result["name"] == "kolo"
  
  mock_request(app, "/users/#{user["id"]}?name=kolo2&email=kolo@gmail.com", "PUT")
  _, _, response = mock_request(app, "/users/#{user["id"]}", "GET")
  result = JSON.parse(response.first) 
  assert result["name"] == "kolo2"
  
  mock_request(app, "/users/#{user["id"]}", "DELETE")
  status_code, _, response = mock_request(app, "/users/#{user["id"]}", "GET")
  assert status_code == 404
end

test "can be queried with index" do |params|
  app = Kolo.application do 
    resources :users do
      attribute :name
      attribute :email

      index :name
    end
  end
 
  mock_request(app, "/users", "POST", "name=kolo&email=kolo@gmail.com")
  mock_request(app, "/users", "POST", "name=kolo&email=kolo2@gmail.com")
  mock_request(app, "/users", "POST", "name=scott&email=scott@gmail.com")
  
  _, _, response = mock_request(app, "/users?name=kolo", "GET")
  users = JSON.parse(response.first)

  assert users.size == 2
end

test "find collection" do
  app = Kolo.application do 
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
 
  _, _, response = mock_request(app, "/users", "POST", "name=kolo&email=kolo@gmail.com")
  users = JSON.parse(response.first)

  mock_request(app, "/posts", "POST", "users_id=#{users["id"]}&title=title1&content=content1")
  mock_request(app, "/posts", "POST", "users_id=#{users["id"]}&title=title2&content=content2")
  _, _, response = mock_request(app, "/users/#{users["id"]}/posts", "GET")

  posts = JSON.parse(response.first)
  assert posts.size == 2
end

test "custom action" do
  app = Kolo.application do
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

  _, _, response = mock_request(app, "/users", "POST", "name=kolo&email=kolo@gmail.com")
  user = JSON.parse(response.first)

  _, _, response = mock_request(app, "/users/#{user["id"]}/showcase", "GET")
  showcase_user = JSON.parse(response.first)
  assert showcase_user["email"] = "kxxx@gmail.com"

  mock_request(app, "/users/#{user["id"]}/showcase?email=newkolo@gmail.com", "PUT")
  _, _, response = mock_request(app, "/users/#{user["id"]}", "GET")
  showcase_user = JSON.parse(response.first)
  assert showcase_user["email"] = "newkolo@gmail.com"
  
  _, _, response = mock_request(app, "/users/#{user["id"]}/showcase?email=newkolo@gmail.com", "DELETE")
  code, _, response = mock_request(app, "/users/#{user["id"]}", "GET")
  assert code == 404 
end
