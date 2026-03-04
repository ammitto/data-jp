#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to fetch Russia-related sanctions PDFs from METI website
# Downloads all PDFs with links containing '禁止措置の対象'
# Parses the PDFs to extract sanctioned entities

require 'nokogiri'
require 'open-uri'
require 'fileutils'
require 'net/http'
require 'uri'

class RussiaSanctionsFetcher
  BASE_URL = 'https://www.meti.go.jp'
  PAGE_URL = 'https://www.meti.go.jp/policy/external_economy/trade_control/01_seido/04_seisai/crimea.html'
  OUTPUT_DIR = 'reference-docs/russia-sanctions'
  YAML_OUTPUT_DIR = 'sources/sanction-lists/russia-sanctions'

  # Timeout settings (in seconds)
  OPEN_TIMEOUT = 120
  READ_TIMEOUT = 300
  MAX_RETRIES = 3

  # Browser-like headers to avoid being blocked
  BROWSER_HEADERS = {
    'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
    'Accept-Language' => 'ja,en-US;q=0.9,en;q=0.8',
    'Connection' => 'keep-alive',
    'Upgrade-Insecure-Requests' => '1',
    'Sec-Fetch-Dest' => 'document',
    'Sec-Fetch-Mode' => 'navigate',
    'Sec-Fetch-Site' => 'none',
    'Sec-Fetch-User' => '?1',
    'Cache-Control' => 'max-age=0'
  }.freeze

  def initialize
    @downloaded_files = []
    FileUtils.mkdir_p(OUTPUT_DIR)
    FileUtils.mkdir_p(YAML_OUTPUT_DIR)
  end

  def run
    puts "Fetching Russia sanctions page..."
    html = fetch_with_retry(PAGE_URL)
    return unless html

    # Debug: Save the HTML for inspection
    File.write('reference-docs/russia-sanctions/debug_page.html', html)
    puts "  Saved HTML to reference-docs/russia-sanctions/debug_page.html"

    doc = Nokogiri::HTML(html)

    # Debug: Print all links
    puts "\nAll links found:"
    doc.css('a').first(20).each do |link|
      href = link['href']
      text = link.text.strip[0..60]
      puts "  - #{text}... -> #{href}"
    end

    # Find all links with their date context
    target_links = find_target_links(doc)

    puts "\nFound #{target_links.size} target PDFs to download"

    # Download each PDF
    target_links.each do |link_info|
      download_pdf(link_info)
    end

    # Save metadata file with dates for each PDF
    save_metadata(target_links)

    puts "\nDownloaded #{@downloaded_files.size} files to #{OUTPUT_DIR}"
    @downloaded_files
  end

  private

  def fetch_with_retry(url, retries: MAX_RETRIES)
    retries.times do |attempt|
      begin
        puts "  Attempt #{attempt + 1}/#{retries}: #{url}" if attempt > 0
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT

        request = Net::HTTP::Get.new(uri.request_uri)
        # Add browser-like headers
        BROWSER_HEADERS.each do |key, value|
          request[key] = value
        end

        response = http.request(request)

        if response.code == '200'
          return response.body
        else
          puts "  HTTP #{response.code}"
        end
      rescue => e
        puts "  Error: #{e.message}"
        sleep(5 * (attempt + 1)) if attempt < retries - 1
      end
    end
    nil
  end

  def find_target_links(doc)
    links = []

    # Find all anchor tags
    doc.css('a').each do |link|
      href = link['href']
      text = link.text.strip

      # Check if link text contains our target phrases
      next unless text.include?('禁止措置の対象となる')

      # Get the parent context to find the date
      date = extract_date_from_context(link)

      # Build full URL
      full_url = href.start_with?('http') ? href : BASE_URL + href

      # Use the original filename from the URL
      original_filename = File.basename(URI.parse(full_url).path)

      links << {
        url: full_url,
        text: text,
        date: date,
        filename: original_filename
      }
    end

    # Remove duplicates and sort by date (newest first)
    links.uniq { |l| l[:url] }.sort_by { |l| l[:date] || '' }.reverse
  end

  def extract_date_from_context(link)
    # Look for date patterns in parent elements
    # The HTML has format like: ＜令和7年9月12日公布＞
    parent = link.parent
    return nil unless parent

    # Check parent and grandparent text for Japanese date format
    [parent, parent.parent, parent.parent&.parent].each do |element|
      next unless element

      text = element.text
      # Match patterns like ＜令和7年9月12日公布＞ or ＜令和7年9月12日発表＞
      match = text.match(/＜(令和|平成)(\d+)年(\d+)月(\d+)日(公布|発表)＞/)
      if match
        era = match[1]
        era_year = match[2].to_i
        month = match[3].to_i
        day = match[4].to_i
        western_year = era_to_western(era, era_year)
        return format('%04d-%02d-%02d', western_year, month, day)
      end

      # Also try patterns without brackets
      match = text.match(/(令和|平成)(\d+)年(\d+)月(\d+)日/)
      if match
        era = match[1]
        era_year = match[2].to_i
        month = match[3].to_i
        day = match[4].to_i
        western_year = era_to_western(era, era_year)
        return format('%04d-%02d-%02d', western_year, month, day)
      end
    end

    nil
  end

  def era_to_western(era, era_year)
    base_years = {
      '令和' => 2018,
      '平成' => 1988,
      '昭和' => 1925
    }
    base_years[era] + era_year
  end

  def save_metadata(links)
    require 'yaml'

    metadata = {}
    links.each do |link|
      metadata[link[:filename]] = {
        'url' => link[:url],
        'date' => link[:date],
        'text' => link[:text][0..100]  # Truncate for readability
      }
    end

    metadata_path = File.join(OUTPUT_DIR, 'metadata.yml')
    File.write(metadata_path, metadata.to_yaml)
    puts "\nSaved metadata to #{metadata_path}"
  end

  def generate_filename(text, date)
    # Create a safe filename from the link text and date
    safe_text = text.gsub(/[^\w\u3040-\u9fff\-]/, '_').squeeze('_')[0..50]
    date_str = date ? date.gsub(/[年月日]/, '') : 'unknown'
    "#{date_str}_#{safe_text}.pdf"
  end

  def download_pdf(link_info)
    url = link_info[:url]
    filename = link_info[:filename]
    output_path = File.join(OUTPUT_DIR, filename)

    # Skip if already exists
    if File.exist?(output_path)
      puts "  ✓ Already exists: #{filename}"
      @downloaded_files << output_path
      return
    end

    puts "  Downloading: #{filename}"
    puts "    URL: #{url}"

    begin
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT

      request = Net::HTTP::Get.new(uri.request_uri)
      # Add browser-like headers
      BROWSER_HEADERS.each do |key, value|
        request[key] = value
      end

      response = http.request(request)

      if response.code == '200'
        File.write(output_path, response.body, mode: 'wb')
        @downloaded_files << output_path
        puts "    ✓ Downloaded successfully"
      else
        puts "    ✗ Failed: HTTP #{response.code}"
      end
    rescue => e
      puts "    ✗ Failed: #{e.message}"
    end
  end
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  fetcher = RussiaSanctionsFetcher.new
  fetcher.run
end
