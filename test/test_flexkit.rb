require 'minitest/autorun'
require 'plasso'

#$public_key = "test_4ice0GuGfPahghb6F5gNw6NyxMO1uYtUrevpOeze1opxrNeLnfPtwDyVkjXHlg7b"
$public_key = "test_def456"

def get_stripe_source(key)
  request = {
    "card[number]"    => "4242 4242 4242 4242",
    "card[exp_year]"  => "2020",
    "card[exp_month]" => "01",
    "card[cvc]"       => "123",
    "card[name]"      => "Michael",
    "key"             => key
  }

  response = Net::HTTP.post_form(URI('https://api.stripe.com/v1/tokens'), request)

  return JSON.parse(response.body)
end

class FlexkitTest < Minitest::Test
  def test_flexkit
    puts 'logged in'
    #source = get_stripe_source("pk_test_5ywZJtYWbWgndgPD8ckUkiMg")
    source = get_stripe_source("pk_test_3OR0B1DynFb4y21HylWOUnHD")
    subscription_request = {
      'public_key' => $public_key,
      'name' => 'Michael',
      'password' => 'password',
      'email' => 'mike+scratch@plasso.com',
      'plan' => 'gold_plan',
      'token' => source['id']
    }
    member = Plasso::Flexkit.create_subscription(subscription_request)
    puts 'create subscription'

    puts member.get_data
    puts 'get data'

    member.log_out
    puts 'log out'

    begin
      member.get_data
    rescue RuntimeError
      puts 'get data failed on purpose'
    end

    member = Plasso::Flexkit.log_in({
      'public_key' => $public_key,
      'password' => 'password',
      'email' => 'mike+scratch@plasso.com'
    })
    
    member.delete
  end
end