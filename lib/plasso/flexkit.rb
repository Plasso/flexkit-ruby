require 'net/http'
require 'json'
require 'uri'

def send_request(method, path, data)
  host = 'https://plasso.com'
  
  uri = URI("#{host}#{path}")
  http = Net::HTTP.new(uri.host, uri.port)
  request = nil
  if method == 'POST'
    request = Net::HTTP::Post.new(uri.request_uri)
  elsif method == 'DELETE'
    request = Net::HTTP::Delete.new(uri.request_uri)
  end

  request.body = JSON.generate(data)
  request['Content-Type'] = 'application/json'

  http.request(request) do |response|
    return JSON.parse(response.body)
  end

end

GRAPHQL_GET_DATA = <<~HEREDOC
  query getMember($token: String) {
    member(token: $token) {
      id,
      name,
      email,
      ccType,
      ccLast4,
      shippingInfo {
        name
        address
        city
        state
        zip
        country
      },
      dataFields {
        id,
        value
      },
      plan {
        alias
      }
    }
  }
HEREDOC

module Plasso
  module Flexkit
    class Member
      def initialize(public_key, token)
        @public_key = public_key
        @token = token
      end

      def update_settings(request)
        request['token'] = @token
        request['public_key'] = @public_key
        send_request("POST", "/api/services/user?action=settings", request)
      end

      def update_credit_card(request)
        request['token'] = @token
        request['public_key'] = @public_key
        send_request("POST", "/api/services/user?action=cc", request)
      end

      def delete
        send_request("DELETE", "/api/service/user?action=cancel", {"public_key" => @public_key, "token" => @token})
      end

      def get_data
        request = {
          "query" => GRAPHQL_GET_DATA,
          "variables" => {
            "token" => @token
          }
        }

        response = send_request("POST", "/graphql", request)

        if response['errors']
          raise response['errors'][0]['message']
        end

        member_data = {
          "credit_card_last4" => response['data']['member']['ccLast4'],
          "credit_card_type" => response['data']['member']['ccType'],
          "email" => response['data']['member']['email'],
          "id" => response['data']['member']['id'],
          "name" => response['data']['member']['name'],
          "plan" => response['data']['member']['plan']['alias']
        }

        if (response['data']['member']['shippingInfo'])
          member_data['shipping_name'] = response['data']['member']['shippingInfo']['name']
          member_data['shipping_address'] = response['data']['member']['shippingInfo']['address']
          member_data['shipping_city'] = response['data']['member']['shippingInfo']['city']
          member_data['shipping_state'] = response['data']['member']['shippingInfo']['state']
          member_data['shipping_zip'] = response['data']['member']['shippingInfo']['zip']
          member_data['shipping_country'] = response['data']['member']['shippingInfo']['country']
        end

        if (response['data']['member']['dataFields'])
          member_data['data_fields'] = response['data']['member']['dataFields']
        end

        return member_data
      end

      def log_out()
        send_request("POST", "/api/service/logout", {"public_key" => @public_key, "token" => @token});
      end
    end

    def self.create_payment(request)
      send_request("POST", "/api/payments", request)
    end

    def self.log_in(request)
      response = send_request("POST", "/api/service/login", request)

      return Member.new(request['public_key'], response['token'])
    end

    def self.create_subscription(request)
      request['subscription_for'] = 'space'

      response = send_request("POST", "/api/subscriptions", request)

      return Member.new(request['public_key'], response['token'])
    end

    private_constant :Member
  end
end