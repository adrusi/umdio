# Script for adding umd testudo courses to a mongodb database using open-uri and nokogiri
# Use: ruby courses_scraper.rb <years> 
# Runs in 3m20s on Rob's macbook for years 2014 and 2015. Not bad.

require 'open-uri'
require 'nokogiri'
require 'mongo'
include Mongo

#set up mongo database - code from ruby mongo driver tutorial
host = ENV['MONGO_RUBY_DRIVER_HOST'] || 'localhost'
port = ENV['MONGO_RUBY_DRIVER_PORT'] || MongoClient::DEFAULT_PORT

#announce connection and connect
puts "Connecting to #{host}:#{port}"
db = MongoClient.new(host, port, pool_size: 2, pool_timeout: 2).db('umdclass')

years = ARGV
semesters = years.map { |e| [e + '01', e + '05', e + '08', e + '12'] }.flatten # year plus starting month is term id


# Get the urls for all the department pages
dep_urls = []
semesters.each do |semester|
    puts "Searching for courses in term #{semester}"

    base_url = "https://ntst.umd.edu/soc/#{semester}"
    
    Nokogiri::HTML(open(base_url)).search('span.prefix-abbrev').each do |e|
      dep_urls << "https://ntst.umd.edu/soc/#{semester}/#{e.text}"
    end
    
    puts "#{dep_urls.length} department/semesters so far"
end

# add the courses from each department to the database
dep_urls.each do |url|
  dept_id = url.split('/soc/')[1][7,10] 
  semester = url.split('/soc/')[1][0,6] 
  course_array = []
  coll = db.collection('courses' + semester)
  page = Nokogiri::HTML(open(url))
  department = page.search('span.course-prefix-name').text.strip

  page.search('div.course').each do |course|
    description =  (course.css('div.approved-course-texts-container').text + course.css('div.course-texts-container').text).strip.gsub(/\t|\r\n/,'')
    relationships = {
      coreqs: /Corequisite: ([^.]+)/.match(description).to_a[1],
      prereqs: /Prerequisite: ([^.]+)/.match(description).to_a[1],
      restrictions: /(Restriction: ([^.]+))/.match(description).to_a[1],
      restricted_to: /Restricted to ([^.]+)/.match(description).to_a[1],
      credit_only_granted_for: /Credit only granted for:([^.]+)/.match(description).to_a[1],
      credit_granted_for: /Credit granted for([^.]+)/.match(description).to_a[1],
      formerly: /Formerly:([^.]+)/.match(description).to_a[1],
      also_offered_as: /Also offered as([^.]+)/.match(description).to_a[1]
    }

    course_array << {
      course_id: course.search('div.course-id').text,
      name: course.css('span.course-title').first.content,
      dept_id: dept_id,
      department: department,
      semester: semester,
      credits: course.css('span.course-min-credits').first.content,
      grading_method: course.at_css('span.grading-method abbr') ? course.at_css('span.grading-method abbr').attr('title').split(', ') : [],
      core: course.css('div.core-codes-group').text.gsub(/\s/, '').delete('CORE:').split(','),
      gen_ed: course.css('div.gen-ed-codes-group').text.gsub(/\s/, '').delete('General Education:').split(','),
      description: description,
      relationships: relationships
    }

  end
  puts "inserting courses from #{dept_id}"
  
  #should be upserts, if we can swing it. That way we can run this lots of times!
  coll.insert(course_array) unless course_array.empty?

end