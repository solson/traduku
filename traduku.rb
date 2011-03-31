#!/usr/bin/env ruby
# encoding: utf-8

require 'rubygems'
require 'net/http'
require 'cgi'
require 'nokogiri'
require 'cinch'

LERNU_LANGS = %w[ar bg ca cs da de el en es eo fa fi fr ga he hi hr hsb hu it ja ko lt nl no pl pt ro ru sk sl sr sv sw th tr uk vi zh]

bot = Cinch::Bot.new do
  configure do |c|
    c.server   = "localhost"
    c.nick     = "traduku"
    c.realname = "Esperanto<->English translator/tradukilo"
    c.channels = ["#bots", "#programming", "#offtopic"]
  end

  on :message, /^#{Regexp.escape nick}[:,]?\s+(.+)$/ do |m, word|
    command, args = word.split(' ', 2)

    case command
    when 'help'
        m.reply(m.user.nick + ': Syntax: "<fromlang>-<tolang> <word>". At least one of the languages must be Esperanto (eo).')
        m.reply(m.user.nick + ': Languages: ' + LERNU_LANGS.join(', '))
    when 'helpo'
        m.reply(m.user.nick + ': Sintakso: "<delingvo>-<allingvo> <vorto>". Almenaŭ unu de la lingvoj devas Esperanto (eo).')
        m.reply(m.user.nick + ': Lingvoj: ' + LERNU_LANGS.join(', '))
    when 'en-sentence'
      doc = Nokogiri::HTML(Net::HTTP.post_form(URI.parse('http://traduku.net/cgi-bin/traduku'), {'en_eo_apertium' => 'EN → EO', 't' => args}).body)
      res = doc.at_css('#rezulto')
      m.reply(m.user.nick + ': ' + res.inner_text.strip.gsub(/\s+/, ' ')) if res
    when 'eo-sentence'
      doc = Nokogiri::HTML(Net::HTTP.post_form(URI.parse('http://traduku.net/cgi-bin/traduku'), {'eo_en_apertium' => 'EO → EN', 't' => args}).body)
      res = doc.at_css('#rezulto')
      m.reply(m.user.nick + ': ' + res.inner_text.strip.gsub(/\s+/, ' ')) if res
    else
      fromlang, tolang = command.split('-')
      # At least one of the languages must be Esperanto (eo).
      unless LERNU_LANGS.include?(fromlang) && LERNU_LANGS.include?(tolang) && (fromlang == 'eo' || tolang == 'eo')
        m.reply(m.user.nick + ': Invalid syntax. Try "help". | Malvalida sintakso. Provu "helpo".')
        next
      end

      params = {'delingvo' => fromlang, 'allingvo' => tolang, 'modelo' => args}
      domain = 'lernu.net'
      path = "/cgi-bin/serchi.pl?" + params.map{|k,v| k + '=' + CGI.escape(v) }.join('&')

      result = Net::HTTP.get(domain, path).force_encoding('utf-8').split("\n")

      type = false
      text = ""
      i = 0
      words = []
      currentword = []
      while i < result.length
        s = result[i]
        break if s.start_with?("[[")
        word = s.split("\t")
        if !type
          if word.length > 1 && word[1] != ""
            currentword << word[1]
            newline = ""
            if word.length > 2 && word[2] != ""
              newline += " (" + word[2].gsub("/", "·")
              if word.length > 3 && word[3] != ""
                newline += " <- " + word[3]
              end
              newline += ")"
            end
            text += newline + "\n"
          end
          i += 1
        else
          if word.length > 3
            text += "  " + word[3] + "\n"
          end
          i += 2
          if(currentword.length > 0)
            currentword << text
            words << currentword
            currentword = []
          end
          text = ""
        end
        type = !type
      end

      case words.length
      when 0
        m.reply("No results! | Neniuj resultoj!")
      when 1
        m.reply(words[0].join)
      else
        if w = words.find{|w| w[0] == args }
          m.reply(w.join)
          words.each{|w| puts w.join }
        else
          m.reply(words.map(&:first).join(', '))
        end
      end
    end
  end
end

bot.start
