#!/usr/bin/env ruby
# frozen_string_literal: true

# All-in-one script to download and convert Japanese METI Foreign User List
# Usage: ruby scripts/update_foreign_user_list.rb

require_relative 'download_foreign_user_list'
require_relative 'convert_foreign_user_list_to_yaml'
require 'fileutils'

def main
  puts "=" * 60
  puts "METI Foreign User List Update"
  puts "=" * 60
  puts

  # Step 1: Download
  puts "Step 1: Downloading Excel file..."
  downloader = ForeignUserListDownloader.new
  xlsx_path = downloader.download('reference-docs')

  unless xlsx_path
    puts "ERROR: Failed to download Excel file"
    exit 1
  end

  # Get the actual download URL
  source_url = downloader.last_download_url
  puts "Source URL: #{source_url}"

  puts

  # Step 2: Convert
  puts "Step 2: Converting to YAML..."

  # Extract date from filename for output path
  date_match = xlsx_path.match(/(\d{8})/)
  date_str = date_match ? date_match[1] : Date.today.strftime('%Y%m%d')
  output_path = "sources/sanction-lists/foreign-user-list/#{date_str}.yml"

  converter = ForeignUserListConverter.new(xlsx_path)

  # Set source URL from the download
  converter.set_source_url(source_url) if source_url

  result = converter.convert

  unless result
    puts "ERROR: Failed to convert Excel"
    exit 1
  end

  # Write YAML file
  schema_comment = "# yaml-language-server: $schema=../../../schemas/jp-announcement.yml\n"
  FileUtils.mkdir_p(File.dirname(output_path))
  File.write(output_path, schema_comment + result.to_yaml(line_width: -1))

  entities_count = result['sanction_details']['entities'].size
  puts "Successfully converted to #{output_path}"
  puts "Total entities: #{entities_count}"

  puts
  puts "=" * 60
  puts "Update complete!"
  puts "  Downloaded: #{xlsx_path}"
  puts "  Output:     #{output_path}"
  puts "  Entities:   #{entities_count}"
  puts "=" * 60
end

main if __FILE__ == $PROGRAM_NAME
