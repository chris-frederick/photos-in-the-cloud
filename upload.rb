#!/usr/bin/env rvm 1.9.3 do ruby

# Upload a file to Amazon S3 using its SHA-1 hash as its filename

require_relative 'options'
require_relative 's3file'

require 'rubygems'
require 'yaml'
require 'aws-sdk'

################################################################################
# Process YAML and command-line options
################################################################################

# Read the YAML config file if it exists
config_file = File.join(File.dirname(__FILE__), "config.yml")
config = File.exist?(config_file) ? YAML.load(File.read(config_file)) : Hash.new

# If the YAML config file wasn't formatted correctly, quit with an error message
unless config.kind_of?(Hash)
  puts <<END
config.yml is formatted incorrectly.  Please use the following format:

access_key_id: YOUR_ACCESS_KEY_ID
secret_access_key: YOUR_SECRET_ACCESS_KEY

END
  exit 1
end

# Process command-line options
opts = process_options

# Command-line options take priority over YAML configuration
config['access_key_id'] = opts[:aws_key_id] unless opts[:aws_key_id].nil?
config['secret_access_key'] = opts[:aws_secret_key] unless opts[:aws_secret_key].nil?

# If no AWS access keys have been specified, quit with an error message
if config['access_key_id'].nil? || config['secret_access_key'].nil?
    puts <<END
Specify your AWS credentials on the command-line or in config.yml as follows:

access_key_id: YOUR_ACCESS_KEY_ID
secret_access_key: YOUR_SECRET_ACCESS_KEY

END
    exit 1
end

################################################################################
# MAIN
################################################################################

# Configure Amazon Web Services
AWS.config(config)

# Get an instance of the S3 interface using the default configuration
s3 = AWS::S3.new

# Get a reference to the specified bucket
bucket = s3.buckets[opts[:bucket]]

# Print local file info
file = S3File.new(opts[:file], "r")
puts <<FILE_INFO
--------------------------------------------------------------------------------
DEBUG: The file's MIME type is #{file.mime_type}
DEBUG: The file's MD5 hash is #{file.md5_hash}
DEBUG: The file's SHA-1 hash is #{file.sha1_hash}
--------------------------------------------------------------------------------

FILE_INFO

# Upload the specified file
object = bucket.objects[file.s3_path]

if object.exists?
    puts "#{file.path} already exists at #{object.public_url}."
else
    puts "Uploading #{file.path} to #{object.public_url}..."
    object.write(file, :content_md5 => file.md5_hash, :content_type => file.mime_type)
    puts "Done."
end

# Print remote file info
info = object.head.map { |key, value| "DEBUG: #{key} = #{value.inspect}" }

puts
puts "Printing object info..."
puts <<-RESPONSE
--------------------------------------------------------------------------------
#{ info.join("\n") }
--------------------------------------------------------------------------------

RESPONSE
