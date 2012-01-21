#!/usr/bin/env ruby

require 'rubygems'
require 'json'
require 'open-uri'

class TwitTwat
  # Establish defaults
  DEF_TWIT_USER = "charliesheen"
  DEF_COUNT = 5
  BASE_IN = "http://twitter.com/statuses/user_timeline/"
  BASE_URL = "http://twitter.com/"

  def initialize (username)
    @twituser = username || DEF_TWIT_USER
    @url = BASE_IN + @twituser + ".json"
  end

  def getJson (count)
    buffer = open(@url + "?count=" + count.to_s, "UserAgent" => "Ruby-Wget").read
    result = JSON.parse(buffer)
  end
end
