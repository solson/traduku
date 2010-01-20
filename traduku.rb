#!/usr/bin/env ruby
# encoding: utf-8

require 'rubygems'
require 'sequel'
require 'on_irc'

# the DB stores accented characters as these arbitrary plain characters
SPECIAL_FROM = 'qQ@#{}[]xXwW'
SPECIAL_TO   = 'ĉĈĝĜĥĤĵĴŝŜŭŬ'

puts 'Connecting to databases...'
EN = Sequel.connect('sqlite://english.sqlite')
puts '  connected to english.sqlite.'
EO = Sequel.connect('sqlite://esperanto.sqlite')
puts '  connected to esperanto.sqlite.'
puts

irc = IRC.new do
  nick 'traduku'
  ident 'eo'
  realname 'Esperanto<->English translator/tradukilo'

  server :eighthbit do
    address 'irc.eighthbit.net'
  end
end

irc[:eighthbit].on '001' do
  join '#offtopic,#bots'
end

irc.on :privmsg do
  if params[1] =~ /^traduku[:,]?\s+(.*)$/
    word = $1
    
    if word[0,1] == '!'
      command = word[1..-1]

      case command
      when 'help'
        respond(sender.nick + ': Tell me a word and I will translate it from English to Esperanto or Esperanto to English.')
      when 'helpo'
        respond(sender.nick + ': Diru al mi vorton kaj mi tradukos ĝi de la angla al Esperanto aŭ Esperanto al la angla.')
      end

      next
    end

    # get en->eo translations
    esp_keys = EN[:dictionary].filter('word = ? COLLATE NOCASE', word).map(:esp_key)
    esp_words = EO[:dictionary].filter(:id => esp_keys).map(:word)
    esp_words.map!{|w| w.tr(SPECIAL_FROM, SPECIAL_TO).gsub(/\d/, '') }.uniq!

    # get eo->en translations
    esp_keys = EO[:dictionary].filter('word = ? COLLATE NOCASE', word.tr(SPECIAL_TO, SPECIAL_FROM)).map(:id)
    eng_words = EN[:dictionary].filter(:esp_key => esp_keys).map(:word)

    # choose what to show
    if !esp_words.empty? and !eng_words.empty?
      response = sender.nick + ': [en->eo] ' + esp_words.join(', ') + ' | ' + '[eo->en] ' + eng_words.join(', ')
    elsif !esp_words.empty?
      response = sender.nick + ': ' + esp_words.join(', ')
    elsif !eng_words.empty?
      response = sender.nick + ': ' + eng_words.join(', ')
    else
      response = sender.nick + ': No results. | Ne resultoj.'
    end

    response << ' | For help, use !help' if word == 'help'
    response << ' | Por helpo, uzu !helpo' if word == 'helpo'

    respond(response)
  end
end

irc.on :all do
  pre = "(#{sender}) " unless sender.empty?
  puts "#{server.name}: #{pre}#{command} #{params.inspect}"
end

irc.on :ping do
  pong params[0]
end

irc.connect

