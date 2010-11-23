require 'rubygems'
require 'bundler'
Bundler.setup
Bundler.require

require 'date'
require 'feedzirra'
require 'couchrest'

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
 
feed.entries.each do |entry|
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
    puts "Downloading #{entry.title}"
    response = RestClient.get(epub_link)
    if response.code == 200
      File.open("#{NOOK_DIR}/#{entry.title}.epub", 'w') {|file| file.write(response.body) }
    end
  end
end

# Magazine
# property :title, String
# property :issue_number, Fixnum
# property :month, Fixnum
# property :year, Fixnum
# property :entry_id, String
# property :epub_link, String
# property :updated_at, Time
