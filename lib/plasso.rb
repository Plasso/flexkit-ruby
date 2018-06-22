require 'net/http'
require 'json'
require 'uri'
require 'date'

def sendGetRequest(url, &block)
  uri = URI(url)
  Net::HTTP.get_response(uri) do |response|
    yield JSON.parse(response.body)
  end
end

def parseCookies(request)
  list = {};
  rc = req.headers.cookie;

  if rc
    rcSplit = rc.split(';')
    rcSplit.each do |cookie|
      parts = cookie.split('=')
      list[parts[0].strip!] = URI.unescape(parts.slice(1).join('='))
    end
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
    self.member
    self.token
    self.space
    self.memberData

    def deserialize(data)
      props = JSON.parse(data)
      self.member = props.member
      self.space = props.space
      self.token = props.token
    end

    def serialize
      return JSON.generate({ :member => self.member, :space => self.space, :token => self.token })
    end

    def loadFromRequest(req)
      cookies = parseCookies(req)
      if !cookies._plasso_flexkit.nil?
        deserialize(URI.unescape(cookies._plasso_flexkit))
      end
    end

    def saveToResponse(res)
      # what is this.serialize
      setCookie(res, this.serialize(), 1, '/')
    end


    def authenticate(options, &block)
      if options.nil? || !options.token
        # is this valid?
        return cb(raise Exception.new('token required'))
      end

      query = self.generateMemberUrlQuery(options.token)
      url = "https://api.plasso.com/?query=#{query}"

      sendGetRequest(url) { |apiResponse|
        if (apiResponse.statusCode !== 200) {
          rawData = ''
          apiResponse.on('data', (chunk) => rawData += chunk);
          apiResponse.on('end', () => { cb(new Error(rawData)); });
          return;
        end
        apiResponse.setEncoding('utf8');
        rawData = '';
        apiResponse.on('data', (chunk) => rawData += chunk);
        apiResponse.on('end', () => {
          begin
            parsedData = JSON.parse(rawData);
            if (parsedData.errors && parsedData.errors.length > 0) {
              return cb(raise Exception.new(JSON.generate(parsedData.errors)));
            end

            self.member = parsedData.data.member;
            self.space = parsedData.data.member.space;
            self.memberData = parsedData.data;

            yield null;
          rescue
            yield raise Exception.new('Failed to get data.');
          end
        });
      end # what to do with this?   }).on('error', cb);
    end

    def isAuthenticated(options, cb)
      if !self.member
        cb(false);
      else
        cb(true);
      end
    end

    def middleware(req, res, next)
      parsedUrl = URI.parse(req.url, true);
      logoutUrl = `//${req.headers.host}`;

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
        redirect(res, self.space ? self.space.logoutUrl : logoutUrl)
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
