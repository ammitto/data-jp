# frozen_string_literal: true

require "roo"
require "yaml"
require "fileutils"
require_relative "field_mapping"
require_relative "entity"

module MofSanctions
  # Parser for MOF Japan sanctions Excel files
  # Outputs YAML files conforming to jp-announcement.yml schema
  class Parser
    SKIP_SHEETS = ["一覧"].freeze
    REPEALED_PATTERN = /【.*廃止.*】|解除/

    # Sanction list directory mapping from sheet name to index + slug
    # Format: "sheet_name" => { index: NN, slug: "name", id: "canonical-id" }
    SANCTION_LIST_CONFIG = {
      "1.ミロシェビッチ前ユーゴ大統領関係者" => { index: 1, slug: "milosevic", id: "jp/mof-asset-freeze-milosevic" },
      "2.タリバーン関係者等" => { index: 2, slug: "taliban", id: "jp/mof-asset-freeze-taliban" },
      "3.テロリスト等 (1)" => { index: 3, slug: "terrorists-g7", id: "jp/mof-asset-freeze-terrorists-g7" },
      "4.テロリスト等 (2)" => { index: 4, slug: "terrorists-us", id: "jp/mof-asset-freeze-terrorists-us" },
      "5.イラク前政権関係者等（Ⅰ）" => { index: 5, slug: "iraq-1", id: "jp/mof-asset-freeze-iraq-1" },
      "6.イラク前政権関係者等 (Ⅱ)" => { index: 6, slug: "iraq-2", id: "jp/mof-asset-freeze-iraq-2" },
      "7.イラク前政権関係者等 (Ⅲ)" => { index: 7, slug: "iraq-3", id: "jp/mof-asset-freeze-iraq-3" },
      "9.コンゴ民主共和国（個人）" => { index: 9, slug: "drc-individuals", id: "jp/mof-asset-freeze-drc-individuals" },
      "10.コンゴ民主共和国 (団体)" => { index: 10, slug: "drc-organizations", id: "jp/mof-asset-freeze-drc-organizations" },
      "12.スーダン" => { index: 12, slug: "sudan", id: "jp/mof-asset-freeze-sudan" },
      "13.北朝鮮(決議1695号)" => { index: 13, slug: "dprk-1695", id: "jp/mof-asset-freeze-dprk-1695" },
      "14.北朝鮮(決議1718号等；団体)" => { index: 14, slug: "dprk-un-organizations", id: "jp/mof-asset-freeze-dprk-un-organizations" },
      "15.北朝鮮(決議1718号等；個人)" => { index: 15, slug: "dprk-un-individuals", id: "jp/mof-asset-freeze-dprk-un-individuals" },
      "16.北朝鮮(協調；団体)" => { index: 16, slug: "dprk-coord-organizations", id: "jp/mof-asset-freeze-dprk-coord-organizations" },
      "17.北朝鮮(協調；個人)" => { index: 17, slug: "dprk-coord-individuals", id: "jp/mof-asset-freeze-dprk-coord-individuals" },
      "19.イラン（個人）" => { index: 19, slug: "iran-individuals", id: "jp/mof-asset-freeze-iran-individuals" },
      "20.イラン (団体)" => { index: 20, slug: "iran-organizations", id: "jp/mof-asset-freeze-iran-organizations" },
      "21.ソマリア" => { index: 21, slug: "somalia", id: "jp/mof-asset-freeze-somalia" },
      "22.リビア(Ⅰ)" => { index: 22, slug: "libya-1", id: "jp/mof-asset-freeze-libya-1" },
      "23.リビア (Ⅱ)" => { index: 23, slug: "libya-2", id: "jp/mof-asset-freeze-libya-2" },
      "24.シリア（個人）" => { index: 24, slug: "syria-individuals", id: "jp/mof-asset-freeze-syria-individuals" },
      "25.シリア（団体）" => { index: 25, slug: "syria-organizations", id: "jp/mof-asset-freeze-syria-organizations" },
      "26.クリミア等（個人）" => { index: 26, slug: "crimea-individuals", id: "jp/mof-asset-freeze-crimea-individuals" },
      "27.クリミア等 (団体)" => { index: 27, slug: "crimea-organizations", id: "jp/mof-asset-freeze-crimea-organizations" },
      "28.ロシア連邦(団体(特定銀行を除く))" => { index: 28, slug: "russia-organizations", id: "jp/mof-asset-freeze-russia-organizations" },
      "29.ロシア連邦(個人)" => { index: 29, slug: "russia-individuals", id: "jp/mof-asset-freeze-russia-individuals" },
      "30.ロシア連邦(特定銀行）" => { index: 30, slug: "russia-banks", id: "jp/mof-asset-freeze-russia-banks" },
      "31.ベラルーシ(個人)" => { index: 31, slug: "belarus-individuals", id: "jp/mof-asset-freeze-belarus-individuals" },
      "32.ベラルーシ(団体(特定銀行を除く))" => { index: 32, slug: "belarus-organizations", id: "jp/mof-asset-freeze-belarus-organizations" },
      "33.ベラルーシ(特定銀行)" => { index: 33, slug: "belarus-banks", id: "jp/mof-asset-freeze-belarus-banks" },
      "34.ロシア及びベラルーシ以外（団体(特定銀行を除く)）" => { index: 34, slug: "other-organizations", id: "jp/mof-asset-freeze-other-organizations" },
      "35.ロシア及びベラルーシ以外（個人）" => { index: 35, slug: "other-individuals", id: "jp/mof-asset-freeze-other-individuals" },
      "36.ロシア及びベラルーシ以外（特定銀行)" => { index: 36, slug: "other-banks", id: "jp/mof-asset-freeze-other-banks" },
      "37.中央アフリカ共和国（個人）" => { index: 37, slug: "car-individuals", id: "jp/mof-asset-freeze-car-individuals" },
      "38.中央アフリカ共和国（団体）" => { index: 38, slug: "car-organizations", id: "jp/mof-asset-freeze-car-organizations" },
      "39.イエメン共和国" => { index: 39, slug: "yemen", id: "jp/mof-asset-freeze-yemen" },
      "40.南スーダン" => { index: 40, slug: "south-sudan", id: "jp/mof-asset-freeze-south-sudan" },
      "41.マリ共和国" => { index: 41, slug: "mali", id: "jp/mof-asset-freeze-mali" },
      "42.ハイチ共和国（個人）" => { index: 42, slug: "haiti-individuals", id: "jp/mof-asset-freeze-haiti-individuals" },
      "43.イスラエル" => { index: 43, slug: "israel-settlers", id: "jp/mof-asset-freeze-israel-settlers" },
      "44.ハイチ共和国（団体）" => { index: 44, slug: "haiti-organizations", id: "jp/mof-asset-freeze-haiti-organizations" }
    }.freeze

    # Legacy mapping for backwards compatibility
    SANCTION_LIST_IDS = SANCTION_LIST_CONFIG.transform_values { |v| v[:id] }.freeze

    # English names for sanction lists (comprehensive mapping)
    SANCTION_LIST_NAMES_EN = {
      "jp/mof-asset-freeze-milosevic" => "Associates of Former Yugoslav President Milosevic",
      "jp/mof-asset-freeze-taliban" => "Taliban, Al-Qaeda and ISIL (Daesh) Associates",
      "jp/mof-asset-freeze-terrorists-g7" => "Terrorists (G7 Coordinated)",
      "jp/mof-asset-freeze-terrorists-us" => "Terrorists (US Designated)",
      "jp/mof-asset-freeze-iraq-1" => "Former Iraqi Regime Officials (I)",
      "jp/mof-asset-freeze-iraq-2" => "Former Iraqi Regime Officials (II)",
      "jp/mof-asset-freeze-iraq-3" => "Former Iraqi Regime Officials (III)",
      "jp/mof-asset-freeze-drc-individuals" => "Democratic Republic of the Congo (Individuals)",
      "jp/mof-asset-freeze-drc-organizations" => "Democratic Republic of the Congo (Entities)",
      "jp/mof-asset-freeze-sudan" => "Sudan",
      "jp/mof-asset-freeze-dprk-1695" => "DPRK (Resolution 1695)",
      "jp/mof-asset-freeze-dprk-un-organizations" => "DPRK (Resolution 1718 - Entities)",
      "jp/mof-asset-freeze-dprk-un-individuals" => "DPRK (Resolution 1718 - Individuals)",
      "jp/mof-asset-freeze-dprk-coord-organizations" => "DPRK (Coordinated - Entities)",
      "jp/mof-asset-freeze-dprk-coord-individuals" => "DPRK (Coordinated - Individuals)",
      "jp/mof-asset-freeze-iran-individuals" => "Iran (Individuals)",
      "jp/mof-asset-freeze-iran-organizations" => "Iran (Entities)",
      "jp/mof-asset-freeze-somalia" => "Somalia",
      "jp/mof-asset-freeze-libya-1" => "Libya (I)",
      "jp/mof-asset-freeze-libya-2" => "Libya (II)",
      "jp/mof-asset-freeze-syria-individuals" => "Syria (Individuals)",
      "jp/mof-asset-freeze-syria-organizations" => "Syria (Entities)",
      "jp/mof-asset-freeze-crimea-individuals" => "Crimea and Sevastopol (Individuals)",
      "jp/mof-asset-freeze-crimea-organizations" => "Crimea and Sevastopol (Entities)",
      "jp/mof-asset-freeze-russia-organizations" => "Russian Federation (Entities excl. Banks)",
      "jp/mof-asset-freeze-russia-individuals" => "Russian Federation (Individuals)",
      "jp/mof-asset-freeze-russia-banks" => "Russian Federation (Designated Banks)",
      "jp/mof-asset-freeze-belarus-individuals" => "Belarus (Individuals)",
      "jp/mof-asset-freeze-belarus-organizations" => "Belarus (Entities excl. Banks)",
      "jp/mof-asset-freeze-belarus-banks" => "Belarus (Designated Banks)",
      "jp/mof-asset-freeze-other-organizations" => "Other Countries (Entities excl. Banks)",
      "jp/mof-asset-freeze-other-individuals" => "Other Countries (Individuals)",
      "jp/mof-asset-freeze-other-banks" => "Other Countries (Designated Banks)",
      "jp/mof-asset-freeze-car-individuals" => "Central African Republic (Individuals)",
      "jp/mof-asset-freeze-car-organizations" => "Central African Republic (Entities)",
      "jp/mof-asset-freeze-yemen" => "Republic of Yemen",
      "jp/mof-asset-freeze-south-sudan" => "South Sudan",
      "jp/mof-asset-freeze-mali" => "Republic of Mali",
      "jp/mof-asset-freeze-haiti-individuals" => "Republic of Haiti (Individuals)",
      "jp/mof-asset-freeze-israel-settlers" => "Israel (Settlers)",
      "jp/mof-asset-freeze-haiti-organizations" => "Republic of Haiti (Entities)"
    }.freeze

    attr_reader :xlsx, :sheets_data, :source_file

    def initialize(file_path)
      @xlsx = Roo::Spreadsheet.open(file_path)
      @sheets_data = {}
      @source_file = File.basename(file_path)
      @entity_counter = 0
    end

    # Parse all sheets and return entities grouped by sanction list
    def parse_all(include_repealed: false)
      result = {}

      @xlsx.sheets.each do |sheet_name|
        next if should_skip_sheet?(sheet_name, include_repealed)

        entities = parse_sheet(sheet_name)
        next if entities.empty?

        list_id = SANCTION_LIST_IDS[sheet_name.strip] || "jp/mof-asset-freeze-unknown"
        result[list_id] ||= { sheet_name: sheet_name, entities: [] }
        result[list_id][:entities].concat(entities)
      end

      result
    end

    # Parse a specific sheet
    def parse_sheet(sheet_name)
      @xlsx.sheet(sheet_name)

      first_row = @xlsx.first_row
      last_row = @xlsx.last_row
      first_col = @xlsx.first_column
      last_col = @xlsx.last_column

      return [] unless first_row && last_row && first_row < last_row

      header_row = find_header_row(first_row, last_row, first_col)
      headers = extract_headers(header_row, first_col, last_col)

      entity_type = FieldMapping.determine_entity_type(sheet_name)
      list_id = SANCTION_LIST_IDS[sheet_name.strip] || "jp/mof-asset-freeze-unknown"

      @sheets_data[sheet_name] = {
        headers: headers.compact,
        header_row: header_row,
        data_rows: last_row - header_row,
        entity_type: entity_type
      }

      entities = []
      (header_row + 1).upto(last_row).each do |row|
        entity = parse_row(row, headers, entity_type, list_id, sheet_name, first_col)
        entities << entity if entity
      end

      entities
    end

    # Export all sanction lists to YAML files
    def export_to_yaml(output_dir, date_str)
      FileUtils.mkdir_p(output_dir)

      data = parse_all(include_repealed: false)

      data.each do |list_id, info|
        sheet_name = info[:sheet_name]
        entities = info[:entities]

        next if entities.empty?

        # Get config for this sheet (strip trailing whitespace)
        clean_sheet_name = sheet_name.strip
        config = SANCTION_LIST_CONFIG[clean_sheet_name]

        if config
          # New structure: output_dir/33-belarus-banks/20260306.yml
          dir_name = "#{config[:index].to_s.rjust(2, '0')}-#{config[:slug]}"
          list_dir = File.join(output_dir, dir_name)
          FileUtils.mkdir_p(list_dir)
          yaml_path = File.join(list_dir, "#{date_str}.yml")
        else
          # Fallback for unknown sheets
          filename = list_id.gsub("jp/mof-asset-freeze-", "").gsub("-", "_")
          yaml_path = File.join(output_dir, "#{date_str}_#{filename}.yml")
        end

        # Build YAML structure
        yaml_data = build_yaml_structure(list_id, sheet_name, entities, date_str)

        # Write YAML file
        File.write(yaml_path, generate_yaml(yaml_path, yaml_data))
        puts "Written: #{yaml_path} (#{entities.size} entities)"
      end
    end

    private

    def should_skip_sheet?(sheet_name, include_repealed)
      return true if SKIP_SHEETS.include?(sheet_name)
      return true if !include_repealed && sheet_name.match?(REPEALED_PATTERN)
      false
    end

    def find_header_row(first_row, last_row, first_col)
      first_row.upto([first_row + 5, last_row].min) do |row|
        val = @xlsx.cell(row, first_col).to_s
        clean_val = val.gsub(/<[^>]+>/, "").gsub(/[\s\u3000]/, "")
        return row if clean_val.include?("告示日付")
      end
      first_row + 1
    end

    def extract_headers(header_row, first_col, last_col)
      headers = []
      first_col.upto(last_col).each do |col|
        val = @xlsx.cell(header_row, col).to_s
        val = val.gsub(/<[^>]+>/, "").gsub(/[\s\u3000]+/, " ").strip
        headers << (val.empty? ? nil : val)
      end
      headers
    end

    def parse_row(row, headers, entity_type, list_id, sheet_name, first_col)
      # For unknown entity types, we'll determine after parsing the row
      # based on presence of individual-specific fields (date_of_birth)
      entity = Entity.new(
        type: entity_type == :organization ? "organization" : "individual",
        sanction_list: list_id,
        sanction_list_en: SANCTION_LIST_NAMES_EN[list_id]
      )

      has_data = false
      gazette_date = nil
      gazette_number = nil
      has_individual_fields = false

      headers.each_with_index do |header, col_idx|
        next if header.nil?

        col = first_col + col_idx
        value = @xlsx.cell(row, col)
        next if value.nil?

        value_str = clean_value(value)
        next if value_str.empty?

        has_data = true

        # Check for individual-specific fields
        has_individual_fields = true if header.include?("生年月日")

        # Apply field mapping
        result = apply_field_mapping(entity, header, value_str, sheet_name)
        if result.is_a?(Hash)
          gazette_date ||= result[:date]
          gazette_number ||= result[:number]
        elsif result.is_a?(String)
          gazette_date ||= result
        end
      end

      return nil unless has_data && (entity.name["ja"] || entity.name["en"])

      # Determine entity type for unknown sheets based on row content
      if entity_type == :unknown
        entity.type = has_individual_fields ? "individual" : "organization"
      end

      # Set effective_date from gazette_date
      entity.effective_date = parse_date(gazette_date) if gazette_date

      # Generate entity ID: jp.mof.{list-slug}.{number}
      list_slug = list_id.gsub("jp/mof-asset-freeze-", "")
      # Strip asterisks and parentheses from gazette_number if present
      entity_number = (gazette_number || (@entity_counter + 1).to_s)
        .gsub(/[*()（）]/, "")
      @entity_counter += 1
      entity.id = "jp.mof.#{list_slug}.#{entity_number}"

      # Add default measure (asset freeze)
      entity.add_measure(
        types: ["asset_freeze"],
        ja: "資産凍結の対象",
        en: "Subject to asset freeze"
      )

      entity
    end

    def clean_value(value)
      value.to_s.strip.gsub(/[\r\n]+/, " ").gsub(/\s+/, " ")
    end

    # Apply field mapping using the configurable mapping system
    # Returns nil, or a hash with gazette_date/gazette_number
    def apply_field_mapping(entity, header, value, sheet_name)
      # Get mapping configuration for this column
      mapping = FieldMapping.get_mapping(sheet_name, header)

      if mapping
        # Apply the configured mapping
        result = FieldMapping.apply_mapping(entity, mapping, value, self)

        # Handle gazette date/number returns
        if result.is_a?(Hash)
          if result[:gazette_date]
            return { date: result[:gazette_date], number: nil }
          elsif result[:gazette_number]
            return { date: nil, number: result[:gazette_number] }
          end
        end
        return nil
      end

      # Fallback for unmapped fields - add to reason with header name
      # But skip fields that look like metadata or are empty
      unless value == "不明" || value.to_s.strip.empty?
        entity.add_reason(ja: "#{header}: #{value}")
      end
      nil
    end

    def parse_date(date_str)
      return nil if date_str.nil?

      # Try to extract first date from string like "2022.3.1 2008.6.25改訂"
      match = date_str.match(/(\d{4})[\.\-\/](\d{1,2})[\.\-\/](\d{1,2})/)
      return nil unless match

      year = match[1]
      month = match[2].rjust(2, "0")
      day = match[3].rjust(2, "0")

      "#{year}-#{month}-#{day}"
    end

    # Parse date_of_birth field - handles Excel serial dates and Japanese formats
    def parse_date_of_birth(value)
      return nil if value.nil? || value.to_s.strip.empty? || value == "不明"

      str = value.to_s.strip

      # Check if it's a pure number (Excel serial date)
      if str.match?(/^\d+$/)
        return excel_serial_to_date(str.to_i)
      end

      # Check for Japanese year format: 1953年 or 1953年頃
      if str.match?(/^(\d{4})年/)
        match = str.match(/^(\d{4})年/)
        return "#{match[1]}-XX-XX"
      end

      # Try to parse standard date formats
      # Format: YYYY年MM月DD日
      if str.match?(/(\d{4})年(\d{1,2})月(\d{1,2})日/)
        match = str.match(/(\d{4})年(\d{1,2})月(\d{1,2})日/)
        year = match[1]
        month = match[2].rjust(2, "0")
        day = match[3].rjust(2, "0")
        return "#{year}-#{month}-#{day}"
      end

      # Format: YYYY.MM.DD or YYYY-MM-DD or YYYY/MM/DD
      match = str.match(/(\d{4})[\.\-\/](\d{1,2})[\.\-\/](\d{1,2})/)
      if match
        year = match[1]
        month = match[2].rjust(2, "0")
        day = match[3].rjust(2, "0")
        return "#{year}-#{month}-#{day}"
      end

      # Return original value if no pattern matches
      str
    end

    # Convert Excel serial date number to YYYY-MM-DD format
    # Excel uses 1900-01-01 as day 1 (with a bug treating 1900 as leap year)
    def excel_serial_to_date(serial)
      return nil if serial.nil? || serial <= 0

      # Excel epoch is December 30, 1899 (to account for the 1900 leap year bug)
      # For dates after March 1, 1900, we need to subtract 1 from the serial
      excel_epoch = Date.new(1899, 12, 30)

      begin
        date = excel_epoch + serial
        date.strftime("%Y-%m-%d")
      rescue
        serial.to_s
      end
    end

    # Parse list_date and un_designation_date - handles Excel serial dates
    def parse_list_date(value)
      return nil if value.nil? || value.to_s.strip.empty?

      str = value.to_s.strip

      # Check if it's a pure number (Excel serial date)
      if str.match?(/^\d+$/)
        return excel_serial_to_date(str.to_i)
      end

      # Try standard date formats
      parse_date(str) || str
    end

    def build_yaml_structure(list_id, sheet_name, entities, date_str)
      {
        "announcement" => {
          "title" => [
            { "ja" => sheet_name.gsub(/^[0-9]+\.\s*/, "") },
            { "en" => SANCTION_LIST_NAMES_EN[list_id] || list_id.split("/").last }
          ].compact,
          "url" => "https://www.mof.go.jp/policy/international_policy/gaitame_kawase/gaitame/economic_sanctions/list.html",
          "publish_date" => parse_file_date(date_str),
          "authority" => "jp/mof",
          "publisher" => "jp/mof",
          "type" => "jp/asset-freeze-announcement",
          "source_file" => @source_file,
          "source_url" => "https://www.mof.go.jp/policy/international_policy/gaitame_kawase/gaitame/economic_sanctions/#{@source_file}"
        },
        "sanction_details" => {
          "instruments" => [
            { "id" => "jp/diet-foreign-exchange-and-foreign-trade-act" },
            { "id" => "jp/cabinet-order-foreign-exchange" }
          ],
          "entities" => entities.map(&:to_h)
        }
      }
    end

    def parse_file_date(date_str)
      "#{date_str[0..3]}-#{date_str[4..5]}-#{date_str[6..7]}"
    end

    def generate_yaml(yaml_path, data)
      # Calculate relative path to schema based on file depth
      depth = yaml_path.split("/").length - yaml_path.split("/").index { |p| p == "sanction-lists" }.to_i - 2
      schema_path = "#{"../" * depth}schemas/jp-announcement.yml"
      header = "# yaml-language-server: $schema=#{schema_path}\n---\n"
      header + data.to_yaml(line_width: -1).gsub(/^---\n/, "")
    end
  end
end
