#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to download Japanese METI Foreign User List (外国ユーザーリスト) from the METI website
# Usage: ruby scripts/download_foreign_user_list.rb [output_dir]

require 'mechanize'
require 'fileutils'
require 'date'

class ForeignUserListDownloader
  BASE_URL = 'https://www.meti.go.jp'
  LAW_PAGE = "#{BASE_URL}/policy/anpo/law00.html"

  attr_reader :agent, :last_download_url

  def initialize
    @agent = Mechanize.new do |a|
      a.user_agent_alias = 'Mac Safari'
      a.follow_meta_refresh = true
      a.redirect_ok = true
      a.open_timeout = 60
      a.read_timeout = 120
    end
    @last_download_url = nil
  end

  def download(output_dir = 'reference-docs')
    puts "Fetching #{LAW_PAGE}..."

    page = @agent.get(LAW_PAGE)

    # Find the Foreign User List link
    # The link text is "外国ユーザーリスト" (not the one with "について")
    ful_link = page.links.find do |l|
      text = l.text.strip
      # Match exact "外国ユーザーリスト" but not "外国ユーザーリストについて" or other variants
      text == '外国ユーザーリスト' ||
        (text.include?('外国ユーザーリスト') && !text.include?('について') && !text.include?('Q&A'))
    end

    unless ful_link
      puts "Searching for Excel file links..."
      # Try to find Excel file links directly
      ful_link = page.links.find { |l| l.href&.match?(/\.(xlsx?|xls)$/i) && l.text.include?('外国ユーザー') }
    end

    unless ful_link
      puts "ERROR: Could not find Foreign User List link"
      puts "Available links containing '外国':"
      page.links.each do |l|
        puts "  - #{l.text.strip[0..50]} => #{l.href}" if l.text.include?('外国')
      end
      return nil
    end

    puts "Found link: #{ful_link.text.strip} => #{ful_link.href}"

    # Check if this is an HTML page or a direct file
    if ful_link.href.end_with?('.html') || ful_link.href.end_with?('.htm')
      # Navigate to the page and find the Excel download link
      puts "Navigating to download page..."
      download_page = @agent.click(ful_link)

      # Find Excel file links on this page
      excel_link = download_page.links.find do |l|
        l.href&.match?(/\.(xlsx?|xls)$/i)
      end

      if excel_link
        puts "Found Excel file: #{excel_link.href}"
        file_page = @agent.click(excel_link)
        return save_file(file_page, output_dir)
      else
        puts "ERROR: Could not find Excel file on download page"
        puts "Page links:"
        download_page.links.each do |l|
          puts "  - #{l.text.strip[0..50]} => #{l.href}" if l.href&.match?(/\.(xlsx?|xls|pdf)$/i)
        end
        return nil
      end
    else
      # Direct file download
      file_page = @agent.click(ful_link)
      return save_file(file_page, output_dir)
    end
  end

  private

  def save_file(page, output_dir)
    filename = extract_filename(page)

    # Capture the full download URL
    @last_download_url = page.uri.to_s

    # Create output directory
    FileUtils.mkdir_p(output_dir)

    # Save the file
    output_path = File.join(output_dir, filename)
    page.save_as(output_path)

    puts "Downloaded to: #{output_path}"
    output_path
  end

  def extract_filename(page)
    # Try to get filename from Content-Disposition header
    if page.response['content-disposition']
      match = page.response['content-disposition'].match(/filename="?([^";]+)"?/)
      return match[1] if match
    end

    # Fall back to URI path
    uri_path = page.uri.path
    File.basename(uri_path)
  end
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  output_dir = ARGV[0] || 'reference-docs'

  downloader = ForeignUserListDownloader.new
  result = downloader.download(output_dir)

  if result
    puts "Success!"
    exit 0
  else
    puts "Failed!"
    exit 1
  end
end
