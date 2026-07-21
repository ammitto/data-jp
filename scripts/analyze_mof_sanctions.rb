#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to analyze MOF sanctions Excel file column structure
# Creates a comparison table of columns across all sheets

require 'roo'
require 'json'

class MofSanctionsAnalyzer
  attr_reader :xlsx, :sheets_data

  def initialize(file_path)
    @xlsx = Roo::Spreadsheet.open(file_path)
    @sheets_data = {}
  end

  def analyze
    @xlsx.sheets.each do |sheet_name|
      @xlsx.sheet(sheet_name)

      first_row = @xlsx.first_row
      last_row = @xlsx.last_row
      first_col = @xlsx.first_column
      last_col = @xlsx.last_column

      next unless first_row && last_row && first_row < last_row

      # Try to find the header row (usually row 2, but check for "告示日付" which is common)
      header_row = find_header_row(first_row, last_row, first_col, last_col)

      # Extract headers from the identified row
      headers = extract_headers(header_row, first_col, last_col)

      # Get entity type (個人 vs 団体) from sheet name
      entity_type = determine_entity_type(sheet_name)

      @sheets_data[sheet_name] = {
        headers: headers,
        header_row: header_row,
        data_rows: last_row - header_row,
        entity_type: entity_type,
        columns: headers.size
      }
    end

    @sheets_data
  end

  def generate_comparison_table
    puts "\n" + "=" * 120
    puts "MOF SANCTIONS EXCEL - COLUMN COMPARISON TABLE"
    puts "=" * 120

    # Collect all unique headers
    all_headers = Set.new
    @sheets_data.each_value do |data|
      data[:headers].each { |h| all_headers << h }
    end

    # Count frequency of each header
    header_freq = Hash.new(0)
    header_by_type = { individual: Hash.new(0), organization: Hash.new(0), other: Hash.new(0) }

    @sheets_data.each_value do |data|
      data[:headers].each do |h|
        header_freq[h] += 1
        case data[:entity_type]
        when :individual
          header_by_type[:individual][h] += 1
        when :organization
          header_by_type[:organization][h] += 1
        else
          header_by_type[:other][h] += 1
        end
      end
    end

    # Sort by frequency
    sorted_headers = all_headers.sort_by { |h| [-header_freq[h], h] }

    # Print header comparison by entity type
    puts "\n" + "-" * 120
    puts "COLUMNS BY ENTITY TYPE"
    puts "-" * 120

    individual_sheets = @sheets_data.select { |_, d| d[:entity_type] == :individual }
    org_sheets = @sheets_data.select { |_, d| d[:entity_type] == :organization }

    puts "\n[INDIVIDUAL (個人) SHEETS: #{individual_sheets.size} sheets]"
    puts sprintf("%-30s | %5s | %s", "Column", "Count", "Present in sheets")
    puts "-" * 100
    sorted_headers.each do |h|
      next unless header_by_type[:individual][h] > 0
      sheets_list = individual_sheets.select { |_, d| d[:headers].include?(h) }.keys.map { |n| n[0..15] }.join(", ")
      puts sprintf("%-30s | %5d | %s", h[0..28], header_by_type[:individual][h], sheets_list[0..60])
    end

    puts "\n[ORGANIZATION (団体) SHEETS: #{org_sheets.size} sheets]"
    puts sprintf("%-30s | %5s | %s", "Column", "Count", "Present in sheets")
    puts "-" * 100
    sorted_headers.each do |h|
      next unless header_by_type[:organization][h] > 0
      sheets_list = org_sheets.select { |_, d| d[:headers].include?(h) }.keys.map { |n| n[0..15] }.join(", ")
      puts sprintf("%-30s | %5d | %s", h[0..28], header_by_type[:organization][h], sheets_list[0..60])
    end

    # Print full comparison matrix
    puts "\n" + "=" * 120
    puts "FULL COLUMN PRESENCE MATRIX"
    puts "=" * 120

    # Only show sheets with actual data (not "解除" or "一覧")
    active_sheets = @sheets_data.reject { |k, _| k.include?("解除") || k == "一覧" }.keys

    # Truncate sheet names for display
    sheet_labels = active_sheets.map { |n| n.gsub(/[（）()]/, "")[0..12].ljust(13) }

    puts "\n#{sprintf("%-28s", "Column")} | #{sheet_labels.join(" | ")}"
    puts "-" * 28 + "-+-" + ("-" * 13 + "-+-") * active_sheets.size

    sorted_headers.each do |header|
      row = [header[0..26].ljust(28)]
      active_sheets.each do |sheet_name|
        has = @sheets_data[sheet_name][:headers].include?(header) ? "✓" : ""
        row << has.center(13)
      end
      puts row.join(" | ")
    end

    # Summary
    puts "\n" + "=" * 120
    puts "SUMMARY"
    puts "=" * 120

    puts "\n| Sheet Name | Entity Type | Columns | Data Rows |"
    puts "|------------|-------------|---------|-----------|"
    @sheets_data.each do |name, data|
      next if name.include?("解除") || name == "一覧"
      type_label = data[:entity_type] == :individual ? "個人" :
                   data[:entity_type] == :organization ? "団体" : "Other"
      puts "| #{name[0..35].ljust(35)} | #{type_label.center(11)} | #{data[:columns].to_s.center(7)} | #{data[:data_rows].to_s.center(9)} |"
    end

    # Recommended schema columns
    puts "\n" + "=" * 120
    puts "RECOMMENDED SCHEMA COLUMNS"
    puts "=" * 120

    puts "\n[INDIVIDUAL SCHEMA - Core Columns (in 80%+ of individual sheets)]"
    individual_cols = sorted_headers.select { |h| header_by_type[:individual][h] >= individual_sheets.size * 0.8 }
    individual_cols.each { |h| puts "  - #{h}" }

    puts "\n[INDIVIDUAL SCHEMA - Extended Columns]"
    individual_extended = sorted_headers.select do |h|
      header_by_type[:individual][h] > 0 &&
        header_by_type[:individual][h] < individual_sheets.size * 0.8
    end
    individual_extended.each { |h| puts "  - #{h} (#{header_by_type[:individual][h]}/#{individual_sheets.size} sheets)" }

    puts "\n[ORGANIZATION SCHEMA - Core Columns (in 80%+ of org sheets)]"
    org_cols = sorted_headers.select { |h| header_by_type[:organization][h] >= org_sheets.size * 0.8 }
    org_cols.each { |h| puts "  - #{h}" }

    puts "\n[ORGANIZATION SCHEMA - Extended Columns]"
    org_extended = sorted_headers.select do |h|
      header_by_type[:organization][h] > 0 &&
        header_by_type[:organization][h] < org_sheets.size * 0.8
    end
    org_extended.each { |h| puts "  - #{h} (#{header_by_type[:organization][h]}/#{org_sheets.size} sheets)" }

    {
      all_headers: sorted_headers,
      header_frequency: header_freq,
      by_entity_type: header_by_type,
      sheets_data: @sheets_data
    }
  end

  private

  def find_header_row(first_row, last_row, first_col, last_col)
    # Check first 5 rows for common header patterns
    first_row.upto([first_row + 5, last_row].min).each do |row|
      # Check if this row contains "告示日付" which is the standard first header
      val = @xlsx.cell(row, first_col).to_s
      # Remove HTML tags and whitespace for comparison
      clean_val = val.gsub(/<[^>]+>/, "").gsub(/[\s\u3000]/, "")
      return row if clean_val.include?("告示日付")
    end
    # Default to row 2 (typical structure: row 1 = title, row 2 = headers)
    first_row + 1
  end

  def extract_headers(header_row, first_col, last_col)
    headers = []
    first_col.upto(last_col).each do |col|
      val = @xlsx.cell(header_row, col).to_s
      # Remove HTML tags first
      val = val.gsub(/<[^>]+>/, "")
      # Strip both ASCII space and full-width space (U+3000), collapse multiple spaces
      val = val.gsub(/[\s\u3000]+/, " ").strip
      headers << (val.empty? ? "Column_#{col}" : val)
    end
    headers
  end

  def determine_entity_type(sheet_name)
    if sheet_name.include?("個人")
      :individual
    elsif sheet_name.include?("団体") || sheet_name.include?("銀行")
      :organization
    else
      :other
    end
  end
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  file_path = ARGV[0] || "reference-docs/shisantouketsu20260305.xlsx"

  analyzer = MofSanctionsAnalyzer.new(file_path)
  analyzer.analyze
  result = analyzer.generate_comparison_table

  # Save JSON analysis
  json_path = file_path.sub(/\.xlsx?$/i, "_column_analysis.json")
  File.write(json_path, JSON.pretty_generate(result))
  puts "\nAnalysis saved to: #{json_path}"
end
