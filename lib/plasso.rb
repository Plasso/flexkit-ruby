require 'net/http'
require 'json'
require 'uri'
require 'date'

def send_get_request(url, &block)
  uri = URI(url)
  Net::HTTP.get_response(uri) do |response|
    block.call(JSON.parse(response.body))
  end
end

def setCookie(res, value, days, path) {
  expdate = DateTime.new(DateTime.now.year, DateTime.now.mon, (DateTime.now.mday + days))
  if (res.cookie) {
    # Convert from JS to Ruby
    res.cookie('_plasso_flexkit', value, { path, expires: expdate })
  elsif
    # Convert from JS to Ruby
    cookies = res.getHeader('Set-Cookie')
    if !cookies
      cookies = []
    end
    cookies.push("_plasso_flexkit=#{value};expires=#{expdate.toUTCString()};path=#{path}")
    # Convert from JS to Ruby
    res.setHeader('Set-Cookie', cookies)
  end
end

def clearCookie(res, path)
  setCookie(res, '{}', -2, path);
end

def redirect(res, location) {
  # Convert from JS to Ruby
  res.writeHead(302, { 'Location': location })
  res.end();
end


GRAPHQL_GET_DATA = <<~HEREDOC
  {
    member(token: "${token}") {
      name,
      email,
      billingInfo {
        street,
        city,
        state,
        zip,
        country
      },
      connectedAccounts {
        id,
        name
      },
      dataFields {
        id,
        value
      },
      defaultSourceId,
      id,
      metadata,
      payments {
        id,
        amount,
        createdAt,
        createdAtReadable
      },
      postNotifications,
      shippingInfo {
        name,
        address,
        city,
        state,
        zip,
        country
      },
      sources {
        createdAt,
        id,
        brand,
        last4,
        type
      },
      space {
        id,
        name,
        logoutUrl
      },
      status,
      subscriptions {
        id,
        status,
        createdAt,
        createdAtReadable,
        plan {
          id,
          name
        }
      }
    }
  }
HEREDOC

module Plasso

  class Flexkit

    def initialize()
      @member = nil
      @token = nil
      @space = nil
      @memberData = nil
    end

    def deserialize(data)
      props = JSON.parse(data)
      @member = props.member
      @space = props.space
      @token = props.token
    end

    def serialize
      return JSON.generate({ :member => @member, :space => @space, :token => @token })
    end

    def loadFromRequest(req)
      cookies = req.to_hash['set-cookie'].collect{|ea|ea[/^.*?;/]}.join
      if !cookies['_plasso_flexkit'].nil?
        deserialize(URI.unescape(cookies['_plasso_flexkit']))
      end
    end

    def saveToResponse(res)
      setCookie(res, self.serialize(), 1, '/')
    end


    def authenticate(options)
      if options.nil? || !options.token
        raise 'token required'
      end

      query = self.generateMemberUrlQuery(options.token)
      url = "https://api.plasso.com/?query=#{query}"

      send_get_request(url) { |apiResponse|
        if (apiResponse.code !== 200) {
          raise apiResponse.body
        end

        begin
          parsedData = JSON.parse(apiResponse.body)
          if (parsedData['errors'] && parsedData['errors'].length > 0) {
            raise JSON.generate(parsedData['errors'])
          end

          @member = parsedData['data']['member'];
          @space = parsedData['data']['member']['space'];
          @memberData = parsedData['data'];
        rescue
          raise 'Failed to get data.'
        end

      end
    end

    def isAuthenticated(options, cb)
      return !!@member
    end

    def middleware(req, res, next)
      parsedUrl = URI.parse(req.url, true);
      logoutUrl = "//#{req.headers.host}";

      loadFromRequest(req);

      if parsedUrl.query._plasso_token
        plasso.token = parsedUrl.query._plasso_token;
      end

      if !parsedUrl.query._logout.nil? || parsedUrl.query._plasso_token === 'logout'
        clearCookie(res, '/');
        redirect(res, plasso.space ? plasso.space.logoutUrl : logoutUrl)
        return;
      end

      if plasso.token.nil?
        clearCookie(res, '/')
        redirect(res, @space ? @space.logoutUrl : logoutUrl)
        return;
      end

      authenticate({ :token => plasso.token }) { |returnValue|
        if !returnValue
          clearCookie(res, '/')
          redirect(res, plasso.space ? plasso.space.logoutUrl : logoutUrl)
          return;
        end
        setCookie(res, JSON.stringify(plasso), 1, '/')
        # next();
      end
    end
  end

end
