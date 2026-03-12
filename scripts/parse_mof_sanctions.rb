#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to parse MOF sanctions Excel file and export to YAML files per# Output conforms to schemas/jp-announcement.yml
#
# Usage: ruby scripts/parse_mof_sanctions.rb [excel_path] [output_dir] [date_str]

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "mof_sanctions"

def main
  excel_path = ARGV[0] || "reference-docs/shisantouketsu20260305.xlsx"
  output_dir = ARGV[1] || "sources/sanction-lists/mof-asset-freeze"
  date_str = ARGV[2] || extract_date_from_filename(excel_path) || Time.now.strftime("%Y%m%d")

  unless File.exist?(excel_path)
    puts "ERROR: File not found: #{excel_path}"
    exit 1
  end

  puts "=" * 80
  puts "MOF Japan Sanctions Parser"
  puts "=" * 80
  puts "Input: #{excel_path}"
  puts "Output: #{output_dir}/"
  puts "Date: #{date_str}"
  puts

  # Export to YAML files per sanction list
  MofSanctions.export_to_yaml(excel_path, output_dir, date_str)

  puts
  puts "Done!"
end

def extract_date_from_filename(path)
  match = File.basename(path).match(/(\d{8})/)
  match ? match[1] : nil
end

main
