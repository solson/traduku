#!/usr/bin/env ruby
# encoding: utf-8
require 'net/http'
require 'cgi'
require 'nokogiri'
require 'bing_translator'
require 'cinch'

# Max length for chained translation (lang1 -> lang2 -> ... -> langN)
MAX_CHAIN_LENGTH = 5

TRADUKU_URL = URI.parse('http://traduku.net/cgi-bin/traduku')

# Languages supported by lernu.net's translation service. All only supported
# to or from Esperanto.
LERNU_LANGS = %w[ar bg ca cs da de el en es eo fa fi fr ga he hi hr hsb hu it
                 ja ko lt nl no pl pt ro ru sk sl sr sv sw th tr uk vi zh]

bt = BingTranslator.new(File.read("bing_api_key").chomp)
BING_LANGS = bt.supported_language_codes

# This method is an abomination. It was translated from a Python plasmoid
# interface to lernu.net.
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
            newline += " ← " + word[3]
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
    c.server   = "irc.tenthbit.net"
    c.nick     = "traduku"
    c.realname = "Universal translator. Uses lernu.net for Esperanto."
#    c.channels = ["#bots", "#programming", "#offtopic"]
    c.channels = ["#bots"]
  end

  on :message, /^#{Regexp.escape(nick)}\S*[:,]?\s+(.+)$/ do |m, word|
    command, args = word.split(' ', 2)

    case command
    when 'help'
        m.user.notice('Syntax: "<lang-lang-...> <words>". If you use ' +
                      'Esperanto (eo) for either of the languages, ' +
                      'lernu.net single-word translation will be used. ' +
                      'Otherwise, Bing Translator is used.')

        m.user.notice('Lernu.net languages: ' + LERNU_LANGS.join(', '))
        m.user.notice('Bing languages: ' + BING_LANGS.join(', '))
    when 'en-sentence'
      doc = Nokogiri::HTML(Net::HTTP.post_form(TRADUKU_URL, {'en_eo_apertium' => 'EN → EO', 't' => args}).body)
      res = doc.at_css('#rezulto')
      m.reply(res.inner_text.strip.gsub(/\s+/, ' '), true) if res
    when 'eo-sentence'
      doc = Nokogiri::HTML(Net::HTTP.post_form(TRADUKU_URL, {'eo_en_apertium' => 'EO → EN', 't' => args}).body)
      res = doc.at_css('#rezulto')
      m.reply(res.inner_text.strip.gsub(/\s+/, ' '), true) if res
    else
      langs = command.split('-')

      if langs.count > MAX_CHAIN_LENGTH
        m.reply("You may use only #{MAX_CHAIN_LENGTH} languages in a chain.", true)
        next
      end

      # If at least one of the languages is Esperanto (eo), use lernu.net.
      # Otherwise, use Bing Translator.
      if langs.count == 2 && LERNU_LANGS.include?(langs[0]) && LERNU_LANGS.include?(langs[1]) && (langs[0] == 'eo' || langs[1] == 'eo')
        words = lernu_translate(langs[0], langs[1], args)

        case words.length
        when 0
          m.reply("No results!")
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
      elsif langs.count > 1 && langs.all?{|lang| BING_LANGS.include?(lang) }
        text = args
        langs.each_cons(2) do |fromlang, tolang|
          text = bt.translate(text, :from => fromlang, :to => tolang)
        end
        m.reply(text, true)
      elsif langs.count == 2 && %w[det detect].include?(langs[0]) && BING_LANGS.include?(langs[1])
        detected_fromlang = bt.detect(args)
        m.reply("(Detected as #{detected_fromlang}) " + bt.translate(args, :from => detected_fromlang, :to => langs[1]))
      else
        m.reply('Invalid syntax. Try "help".', true)
      end
    end
  end
end

bot.start
