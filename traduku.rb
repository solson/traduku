#!/usr/bin/env ruby
# encoding: utf-8

require 'rubygems'
require 'net/http'
require 'cgi'
require 'nokogiri'
require 'google_translate'
require 'htmlentities'
require 'cinch'

LERNU_LANGS = %w[ar bg ca cs da de el en es eo fa fi fr ga he hi hr hsb hu it ja ko lt nl no pl pt ro ru sk sl sr sv sw th tr uk vi zh]

gt = Google::Translator.new
glangs = gt.supported_languages
GOOGLE_FROM_LANGS = glangs[:from_languages].map(&:code)
GOOGLE_TO_LANGS = glangs[:to_languages].map(&:code)

# This method is an abomination. It was translated from a Python plasmoid interface to lernu.net.
def lernu_translate(fromlang, tolang, args)
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

  words
end

bot = Cinch::Bot.new do
  configure do |c|
    c.server   = "localhost"
    c.nick     = "traduku"
    c.realname = "Universal translator. Uses lernu.net for Esperanto."
    c.channels = ["#bots", "#programming", "#offtopic"]
  end

  on :message, /^#{Regexp.escape nick}[:,]?\s+(.+)$/ do |m, word|
    command, args = word.split(' ', 2)

    case command
    when 'help'
        m.user.notice('Syntax: "<fromlang>-<tolang> <word>". If you use Esperanto (eo) for either of the languages, lernu.net single-word translation will be used. Otherwise, Google Translate is used.')
        m.user.notice('Lernu.net languages: ' + LERNU_LANGS.join(', '))
        m.user.notice('Google \'from\' languages: ' + GOOGLE_FROM_LANGS.join(', '))
        m.user.notice('Google \'to\' languages: ' + GOOGLE_TO_LANGS.join(', '))
    when 'helpo'
        m.user.notice('Sintakso: "<delingvo>-<allingvo> <vorto>". Ĉu vi uzas Esperanton (eo) por ĉu de la lingvoj, lernu.net unuopa-vorton tradukanton uzos. Kontraŭe, Google Tradukanton uzas.')
        m.user.notice('Lernu.net lingvoj: ' + LERNU_LANGS.join(', '))
        m.user.notice('Google allingvoj: ' + GOOGLE_FROM_LANGS.join(', '))
        m.user.notice('Google delingvoj: ' + GOOGLE_TO_LANGS.join(', '))
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
      # If at least one of the languages is Esperanto (eo), use lernu.net.
      # Otherwise, use google translate.
      if LERNU_LANGS.include?(fromlang) && LERNU_LANGS.include?(tolang) && (fromlang == 'eo' || tolang == 'eo')
        words = lernu_translate(fromlang, tolang, args)

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
      elsif GOOGLE_FROM_LANGS.include?(fromlang) && GOOGLE_TO_LANGS.include?(tolang)
        m.reply(HTMLEntities.decode_entities(gt.translate(fromlang, tolang, args)), true)
      elsif %w[det detect].include?(fromlang) && GOOGLE_TO_LANGS.include?(tolang)
        detected_fromlang = gt.detect_language(args)['language']
        m.reply("(Detected as #{detected_fromlang}) " + HTMLEntities.decode_entities(gt.translate(detected_fromlang, tolang, args)))
      else
        m.reply('Invalid language pair. Try "help". | Malvalidaj lingvoj duoj. Provu "helpo".', true)
      end
    end
  end
end

bot.start
