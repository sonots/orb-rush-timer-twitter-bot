#!/usr/bin/env ruby
# -*- coding: utf-8 -*-
require 'twitter'
require 'optparse'
require 'yaml'

$options = {}
OptionParser.new do |opt|
  opt.on("-c", "--config=CONFIG", "config file") do |v|
    $options[:config] = v
  end
  opt.parse!(ARGV)
end

def update(tweet)
  begin
    tweet = (tweet.length > 140) ? tweet[0..139].to_s : tweet
    Twitter.update(tweet.chomp)
  rescue => e
    $stderr.puts "<<twitter.rake::tweet.update ERROR : #{e.message}>>"
  end
end

def config
  @config ||= YAML.load_file($options[:config] || (File.dirname(__FILE__) + '/config.yml'))
end

def main
  Twitter.configure do |conf|
    conf.consumer_key       = config['consumer_key']
    conf.consumer_secret    = config['consumer_secret']
    conf.oauth_token        = config['oauth_token']
    conf.oauth_token_secret = config['oauth_token_secret']
  end

  tweet = STDIN.read.encode(Encoding::UTF_8, Encoding::UTF_8)
  update(tweet) if tweet.size > 0
end

main
