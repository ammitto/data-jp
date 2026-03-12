#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to download and analyze Japan MOF Economic Sanctions lists
# Usage: ruby scripts/download_mof_sanctions.rb [output_dir]

require 'mechanize'
require 'roo'
require 'fileutils'
require 'json'
require 'date'

class MofSanctionsDownloader
  BASE_URL = 'https://www.mof.go.jp'
  LIST_PAGE = "#{BASE_URL}/policy/international_policy/gaitame_kawase/gaitame/economic_sanctions/list.html"

  attr_reader :agent, :last_download_url, :downloaded_file

  def initialize
    @agent = Mechanize.new do |a|
      a.user_agent_alias = 'Mac Safari'
      a.follow_meta_refresh = true
      a.redirect_ok = true
      a.open_timeout = 60
      a.read_timeout = 120
    end
    @last_download_url = nil
    @downloaded_file = nil
  end

  def download(output_dir = 'reference-docs')
    puts "Fetching #{LIST_PAGE}..."

    page = @agent.get(LIST_PAGE)

    # Find the Excel file link containing '資産凍結等対象者一覧（Excel 形式）'
    excel_link = page.links.find do |l|
      l.text.include?('資産凍結等対象者一覧') &&
        (l.text.include?('Excel') || l.href&.match?(/\.(xlsx?|xls)$/i))
    end

    unless excel_link
      puts "Searching for any Excel file links..."
      excel_link = page.links.find { |l| l.href&.match?(/\.(xlsx?|xls)$/i) }
    end

    unless excel_link
      puts "ERROR: Could not find Excel file link"
      puts "Available links:"
      page.links.each do |l|
        puts "  - #{l.text.strip[0..80]} => #{l.href}" if l.href&.match?(/\.(xlsx?|xls|pdf)$/i)
      end
      return nil
    end

    puts "Found link: #{excel_link.text.strip}"
    puts "URL: #{excel_link.href}"

    # Download the file
    file_page = @agent.click(excel_link)
    @last_download_url = file_page.uri.to_s

    FileUtils.mkdir_p(output_dir)

    filename = extract_filename(file_page)
    output_path = File.join(output_dir, filename)
    file_page.save_as(output_path)

    @downloaded_file = output_path
    puts "Downloaded to: #{output_path}"
    output_path
  end

  def analyze_columns(file_path = @downloaded_file)
    return nil unless file_path && File.exist?(file_path)

    puts "\nAnalyzing Excel file: #{file_path}"

    spreadsheet = Roo::Spreadsheet.open(file_path)
    sheets_info = {}

    spreadsheet.sheets.each_with_index do |sheet_name, idx|
      spreadsheet.sheet(sheet_name)

      puts "\n[Sheet #{idx + 1}] #{sheet_name}"

      # Get dimensions
      first_row = spreadsheet.first_row
      last_row = spreadsheet.last_row
      first_col = spreadsheet.first_column
      last_col = spreadsheet.last_column

      puts "  Rows: #{first_row}-#{last_row}, Columns: #{first_col}-#{last_col}"

      # Extract headers (assuming first row contains headers)
      headers = []
      if first_row && last_row && first_row <= last_row
        first_col.upto(last_col).each do |col|
          val = spreadsheet.cell(first_row, col)
          headers << (val&.to_s&.strip || "Column_#{col}")
        end
      end

      # Count data rows (excluding header)
      data_rows = last_row && first_row ? (last_row - first_row) : 0

      sheets_info[sheet_name] = {
        index: idx,
        headers: headers,
        header_count: headers.size,
        first_row: first_row,
        last_row: last_row,
        first_col: first_col,
        last_col: last_col,
        data_rows: data_rows,
        sample_data: extract_sample_data(spreadsheet, first_row, last_row, first_col, last_col)
      }

      puts "  Headers (#{headers.size}): #{headers.take(10).join(', ')}#{'...' if headers.size > 10}"
    end

    sheets_info
  end

  def generate_comparison_table(sheets_info)
    puts "\n" + '=' * 100
    puts "COLUMN COMPARISON TABLE ACROSS ALL SHEETS"
    puts '=' * 100

    # Collect all unique columns
    all_columns = Set.new
    sheets_info.each_value do |info|
      info[:headers].each { |h| all_columns << h unless h.start_with?('Column_') }
    end

    # Sort columns by frequency (most common first)
    column_frequency = Hash.new(0)
    sheets_info.each_value do |info|
      info[:headers].each { |h| column_frequency[h] += 1 unless h.start_with?('Column_') }
    end
    sorted_columns = all_columns.sort_by { |c| [-column_frequency[c], c] }

    # Print header row
    sheet_names = sheets_info.keys
    puts "\n#{'Column Name'.ljust(50)} | #{sheet_names.map { |n| n[0..15].ljust(16) }.join(' | ')}"
    puts '-' * 50 + '-+-' + ('-' * 16 + '-+-') * sheet_names.size

    # Print each column
    sorted_columns.each do |column|
      row = [column[0..48].ljust(50)]
      sheet_names.each do |sheet_name|
        has_col = sheets_info[sheet_name][:headers].include?(column) ? '✓' : ''
        row << has_col.center(16)
      end
      puts row.join(' | ')
    end

    # Summary statistics
    puts "\n" + '=' * 100
    puts "SUMMARY STATISTICS"
    puts '=' * 100

    puts "\n| Sheet Name | Headers | Data Rows |"
    puts "|------------|---------|-----------|"
    sheets_info.each do |name, info|
      puts "| #{name[0..30].ljust(30)} | #{info[:header_count].to_s.center(7)} | #{info[:data_rows].to_s.center(9)} |"
    end

    # Column frequency
    puts "\n" + '-' * 50
    puts "COLUMN FREQUENCY (appears in X of #{sheets_info.size} sheets)"
    puts '-' * 50
    sorted_columns.first(30).each do |col|
      freq = column_frequency[col]
      pct = (freq.to_f / sheets_info.size * 100).round(1)
      puts "  #{freq}/#{sheets_info.size} (#{pct}%) - #{col}"
    end

    # Generate JSON output for further processing
    {
      sheets: sheets_info,
      all_columns: sorted_columns,
      column_frequency: column_frequency,
      summary: {
        total_sheets: sheets_info.size,
        total_unique_columns: sorted_columns.size,
        sheets_info: sheets_info.transform_values { |v| { headers: v[:headers], data_rows: v[:data_rows] } }
      }
    }
  end

  private

  def extract_filename(page)
    if page.response['content-disposition']
      match = page.response['content-disposition'].match(/filename="?([^";]+)"?/)
      return match[1] if match
    end
    File.basename(page.uri.path)
  end

  def extract_sample_data(spreadsheet, first_row, last_row, first_col, last_col)
    return [] unless first_row && last_row && first_row < last_row

    samples = []
    # Get up to 3 sample rows
    sample_rows = [(first_row + 1)..(first_row + 3)].first.select { |r| r <= last_row }

    sample_rows.each do |row_idx|
      row_data = {}
      first_col.upto(last_col).each do |col|
        header = spreadsheet.cell(first_row, col)&.to_s&.strip || "col_#{col}"
        value = spreadsheet.cell(row_idx, col)
        row_data[header] = value if value
      end
      samples << row_data unless row_data.empty?
    end

    samples
  end
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  output_dir = ARGV[0] || 'reference-docs'

  downloader = MofSanctionsDownloader.new

  # Download the file
  file_path = downloader.download(output_dir)

  if file_path
    # Analyze columns
    sheets_info = downloader.analyze_columns(file_path)

    # Generate comparison table
    result = downloader.generate_comparison_table(sheets_info)

    # Save JSON analysis
    json_path = file_path.sub(/\.(xlsx?|xls)$/i, '_analysis.json')
    File.write(json_path, JSON.pretty_generate(result))
    puts "\nAnalysis saved to: #{json_path}"

    exit 0
  else
    puts "Failed to download file!"
    exit 1
  end
end
