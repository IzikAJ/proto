# Usage:
# ruby proto.rb [remote path] [local path] [max pages count] [is mobile version?]
# Sample
# ruby proto.rb ***.org ../some_else/ 2 1
require 'rubygems'
require 'mechanize'
require 'uri'
require 'pp'
require 'yaml'

@args = ARGV
@src = @args[0]
@dst = @args[1]
@count = @args[2] && @args[2].to_i
@mobile = !!@args[3]

@src = "http://#{@args[0].gsub(/^(((http(s)?:)?\/\/)?)/i, '')}"

puts "Scanning url: #{@src}"


def keys_to_sym src
  if src.is_a? Array
    src.map {|item| keys_to_sym item}
  elsif src.is_a? Hash
    Hash[src.map {|k, v| ["#{k}".to_sym, keys_to_sym(v)]}]
  else
    src
  end
end
def keys_to_str src
  if src.is_a? Array
    src.map {|item| keys_to_str item}
  elsif src.is_a? Hash
    Hash[src.map {|k, v| [k.to_s, keys_to_str(v)]}]
  else
    src
  end
end

def get_hash_file filename
  if File.exist?(filename)
    keys_to_sym YAML.load_file(filename)
  else
    nil
  end
end
def put_hash_file filename, props
  File.open(filename, 'w') do |f|
    f.write((keys_to_str props).to_yaml)
  end
end

@config = get_hash_file 'config.yml'
puts "Settings:"
pp @config

@mech = Mechanize.new { |agent|
  # Flickr refreshes after login
  agent.follow_meta_refresh = true
  agent.add_auth(@src, @config[:auth][:user], @config[:auth][:pass]) if @config[:auth]
  # agent.set_proxy 'localhost', 3000
  agent.user_agent_alias = "iPhone" if @mobile
}


@link_list = []
@outer_list = []
@urls_checked = []
@urls_to_check = []
@errors = []

def put_error url, error = nil
  @errors << url
  pp "#{[url, error].join("\t")}\n"
  # File.open("#{@src.gsub('http://', '')}.log", 'a+') do |file|
  #   file.write("#{[url, error].join("\t")}\n")
  # end
end

def find_url uri
  s, h, p, q = uri.scheme, uri.host, uri.path
  if !s || s == 'https'
    ( h ? @outer_list : @link_list ).find {|link| link if (link[:path]==(p || ''))}
  else
    nil
  end
end

def add_url_to_list url
  u = URI(url)
  s, h, p, q, f = u.scheme, u.host, u.path, u.query, u.fragment
  if !s || s == 'https'
    link = find_url(u)    
    if link
      link[:query] << q unless link[:query].include?(q)
    else
      ( h ? @outer_list : @link_list ) << {path: (p || ""), query: [q], host: h}
    end
    if !s && !h
      l = [@src, [p, q].join('?').chomp('?')].join('/').gsub(/([^:]|^)\/{2,}/, '\1/')  
      @urls_to_check << l if !(@urls_to_check + @urls_checked).find {|item| item == l}
    end
  end
end

def check_url url
  unless @urls_checked.include?(url) || @errors.include?(url)
    begin
      @mech.get(url) do |page|
        page.links.each do |link|
          _href = link.href.gsub(/([^:]|^)\/{2,}/, '\1/')
          u = URI(_href)
          add_url_to_list _href
        end
        # check_assets page
        # check_images page
      end
    rescue => e
      puts "#{e.methods.include?(:response_code) ? e.response_code : e.to_s} on #{url}"
      put_error url, e.methods.include?(:response_code) ? e.response_code : e.to_s
    end
  end
  if @urls_to_check.include?(url)
    @urls_checked << @urls_to_check.delete(url)
  end
end

def get_dst_head
  pathes = Dir.glob("#{@dst}/main.htm?") + Dir.glob("#{@dst}/index.htm?") + Dir.glob("#{@dst}/home.htm?")
  index = File.expand_path(pathes[0])
  page = @mech.get("file://#{index}")
  h = page.search("head").to_html
  page.search("head").to_html
end

def write_to_file filename, data
  File.open(filename, "w") { |f| f.write(data) }
end

def write_local_page
  head = get_dst_head
  local_dir = File.expand_path(@dst)
  prefix = 'proto_'
  @link_list = @link_list[0..(@count-1)] if (@count && @count>0)
  @link_list.each do |url|
    begin
      page = @mech.get(File.join(@src, url[:path]))
      # page.search("head").to_html
      page.search("head").remove
      page.search("body").before(head)
      uname = ['', page.filename].join.gsub(/^\//, '').gsub(/\//, '_')
      write_to_file File.join(local_dir, [prefix, uname].join('')), page.search("html").to_html
      puts "Page #{uname} is done"
    rescue => e
      puts "#{e.methods.include?(:response_code) ? e.response_code : e.to_s} on #{url}"
      put_error url, e.methods.include?(:response_code) ? e.response_code : e.to_s
    end
  end
end

puts puts '*'*25

check_url @src
@urls_to_check << @src
while (@urls_to_check.size > 0) && (!@count || @count<1 || (@link_list.size < @count))
  curr = @urls_to_check[0]
  puts "[#{@urls_checked.size}/#{@urls_to_check.size}] Checking url #{curr}"
  check_url curr
end
write_local_page



