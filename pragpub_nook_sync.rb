require 'rubygems'
require 'bundler'
Bundler.setup
Bundler.require

require 'date'
require 'feedzirra'
require 'couchrest'
require 'em-http'
require 'eventmachine'

NOOK_DIR = "/media/nook/my documents"

db = CouchRest.database!("http://127.0.0.1:5984/pragpub_nook_sync")
issue_no_map = <<MAP
function(doc) {
  if(doc.issue_number) {
    emit(doc.issue_number)
  }
}
MAP

begin
  db.get("_design/magazine")
rescue RestClient::ResourceNotFound
  response = db.save_doc("_id" => "_design/magazine",
    :views => {
      :issue_no => {
        :map => issue_no_map
      }
    }
  )

  puts response.inspect
end

feed_url = "http://pragprog.com/magazines.opds"
feed = Feedzirra::Feed.fetch_and_parse(feed_url)
 
epub_links = feed.entries.map do |entry|
  number, month_year = entry.title.split(',')
  month, year = month_year.split
  month = Date::MONTHNAMES.index(month)
  number = number.split.last
  epub_link = entry.links.detect {|link| /epub$/.match(link) }

  if db.view('magazine/issue_no', key: number)['rows'].empty?
    response = db.save_doc(title: entry.title,
                           issue_number: number,
                           month: month,
                           year: year,
                           entry_id: entry.entry_id,
                           epub_link: epub_link,
                           updated_at: Time.now)
    puts response.inspect
  end

  [entry.title, epub_link]
end

# Magazine
# property :title, String
# property :issue_number, Fixnum
# property :month, Fixnum
# property :year, Fixnum
# property :entry_id, String
# property :epub_link, String
# property :updated_at, Time

http_callback = proc do |http, multi, title|
  case http.response_header.status
  when 302
    real_epub_link = http.response_header["LOCATION"]
    puts "Redirecting from #{http.uri} to #{real_epub_link}"
    new_http = EM::HttpRequest.new(real_epub_link).get
    new_http.callback {
      http_callback.call(new_http, multi, title)
    }

    multi.add(new_http)
  when 200
    filename  = "#{NOOK_DIR}/#{title}.epub"
    puts "Writing to #{filename}"
    File.open(filename, 'w') {|file| file.write(http.response) }
  else
    puts http.response_header.status
  end
end


EM.run {
  multi = EM::MultiRequest.new
  multi.callback {
    multi.responses[:failed].each do |response|
      puts "Failed to retrieve: #{response.uri}"
    end

    EM.stop
  }

  epub_links.each do |(title, link)|
    puts "Downloading #{title} @ #{link}"
    http = EM::HttpRequest.new(link).get
    http.callback {
      http_callback.call(http, multi, title)
    }

    multi.add(http)
  end
}
