# frozen_string_literal: true

require_relative "mof_sanctions/field_mapping"
require_relative "mof_sanctions/entity"
require_relative "mof_sanctions/parser"

module MofSanctions
  class Error < StandardError; end

  class << self
    # Parse a MOF sanctions Excel file and    # @param file_path [String] Path to the Excel file
    # @param include_repealed [Boolean] Include repealed sanctions
    # @return [Hash] Sanction list ID => { sheet_name:, entities: }
    def parse(file_path, include_repealed: false)
      parser = Parser.new(file_path)
      parser.parse_all(include_repealed: include_repealed)
    end

    # Parse a specific sheet from the Excel file
    # @param file_path [String] Path to the Excel file
    # @param sheet_name [String] Name of the sheet to parse
    # @return [Array<Entity>] Parsed entities from the sheet
    def parse_sheet(file_path, sheet_name)
      parser = Parser.new(file_path)
      parser.parse_sheet(sheet_name)
    end

    # Export all sanction lists to YAML files
    # @param file_path [String] Path to the Excel file
    # @param output_dir [String] Directory to write YAML files
    # @param date_str [String] Date string for file naming (YYYYMMDD)
    def export_to_yaml(file_path, output_dir, date_str)
      parser = Parser.new(file_path)
      parser.export_to_yaml(output_dir, date_str)
    end

    # Get sheet metadata from an Excel file
    # @param file_path [String] Path to the Excel file
    # @return [Hash] Metadata about all sheets
    def sheet_metadata(file_path)
      parser = Parser.new(file_path)
      parser.parse_all # Parse to collect metadata
      parser.sheets_metadata
    end
  end
end
