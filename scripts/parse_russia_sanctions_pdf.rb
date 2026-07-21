#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to parse METI Russia sanctions PDFs and extract sanctioned entities
#
# Semantic Structure:
# - Three separate sanction lists (Russia, Belarus, Third-country)
# - Each list has a base list (list_*_tokutei.pdf) and incremental updates
# - Titles are extracted from PDF content
# - Authority is MOFA (外務省), not METI
#
# Rules:
# 1. Each entry starts with a number, content until the next number or EOF belongs to it
# 2. Japanese alias pattern: （別称、{alias}、... 及び {alias}）
#    English alias pattern: , a.k.a., ... followed by lines starting with - ending with ;
# 3. If no alias: Japanese name = after number until newline before first English line
# 4. Address = line starting with 所在地： until END OF CONTENT (next entry or EOF)
# 5. Always fully parse and remove delimiters like semicolons
# 6. Assign unique entity IDs
# 7. Normalize spaces (full-width to ASCII)

require 'pdf-reader'
require 'yaml'
require 'fileutils'
require 'date'

class RussiaSanctionsPdfParser
  INPUT_DIR = 'reference-docs/russia-sanctions'
  BASE_OUTPUT_DIR = 'sources/sanction-lists'
  METADATA_FILE = 'reference-docs/russia-sanctions/metadata.yml'

  ERA_YEARS = {
    '令和' => 2018,
    '平成' => 1988,
    '昭和' => 1925
  }.freeze

  # Sanction list type detection patterns (from PDF text, not filename)
  LIST_PATTERNS = {
    russia: /ロシア連邦の(特定)?団体/,
    belarus: /ベラルーシ共和国の(特定)?団体/,
    third_country: /ロシア連邦及びベラルーシ共和国以外の国の(特定)?団体/
  }.freeze

  # Base list filenames (contain full official title with announcement number)
  BASE_LIST_FILES = %w[
    list_russia_tokutei.pdf
    list_belarus_tokutei.pdf
    list_daisangoku_tokutei.pdf
  ].freeze

  # List configuration
  LIST_CONFIG = {
    russia: {
      dir: 'russia-export-prohibition',
      id_prefix: 'jp.mofa.russia',
      sanction_list: 'jp/mofa-russia-export-prohibition-list',
      sanction_list_en: 'Japan Russia Export Prohibition List',
      default_country_code: 'RU',
      default_country_name: { 'ja' => 'ロシア連邦', 'en' => 'Russian Federation' }
    },
    belarus: {
      dir: 'belarus-export-prohibition',
      id_prefix: 'jp.mofa.belarus',
      sanction_list: 'jp/belarus-export-prohibition-list',
      sanction_list_en: 'Japan Belarus Export Prohibition List',
      default_country_code: 'BY',
      default_country_name: { 'ja' => 'ベラルーシ共和国', 'en' => 'Republic of Belarus' }
    },
    third_country: {
      dir: 'third-country-export-prohibition',
      id_prefix: 'jp.mofa.third-country',
      sanction_list: 'jp/third-country-export-prohibition-list',
      sanction_list_en: 'Japan Third-Country Export Prohibition List',
      default_country_code: nil,
      default_country_name: nil
    }
  }.freeze

  # Country name to ISO 3166-1 alpha-2 code mapping for address detection
  COUNTRY_CODE_MAP = {
    # Common countries in sanctions lists
    'Armenia' => 'AM',
    'Syria' => 'SY',
    'United Arab Emirates' => 'AE',
    'UAE' => 'AE',
    'Dubai' => 'AE',
    'China' => 'CN',
    'Hong Kong' => 'HK',
    'Hong Kong, China' => 'HK',
    'Uzbekistan' => 'UZ',
    'India' => 'IN',
    'Turkey' => 'TR',
    'Türkiye' => 'TR',
    'Singapore' => 'SG',
    'Malaysia' => 'MY',
    'Thailand' => 'TH',
    'Vietnam' => 'VN',
    'Viet Nam' => 'VN',
    'Indonesia' => 'ID',
    'Philippines' => 'PH',
    'Pakistan' => 'PK',
    'Iran' => 'IR',
    'North Korea' => 'KP',
    "Democratic People's Republic of Korea" => 'KP',
    'Myanmar' => 'MM',
    'Cambodia' => 'KH',
    'Sri Lanka' => 'LK',
    'Bangladesh' => 'BD',
    'Nepal' => 'NP',
    'Georgia' => 'GE',
    'Kazakhstan' => 'KZ',
    'Kyrgyzstan' => 'KG',
    'Tajikistan' => 'TJ',
    'Turkmenistan' => 'TM',
    'Azerbaijan' => 'AZ',
    'Moldova' => 'MD',
    'Serbia' => 'RS',
    'Belarus' => 'BY',
    'Russia' => 'RU',
    'Ukraine' => 'UA',
    'Israel' => 'IL',
    'Egypt' => 'EG',
    'South Africa' => 'ZA',
    'Nigeria' => 'NG',
    'Kenya' => 'KE',
    'Morocco' => 'MA',
    'Algeria' => 'DZ',
    'Tunisia' => 'TN',
    'Libya' => 'LY',
    'Sudan' => 'SD',
    'Ethiopia' => 'ET',
    'Somalia' => 'SO',
    'Yemen' => 'YE',
    'Iraq' => 'IQ',
    'Jordan' => 'JO',
    'Lebanon' => 'LB',
    'Saudi Arabia' => 'SA',
    'Kuwait' => 'KW',
    'Qatar' => 'QA',
    'Bahrain' => 'BH',
    'Oman' => 'OM',
    'Afghanistan' => 'AF',
    'Panama' => 'PA',
    'Cayman Islands' => 'KY',
    'British Virgin Islands' => 'VG',
    'Virgin Islands' => 'VG',
    'Cyprus' => 'CY',
    'Malta' => 'MT',
    'Luxembourg' => 'LU',
    'Switzerland' => 'CH',
    'United Kingdom' => 'GB',
    'UK' => 'GB',
    'United States' => 'US',
    'USA' => 'US',
    'Canada' => 'CA',
    'Australia' => 'AU',
    'New Zealand' => 'NZ',
    'Japan' => 'JP',
    'South Korea' => 'KR',
    'Republic of Korea' => 'KR',
    'Korea' => 'KR',
    'Taiwan' => 'TW',
    'Macao' => 'MO',
    'Macau' => 'MO'
  }.freeze

  def initialize
    @processed_files = []
    @metadata = load_metadata
    @entity_id_counters = Hash.new(0)
  end

  def load_metadata
    return {} unless File.exist?(METADATA_FILE)
    YAML.load_file(METADATA_FILE) || {}
  rescue => e
    puts "Warning: Could not load metadata: #{e.message}"
    {}
  end

  def parse_all
    pdf_files = Dir.glob(File.join(INPUT_DIR, '*.pdf'))
    puts "Found #{pdf_files.size} PDF files to parse"

    # Process base lists first
    base_files = pdf_files.select { |f| BASE_LIST_FILES.include?(File.basename(f)) }
    incremental_files = pdf_files.reject { |f| BASE_LIST_FILES.include?(File.basename(f)) }

    puts "\n=== Processing Base Lists ==="
    base_files.each { |pdf_path| parse_pdf(pdf_path, is_base: true) }

    puts "\n=== Processing Incremental Updates ==="
    incremental_files.sort_by { |f| extract_date(File.basename(f), '') }
                     .each { |pdf_path| parse_pdf(pdf_path, is_base: false) }

    puts "\nProcessed #{@processed_files.size} files"
    @processed_files
  end

  def parse_pdf(pdf_path, is_base: false)
    filename = File.basename(pdf_path)
    puts "\nParsing: #{filename}"

    begin
      reader = PDF::Reader.new(pdf_path)
      full_text = reader.pages.map(&:text).join("\n")

      # Extract title from PDF content
      title_ja = extract_title(full_text)
      puts "  Title: #{title_ja[0..60]}..."

      # Determine list type from PDF content (not filename)
      list_type = detect_list_type(full_text)
      puts "  List type: #{list_type}"

      publish_date = extract_date(filename, full_text)
      puts "  Date extracted: #{publish_date}"

      config = LIST_CONFIG[list_type]

      # Extract entities with entry numbers for ID assignment
      entities = extract_entities(full_text, list_type)

      if entities.empty?
        puts "  No entities found, skipping"
        return
      end

      puts "  Entities found: #{entities.size}"

      # Generate output in appropriate folder
      output_dir = File.join(BASE_OUTPUT_DIR, config[:dir])
      FileUtils.mkdir_p(output_dir)

      if is_base
        generate_base_yaml(entities, publish_date, filename, title_ja, list_type, output_dir, config)
      else
        generate_incremental_yaml(entities, publish_date, filename, title_ja, list_type, output_dir, config)
      end

      @processed_files << pdf_path

    rescue => e
      puts "  Error: #{e.message}"
      puts e.backtrace.first(3).join("\n")
    end
  end

  private

  def extract_title(text)
    # Extract the Japanese title from PDF content
    # Titles span multiple lines and end with 告示第XXX号)

    # Remove all line breaks to handle titles split across lines
    normalized = text.gsub(/\s+/, ' ').strip

    # Pattern 1: Full title with MOFA announcement number (base lists)
    # Look for pattern: ○ ... 外務省告示...号）
    match = normalized.match(/((○\s*.*?)外務省告示[^)）]*[)）])/)

    if match
      title = match[1]
      # Remove "○ " prefix
      title = title.sub(/^[○\s]+/, '').strip
      # Remove spaces between Japanese characters (artifact from PDF line breaks)
      return remove_spaces_between_japanese(title)
    end

    # Pattern 2: Incremental update titles (特定団体 or 団体 without announcement number)
    # Match titles ending with either 特定団体 or just 団体
    match = normalized.match(/(輸出等に係る禁止措置の対象となる[^""]*(?:特定)?団体)/)

    if match
      # Remove spaces between Japanese characters (artifact from PDF line breaks)
      return remove_spaces_between_japanese(match[1].strip)
    end

    # Fallback: Find lines containing 団体
    lines = text.split("\n").map(&:strip)
    title_lines = lines.select do |line|
      line.match?(/団体|措置/) && line.length > 10 && !line.match?(/^\d/)
    end

    title = title_lines.first(4).join
    title = title.sub(/^[○\s]+/, '').strip
    remove_spaces_between_japanese(title)
  end

  def remove_spaces_between_japanese(text)
    # Remove spaces that are between Japanese characters
    # Japanese characters: Hiragana, Katakana, Han (Kanji)
    text.gsub(/([一-龯ぁ-んァ-ン])\s+(?=[一-龯ぁ-んァ-ン])/, '\1')
  end

  def detect_list_type(text)
    # Normalize text - remove line breaks for pattern matching
    normalized_text = text.gsub(/\s+/, '')

    # Detect based on content patterns - check most specific first
    # Third-country must be checked before russia/belarus since it contains both terms
    if normalized_text.include?('ロシア連邦及びベラルーシ共和国以外の国の団体') ||
       normalized_text.include?('ロシア連邦及びベラルーシ共和国以外の国の特定団体')
      :third_country
    elsif normalized_text.include?('ベラルーシ共和国の団体') ||
          normalized_text.include?('ベラルーシ共和国の特定団体')
      :belarus
    elsif normalized_text.include?('ロシア連邦の団体') ||
          normalized_text.include?('ロシア連邦の特定団体')
      :russia
    else
      # Fallback to metadata
      :russia
    end
  end

  def extract_date(filename, text)
    # Try metadata first
    date = @metadata&.dig(filename, 'date')
    return date if date && !date.empty?

    # Try filename pattern YYYYMMDD
    match = filename.match(/(\d{4})(\d{2})(\d{2})/)
    if match
      year, month, day = match[1..3].map(&:to_i)
      return format('%04d-%02d-%02d', year, month, day) if valid_date?(year, month, day)
    end

    # Try Japanese era date in content
    match = text.match(/(令和|平成|昭和)(\d+)年(\d+)月(\d+)日/)
    if match
      era, era_year, month, day = match[1], match[2].to_i, match[3].to_i, match[4].to_i
      western_year = ERA_YEARS[era] + era_year
      return format('%04d-%02d-%02d', western_year, month, day)
    end

    Date.today.to_s
  end

  def valid_date?(year, month, day)
    year >= 2020 && month.between?(1, 12) && day.between?(1, 31)
  end

  def normalize_spaces(text)
    return nil if text.nil?
    # Replace full-width spaces with regular spaces, then collapse multiple spaces
    text.gsub(/[　\s]+/, ' ').strip
  end

  def extract_entities(text, list_type)
    entities = []
    lines = text.split("\n")

    # Step 1: Group lines into entry blocks (each starts with a number)
    entry_blocks = []
    current_block = []

    lines.each do |line|
      stripped = line.strip

      # New entry starts with a number (1-3 digits, not postal codes)
      if stripped.match?(/^[０-９\d]+[\.\s　]+/) && !stripped.match?(/^\d{5,}/)
        entry_blocks << current_block if current_block.any?
        current_block = [line]
      elsif current_block.any?
        current_block << line
      end
    end
    entry_blocks << current_block if current_block.any?

    # Step 2: Parse each entry block
    entry_blocks.each do |block|
      entry_number = extract_entry_number(block.first)
      entity = parse_entry(block, entry_number, list_type)
      entities << entity if entity && entity[:name] && !entity[:name].empty?
    end

    entities.compact
  end

  def extract_entry_number(first_line)
    return nil unless first_line
    match = first_line.strip.match(/^([０-９\d]+)[\.\s　]+/)
    match ? normalize_number(match[1]) : nil
  end

  def normalize_number(num_str)
    # Convert full-width digits to ASCII
    num_str.tr('０-９', '0-9').to_i
  end

  def generate_entity_id(list_type, entry_number)
    config = LIST_CONFIG[list_type]
    "#{config[:id_prefix]}.#{entry_number}"
  end

  def parse_entry(lines, entry_number, list_type)
    config = LIST_CONFIG[list_type]

    # Step 1: Extract address (from 所在地： until end of content)
    address = extract_address(lines)
    address = normalize_spaces(address)

    # Step 2: Split remaining content into Japanese and English sections
    non_address_lines = remove_address_lines(lines)
    ja_lines, en_lines = split_japanese_english(non_address_lines)

    # Step 3: Parse Japanese section
    ja_name, ja_aliases = parse_japanese_section(ja_lines)

    # Step 4: Parse English section (with multi-line alias support)
    en_name, en_aliases = parse_english_section(en_lines)

    # Normalize all names and aliases
    ja_name = normalize_spaces(ja_name)
    en_name = normalize_spaces(en_name)
    ja_aliases = ja_aliases.map { |a| normalize_spaces(a) }.compact.reject(&:empty?)
    en_aliases = en_aliases.map { |a| normalize_spaces(a) }.compact.reject(&:empty?)

    # Build entity
    entity = {
      id: generate_entity_id(list_type, entry_number),
      entry_number: entry_number,
      name: {},
      type: 'organization'
    }

    entity[:name]['ja'] = ja_name if ja_name && !ja_name.empty?
    entity[:name]['en'] = en_name if en_name && !en_name.empty?
    entity[:address] = address if address && !address.empty?

    # Add country info for Russia and Belarus lists
    if config[:default_country_code]
      entity[:country_code] = config[:default_country_code]
      entity[:country_name] = config[:default_country_name]
    elsif address
      # Detect country from address for third-country entities
      country_code, country_name = detect_country_from_address(address)
      if country_code
        entity[:country_name] = detected_name
      end
    end

    # Combine aliases (language-specific)
    if ja_aliases.any? || en_aliases.any?
      entity[:aliases] = {}
      entity[:aliases]['ja'] = ja_aliases if ja_aliases.any?
      entity[:aliases]['en'] = en_aliases if en_aliases.any?
    end

    entity
  end

  def extract_address(lines)
    address_lines = []
    in_address = false

    lines.each do |line|
      stripped = line.strip

      if stripped.match?(/^所在(地)?[：:　\s]/)
        in_address = true
        address_content = stripped.sub(/^所在(地)?[：:　\s]+/, '')
        address_lines << address_content if address_content && !address_content.empty?
      elsif in_address
        if stripped.match?(/^[０-９]{1,3}[\.\s　]+[^\d]/) || stripped.match?(/^\d{1,3}[\.\s　]+[^\d\s]/)
          break
        end
        address_lines << stripped if stripped && !stripped.empty?
      end
    end

    return nil if address_lines.empty?
    address_lines.join(' ').strip
  end

  def remove_address_lines(lines)
    result = []
    in_address = false

    lines.each do |line|
      stripped = line.strip

      if stripped.match?(/^所在(地)?[：:　\s]/)
        in_address = true
        next
      elsif in_address
        if stripped.match?(/^[０-９]{1,3}[\.\s　]+[^\d]/) || stripped.match?(/^\d{1,3}[\.\s　]+[^\d\s]/)
          in_address = false
          result << line
        end
        next
      else
        result << line
      end
    end

    result
  end

  def split_japanese_english(lines)
    ja_lines = []
    en_lines = []
    first_line = true

    lines.each do |line|
      stripped = line.strip
      next if stripped.empty?

      if first_line
        stripped = stripped.sub(/^[０-９\d]+[\.\s　]+/, '')
        first_line = false
      end

      if stripped.match?(/[\p{Hiragana}\p{Katakana}\p{Han}]/)
        # Contains Japanese characters
        if en_lines.empty?
          ja_lines << stripped
        end
      elsif stripped.match?(/^[A-Za-z0-9\-—－""''`]/)
        # Starts with English letter, number, dash, or quote - treat as English
        en_lines << stripped
      end
    end

    [ja_lines, en_lines]
  end

  def parse_japanese_section(lines)
    return [nil, []] if lines.empty?

    # Join lines WITHOUT adding spaces - Japanese text flows across lines
    # The PDF splits text mid-word, so we need to join directly
    full_text = lines.join

    # Check for （別称 pattern, allowing optional whitespace between 別 and 称
    # PDF text may have spaces due to line breaks: （別    称
    betusho_match = full_text.match(/（別\s*称[、,､]?\s*/)
    if betusho_match
      return [full_text, []] unless betusho_match

      main_name = full_text[0...betusho_match.begin(0)].strip

      # Start position is right after （別称 and any delimiter
      start_pos = betusho_match.end(0)
      # Skip any whitespace
      start_pos += 1 while start_pos < full_text.length && full_text[start_pos] =~ /\s/

      # Find matching closing ） by counting balanced parens
      paren_depth = 1
      end_pos = start_pos
      balanced = false
      while end_pos < full_text.length && paren_depth > 0
        char = full_text[end_pos]
        if char == '（' || char == '('
          paren_depth += 1
        elsif char == '）' || char == ')'
          paren_depth -= 1
        end
        end_pos += 1
      end

      # Check if we exited due to balanced parens or end of string
      balanced = (paren_depth == 0)

      # Extract aliases text
      # If balanced, exclude the final closing paren
      # If not balanced (reached end of string), include everything
      aliases_text = balanced ? full_text[start_pos...end_pos - 1] : full_text[start_pos..-1]

      # Split by 及び first to handle the last alias
      parts = aliases_text.split(/及び/)
      all_aliases = []

      parts.each_with_index do |part, idx|
        if idx == parts.length - 1
          # Last part - just clean and add
          alias_text = part.strip
          # Remove leading commas (trailing parens are part of alias name)
          alias_text = alias_text.sub(/^[、,､\s]+/, '')
          all_aliases << alias_text unless alias_text.empty?
        else
          # Split by 、 (both full-width and half-width)
          subparts = part.split(/[、,､]/)
          subparts.each do |sp|
            alias_text = sp.strip
            # Remove leading commas (trailing parens are part of alias name)
            alias_text = alias_text.sub(/^[、,､\s]+/, '')
            all_aliases << alias_text unless alias_text.empty?
          end
        end
      end

      # Clean up aliases - remove empty ones and normalize spaces within
      aliases = all_aliases.map do |a|
        # Normalize internal spaces but preserve the alias
        normalize_spaces(a)
      end.reject(&:empty?)

      return [main_name, aliases]
    end

    # No aliases - return full text as name
    main_name = full_text.sub(/（[^）]*$/, '').strip
    main_name = main_name.sub(/（$/, '').strip
    [main_name, []]
  end

  def parse_english_section(lines)
    return [nil, []] if lines.empty?

    alias_lines = []
    name_lines = []
    current_alias = nil
    in_alias_section = false

    lines.each do |line|
      stripped = line.strip

      if stripped.match?(/^[—－-]/)
        # New alias starts with dash
        if current_alias && !current_alias.empty?
          alias_lines << current_alias
        end

        alias_text = stripped.sub(/^[—－-]\s*/, '')
        alias_text = alias_text.sub(/[;；]\s*(and)?\s*$/i, '')
        alias_text = alias_text.sub(/[.．]\s*$/, '')
        current_alias = alias_text.strip
        in_alias_section = true
      elsif in_alias_section && !stripped.empty? && !stripped.match?(/^[—－-]/)
        # Continuation line for current alias (could start with quote, letter, etc.)
        # But not a new alias (doesn't start with dash)
        # Join with space if current alias doesn't end with opening quote/bracket
        if current_alias
          if current_alias.match?(/[""「\[(]$/)
            current_alias = "#{current_alias}#{stripped}"
          else
            current_alias = "#{current_alias} #{stripped}"
          end
        end
      elsif !in_alias_section && !stripped.empty?
        name_lines << stripped
      end
    end

    # Don't forget the last alias
    if current_alias && !current_alias.empty?
      alias_lines << current_alias
    end

    # Clean up aliases - remove trailing delimiters
    clean_aliases = alias_lines.map do |a|
      a.sub(/[;；]\s*(and)?\s*$/i, '').sub(/[.．]\s*$/, '').strip
    end.reject(&:empty?)

    full_name = name_lines.join(' ').strip

    # Check for a.k.a. pattern in name
    if full_name.match?(/a\.?k\.?a\.?/i)
      match = full_name.match(/^(.+?),?\s*a\.?k\.?a\.?/i)
      if match
        main_name = match[1].strip
        return [main_name, clean_aliases]
      end
    end

    full_name = full_name.sub(/,?\s*the following \d+ aliases?:?\s*$/i, '')
    full_name = full_name.sub(/,?\s*the following \d+ alias:??\s*$/i, '')

    [full_name.empty? ? nil : full_name.strip, clean_aliases]
  end

  def generate_base_yaml(entities, publish_date, source_filename, title_ja, list_type, output_dir, config)
    # Base list goes to _index.yml
    output_path = File.join(output_dir, '_index.yml')

    output = {
      '#' => "yaml-language-server: \$schema=../../schemas/jp-sanction-list.yml",
      'sanction_list' => {
        'id' => config[:sanction_list],
        'name' => {
          'ja' => title_ja,
          'en' => config[:sanction_list_en]
        },
        'authority' => 'jp/mofa',
        'type' => 'jp/export-prohibition-list',
        'source_file' => source_filename,
        'source_url' => @metadata&.dig(source_filename, 'url') ||
          "https://www.meti.go.jp/policy/external_economy/trade_control/02_export/17_russia/#{source_filename}"
      },
      'entities' => entities.map do |e|
        build_entity_data(e, config[:sanction_list])
      end
    }

    File.write(output_path, generate_yaml_string(output))
    puts "  Generated base list: #{output_path}"
    puts "  Total entities: #{entities.size}"
  end

  def generate_incremental_yaml(entities, publish_date, source_filename, title_ja, list_type, output_dir, config)
    # Incremental update goes to date-based file
    output_filename = "#{publish_date}.yml"
    output_path = File.join(output_dir, output_filename)

    output = {
      '#' => "yaml-language-server: \$schema=../../schemas/jp-announcement.yml",
      'announcement' => {
        'title' => [
          { 'ja' => title_ja },
          { 'en' => config[:sanction_list_en].sub('Japan ', '').sub(' List', '') }
        ],
        'publish_date' => publish_date,
        'authority' => 'jp/mofa',
        'type' => 'jp/export-prohibition-announcement',
        'source_file' => source_filename,
        'source_url' => @metadata&.dig(source_filename, 'url') ||
          "https://www.mofa.go.jp/mofaj/files/#{source_filename}"
      },
      'entities' => entities.map do |e|
        build_entity_data(e, config[:sanction_list])
      end
    }

    File.write(output_path, generate_yaml_string(output))
    puts "  Generated: #{output_path}"
    puts "  Total entities: #{entities.size}"
  end

  def build_entity_data(entity, sanction_list)
    entity_data = {
      'id' => entity[:id],
      'entry_number' => entity[:entry_number],
      'name' => entity[:name],
      'type' => entity[:type] || 'organization',
      'sanction_list' => sanction_list,
      'measures' => [
        {
          'type' => ['prohibit_export_dual_use_items'],
          'ja' => '輸出等に係る禁止措置の対象',
          'en' => 'Subject to export prohibition measures'
        }
      ]
    }

    entity_data['country_code'] = entity[:country_code] if entity[:country_code]
    entity_data['country_name'] = entity[:country_name] if entity[:country_name]
    entity_data['address'] = entity[:address] if entity[:address]
    entity_data['aliases'] = entity[:aliases] if entity[:aliases] && entity[:aliases].any?

    entity_data
  end

  def generate_yaml_string(data)
    yaml = data.reject { |k| k == '#' }.to_yaml(line_width: -1)
    "# #{data['#']}\n#{yaml}"
  end
end

if __FILE__ == $PROGRAM_NAME
  parser = RussiaSanctionsPdfParser.new
  parser.parse_all
end
