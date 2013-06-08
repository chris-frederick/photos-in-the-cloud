#!/usr/bin/env rvm 1.9.3 do ruby

# Upload a file to Amazon S3 using its SHA-1 hash as its filename

require 'base64'
require 'cgi'
require 'openssl'
require 'digest/sha1'
require 'net/http'

require 'trollop'
require 'nokogiri'

###############################################################################
# Utility Methods
###############################################################################

# Get the current time
def current_time
    Time.now.strftime("%a, %d %b %Y %H:%M:%S %z")
end

# Calculate the Base64-encoded SHA-1 HMAC signature of a key and string
def hmac_signature(key, string_to_sign)
    digest = OpenSSL::HMAC.digest('sha1', key, string_to_sign)
    signature = Base64.encode64(digest)
end

# Calculate the authentication header for an Amazon Web Services request
def auth_header(access_key_id, secret_access_key, string_to_sign)
    signature = hmac_signature(secret_access_key, string_to_sign)
    header = "AWS #{access_key_id}:#{signature}"
end

###############################################################################
# Classes
###############################################################################

class Bucket

    def initialize(name, region="s3")
        @name = name
        @region = region
    end

    def get_files_for_key(id, key)
        time = current_time()
        string_to_sign = <<-EOL
GET


#{time}
/#{@name}/
        EOL
        # Remove trailing whitespace
        string_to_sign.rstrip!
        host_name = "#{@name}.#{@region}.amazonaws.com"
        uri = URI.parse("http://#{host_name}/")
        http = Net::HTTP.new(uri.host, uri.port)
        # TIP: Try uncommenting the following line to debug issues!
        # http.set_debug_output($stdout)
        request_files = Net::HTTP::Get.new(uri.request_uri)
        request_files.delete 'Accept'
        request_files.delete 'User-Agent'
        request_files.add_field 'Host', host_name
        request_files.add_field 'Date', time
        request_files.add_field 'Authorization', auth_header(id, key, string_to_sign)
        response = http.request(request_files)

        nodes = Array.new
        xml_reader = Nokogiri::XML::Reader(response.body)
        xml_reader.each do |node|
            if node.name == "Key"
                nodes << node.inner_xml
            end
        end
        nodes
    end

    attr_reader :name
end

###############################################################################
# MAIN
###############################################################################

# Selected elements from the Amazon S3 request to sign
#
# For more information, see
# http://docs.aws.amazon.com/AmazonS3/latest/dev/RESTAuthentication.html

###############################################################################
# Step 1: Parse command-line options
###############################################################################

# Get command-line options as a hash object with Trollop
# opts[:file] holds the specified file,
# opts[:bucket] holds the specified bucket, etc.
opts = Trollop::options do
    version "S3 Photo Manager 0.0.1 (c) 2013 Christopher Frederick"

    opt :file, "File to upload",
        :type => :string, :required => true

    opt :bucket, "Amazon S3 bucket",
        :type => :string, :required => true

    opt :region, "Region where the bucket is located. By default, this is US Standard. Use 'us-west-2' for US West (Oregon), 'us-west-1' for US West (Northern California), 'eu' for EU (Ireland), 'ap-southeast-1' for Asia Pacific (Singapore), 'ap-southeast-2' for Asia Pacific (Sydney), 'ap-northeast-1' for Asia Pacific (Tokyo), and 'sa-east-1' for South America (Sao Paulo)",
        :type => :string

    opt :path, "Photo path (filename prefix) in the specified bucket",
        :type => :string, :required => true

    opt :aws_key_id, "Access key ID for Amazon Web Services",
        :type => :string, :required => true

    opt :aws_secret_key, "Secret access key for Amazon Web Services",
        :type => :string, :required => true
end

# DEBUG: Print the opts hash
p opts

###############################################################################
# Step 2: Examine the file to upload
###############################################################################

# Open the file & determine its MIME type by reading its magic header
# For more information, see
# http://www.garykessler.net/library/file_sigs.html
filename = opts[:file]
file = File.open(filename, "rb")

# I'm currently checking for the following two magic headers:
# FF D8 FF E0 xx xx 4A 46 49 46 00 - JPEG/JFIF graphics file
# FF D8 FF E1 xx xx 45 78 69 66 00 - Digital camera JPG using EXIF
file_type = ''
jpg_regexp = Regexp.new("\xff\xd8\xff(\xe0|\xe1).{2}JFIF".force_encoding("binary"))
case IO.read(filename, 10)
when /^#{jpg_regexp}/
    file_type = 'image/jpeg'
end

# Abort if the file doesn't have one of the magic headers listed above
# TODO: Add more file types as necessary
if file_type.empty?
    puts "#{filename} does not appear to be a supported file type"
    puts "This script currently only supports JPEG files"
    abort
end

###############################################################################
# Step 3: Get the current time
###############################################################################

# %a - Abbreviated weekday name ("Sun")
# %d - Day of the month, zero-padded (01..31)
# %b - Abbreviated month name ("Jan")
# %Y - Year with century (can be negative, 4 digits at least)
# %H - Hour of the day, 24-hour clock, zero-padded (00..23)
# %M - Minute of the hour (00..59)
# %S - Second of the minute (00..60)
# %z - Time zone as hour and minute offset from UTC (e.g. +0900)
# Example: Sun, 01 Jan 2001 00:00:00 +0900
time_string = Time.now.strftime("%a, %d %b %Y %H:%M:%S %z")

# Calculate the file's SHA-1 hash
file_size = file.size
file_contents = file.read
sha1_hash = Digest::SHA1.hexdigest "blob #{file_size}\0#{file_contents}"

# Calculate the file's MD5 hash
md5_hash = Digest::MD5.base64digest file_contents

###############################################################################
# Step 4: Set the string to sign with your AWS secret access key
###############################################################################

bucket_name = opts[:bucket]
folder_name = opts[:path]
  file_name = sha1_hash
string_to_sign = "PUT
#{md5_hash}
#{file_type}
#{time_string}
/#{bucket_name}/#{folder_name}/#{file_name}"

# DEBUG: Print the string to sign
puts "DEBUG: The string to sign is:\n\n"
puts "-------------------------------\n#{string_to_sign}\n-------------------------------\n\n"

# Get the AWS secret access key
secret_access_key = opts[:aws_secret_key]

my_bucket = Bucket.new(opts[:bucket], opts[:region])
files = my_bucket.get_files_for_key(opts[:aws_key_id], opts[:aws_secret_key])

unless files.empty?
    puts "Received the following filenames:"
    count = 0
    files.each do |filename|
        count = count + 1
        puts "#{count}: #{filename}"
    end
end

# Calculate a Base64-encoded SHA-1 HMAC signature from
# string_to_sign and secret_access_key

hmac_digest = OpenSSL::HMAC.digest('sha1', secret_access_key, string_to_sign)
hmac_signature = Base64.encode64(hmac_digest)

# DEBUG: Print the HMAC signature
puts "DEBUG: The HMAC signature is #{hmac_signature}\n"

# Close the file
file.close
