#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to convert Japanese METI Foreign User List (外国ユーザーリスト) Excel to YAML
# Usage: ruby scripts/convert_foreign_user_list_to_yaml.rb [xlsx_path] [output_path]

require 'roo'
require 'yaml'
require 'fileutils'
require 'date'

class ForeignUserListConverter
  # WMD Type mappings (letter codes in Excel)
  WMD_TYPES = {
    'N' => { ja: '核兵器', en: 'Nuclear weapons' },
    'M' => { ja: 'ミサイル', en: 'Missiles' },
    'B' => { ja: '生物兵器', en: 'Biological weapons' },
    'C' => { ja: '化学兵器', en: 'Chemical weapons' },
    'CW' => { ja: '通常兵器', en: 'Conventional weapons' }
  }.freeze

  # ISO 3166-1 alpha-2 country code mappings
  COUNTRY_CODES = {
    'アフガニスタン' => 'AF',
    'アラブ首長国連邦' => 'AE',
    'アルジェリア' => 'DZ',
    'アルメニア' => 'AM',
    'アンゴラ' => 'AO',
    'アルゼンチン' => 'AR',
    'オーストリア' => 'AT',
    'アゼルバイジャン' => 'AZ',
    'バングラデシュ' => 'BD',
    'ベラルーシ' => 'BY',
    'ベルギー' => 'BE',
    'ボスニア・ヘルツェゴビナ' => 'BA',
    'ブラジル' => 'BR',
    'ブルガリア' => 'BG',
    'カンボジア' => 'KH',
    'カナダ' => 'CA',
    'チリ' => 'CL',
    '中国' => 'CN',
    'コロンビア' => 'CO',
    'クロアチア' => 'HR',
    'キプロス' => 'CY',
    'チェコ' => 'CZ',
    'デンマーク' => 'DK',
    'エジプト' => 'EG',
    'エストニア' => 'EE',
    'フィンランド' => 'FI',
    'フランス' => 'FR',
    'ジョージア' => 'GE',
    'ドイツ' => 'DE',
    'ギリシャ' => 'GR',
    '香港' => 'HK',
    'ハンガリー' => 'HU',
    'アイスランド' => 'IS',
    'インド' => 'IN',
    'インドネシア' => 'ID',
    'イラン' => 'IR',
    'イラク' => 'IQ',
    'アイルランド' => 'IE',
    'イスラエル' => 'IL',
    'イタリア' => 'IT',
    '日本' => 'JP',
    'ヨルダン' => 'JO',
    'カザフスタン' => 'KZ',
    'ケニア' => 'KE',
    '大韓民国' => 'KR',
    'クウェート' => 'KW',
    'キルギス' => 'KG',
    'ラトビア' => 'LV',
    'レバノン' => 'LB',
    'リビア' => 'LY',
    'リトアニア' => 'LT',
    'ルクセンブルク' => 'LU',
    'マケドニア' => 'MK',
    'マレーシア' => 'MY',
    'メキシコ' => 'MX',
    'モルドバ' => 'MD',
    'モンゴル' => 'MN',
    'モンテネグロ' => 'ME',
    'モロッコ' => 'MA',
    'ミャンマー' => 'MM',
    'オランダ' => 'NL',
    'ナイジェリア' => 'NG',
    '北朝鮮' => 'KP',
    'ノルウェー' => 'NO',
    'パキスタン' => 'PK',
    'パレスチナ' => 'PS',
    'パナマ' => 'PA',
    'ペルー' => 'PE',
    'フィリピン' => 'PH',
    'ポーランド' => 'PL',
    'ポルトガル' => 'PT',
    'カタール' => 'QA',
    'ルーマニア' => 'RO',
    'ロシア' => 'RU',
    'サウジアラビア' => 'SA',
    'セルビア' => 'RS',
    'シンガポール' => 'SG',
    'スロバキア' => 'SK',
    'スロベニア' => 'SI',
    '南アフリカ' => 'ZA',
    'スペイン' => 'ES',
    'スーダン' => 'SD',
    'スウェーデン' => 'SE',
    'スイス' => 'CH',
    'シリア' => 'SY',
    '台湾' => 'TW',
    'タジキスタン' => 'TJ',
    'タンザニア' => 'TZ',
    'タイ' => 'TH',
    'チュニジア' => 'TN',
    'トルコ' => 'TR',
    'トルクメニスタン' => 'TM',
    'ウガンダ' => 'UG',
    'ウクライナ' => 'UA',
    'イギリス' => 'GB',
    'アメリカ' => 'US',
    'ウズベキスタン' => 'UZ',
    'ベネズエラ' => 'VE',
    'ベトナム' => 'VN',
    'イエメン' => 'YE',
    'ザンビア' => 'ZM',
    'ジンバブエ' => 'ZW'
  }.freeze

  def initialize(xlsx_path)
    @xlsx_path = xlsx_path
    @xlsx = Roo::Excelx.new(xlsx_path)
    @xlsx.default_sheet = @xlsx.sheets.first

    # Extract date from filename (format: YYYYMMDD_x.xlsx)
    @publish_date = extract_date_from_filename

    # Store source file info
    @source_file = File.basename(xlsx_path)
    @source_url = nil # Will be set by the downloader
  end

  def set_source_url(url)
    @source_url = url
  end

  def convert
    entities = []

    # Skip header row (row 1)
    (2..@xlsx.last_row).each do |row_num|
      entity = process_row(row_num)
      entities << entity if entity
    end

    {
      'announcement' => build_announcement,
      'sanction_details' => {
        'instruments' => build_instruments,
        'entities' => entities.compact
      }
    }
  end

  private

  def extract_date_from_filename
    filename = File.basename(@xlsx_path)
    match = filename.match(/(\d{8})/)
    match ? "#{match[1][0,4]}-#{match[1][4,2]}-#{match[1][6,2]}" : Date.today.to_s
  end

  def build_announcement
    announcement = {
      'title' => [
        { 'ja' => '外国ユーザーリスト' },
        { 'en' => 'Foreign User List' }
      ],
      'url' => 'https://www.meti.go.jp/policy/anpo/law00.html',
      'lang' => 'ja',
      'publish_date' => @publish_date,
      'authority' => 'jp/meti',
      'publisher' => 'jp/meti',
      'type' => 'jp/meti-foreign-user-list-announcement'
    }

    # Add source URL if available
    announcement['source_file'] = @source_file if @source_file
    announcement['source_url'] = @source_url if @source_url

    announcement
  end

  def build_instruments
    [
      { 'id' => 'jp/diet-foreign-exchange-and-foreign-trade-act' },
      { 'id' => 'jp/cabinet-order-foreign-exchange' },
      { 'id' => 'jp/meti-export-trade-control-order' },
      { 'id' => 'jp/meti-foreign-exchange-order' }
    ]
  end

  def process_row(row_num)
    row = @xlsx.row(row_num)

    # Column structure:
    # 1: No. (ID number)
    # 2: Country (Japanese\nEnglish)
    # 3: Company name
    # 4: Aliases (・Name1\n・Name2...)
    # 5: WMD type (Japanese\nCodes like B,C,M,N)
    # 6: Conventional weapons (optional)

    id = row[0]
    country_raw = row[1]
    company = row[2]
    aliases_raw = row[3]
    wmd_raw = row[4]
    cw_raw = row[5]

    return nil if id.nil? || company.nil? || company.strip.empty?

    # Parse country
    country = parse_bilingual_text(country_raw)

    # Parse aliases
    aliases = parse_aliases(aliases_raw)

    # Parse WMD types
    wmd_codes = extract_wmd_codes(wmd_raw, cw_raw)
    reasons = build_reasons(wmd_codes)

    # Get country code
    country_code = lookup_country_code(country[:ja], country[:en])

    # Build entity with proper ID
    entity = {
      'id' => "jp.meti.ful.#{id.to_i}",
      'name' => build_name(company),
      'type' => 'organization',
      'effective_date' => @publish_date,
      'sanction_list' => 'jp/meti-foreign-user-list',
      'reason' => reasons
    }

    # Add source information
    entity['source_file'] = @source_file if @source_file
    entity['source_url'] = @source_url if @source_url

    # Add country information
    if country_code
      entity['country_code'] = country_code
      entity['country_name'] = build_country_name(country)
    end

    # Add measures
    entity['measures'] = default_measures

    # Add aliases if present
    entity['aliases'] = aliases unless aliases.empty?

    entity.compact
  end

  def parse_bilingual_text(text)
    return { ja: nil, en: nil } unless text

    # Split by newline
    parts = text.to_s.split("\n").map(&:strip).reject(&:empty?)

    if parts.length >= 2
      { ja: parts[0], en: parts[1] }
    elsif parts.length == 1
      # Determine if Japanese or English
      if parts[0].match?(/[\p{Hiragana}\p{Katakana}\p{Han}]/)
        { ja: parts[0], en: nil }
      else
        { ja: nil, en: parts[0] }
      end
    else
      { ja: nil, en: nil }
    end
  end

  def parse_aliases(text)
    return [] unless text

    # Split by newline and clean up
    text.to_s.split("\n").map do |line|
      # Remove leading bullet points (・, •, -)
      cleaned = line.strip.sub(/^[・•\-\*]\s*/, '').strip
      cleaned unless cleaned.empty?
    end.compact
  end

  def extract_wmd_codes(wmd_raw, cw_raw)
    codes = []

    # Extract codes from WMD column (format: "生物、化学、ミサイル、核\nB,C,M,N")
    # Note: Some codes may be fullwidth (Ｂ, Ｃ, Ｍ, Ｎ)
    if wmd_raw
      # Normalize fullwidth to halfwidth characters
      normalized = wmd_raw.to_s.chars.map do |c|
        if c.match?(/[Ａ-Ｚａ-ｚ０-９]/)
          (c.ord - 0xFEE0).chr
        else
          c
        end
      end.join.upcase
      # Find letter codes (B, C, M, N)
      normalized.scan(/[BCMN]/).each { |code| codes << code unless codes.include?(code) }
    end

    # Check for conventional weapons
    if cw_raw
      normalized_cw = cw_raw.to_s.chars.map do |c|
        if c.match?(/[Ａ-Ｚａ-ｚ０-９]/)
          (c.ord - 0xFEE0).chr
        else
          c
        end
      end.join.upcase
      normalized_cw.scan(/CW/).each { |code| codes << code unless codes.include?(code) }
    end

    codes.uniq
  end

  def build_reasons(codes)
    reasons = []

    codes.each do |code|
      info = WMD_TYPES[code]
      if info
        reasons << {
          'ja' => "#{info[:ja]}の開発・拡散に関与",
          'en' => "Involved in development or proliferation of #{info[:en].downcase}"
        }
      end
    end

    reasons
  end

  def lookup_country_code(ja_name, en_name)
    # Try Japanese name first
    if ja_name
      return COUNTRY_CODES[ja_name] if COUNTRY_CODES[ja_name]

      # Try partial match
      COUNTRY_CODES.each do |name, code|
        return code if ja_name.include?(name) || name.include?(ja_name)
      end
    end

    # Try English name
    if en_name
      en_lower = en_name.downcase
      # Common English name mappings
      COUNTRY_CODES.each_value do |code|
        case code
        when 'AF' then return 'AF' if en_lower.include?('afghanistan')
        when 'AE' then return 'AE' if en_lower.include?('arab emirates') || en_lower.include?('uae')
        when 'CN' then return 'CN' if en_lower.include?('china') && !en_lower.include?('taiwan')
        when 'HK' then return 'HK' if en_lower.include?('hong kong')
        when 'KP' then return 'KP' if en_lower.include?('north korea') || en_lower.include?("democratic people's")
        when 'KR' then return 'KR' if en_lower.include?('korea') && !en_lower.include?('north')
        when 'IR' then return 'IR' if en_lower.include?('iran')
        when 'IQ' then return 'IQ' if en_lower.include?('iraq')
        when 'RU' then return 'RU' if en_lower.include?('russia')
        when 'SY' then return 'SY' if en_lower.include?('syria')
        when 'TW' then return 'TW' if en_lower.include?('taiwan')
        end
      end
    end

    nil
  end

  def build_name(company)
    name = {}
    text = company.to_s.strip

    # Check if bilingual (contains both Japanese and English)
    if text.include?("\n")
      parts = text.split("\n").map(&:strip)
      if parts.length >= 2
        name['ja'] = parts[0] if parts[0].match?(/[\p{Hiragana}\p{Katakana}\p{Han}]/)
        name['en'] = parts.find { |p| p.match?(/^[A-Za-z]/) }
      end
    end

    # If not bilingual or couldn't parse, use as-is
    if name.empty?
      if text.match?(/[\p{Hiragana}\p{Katakana}\p{Han}]/)
        name['ja'] = text
      else
        name['en'] = text
      end
    end

    name
  end

  def build_country_name(country)
    name = {}
    name['ja'] = country[:ja] if country[:ja]
    name['en'] = country[:en] if country[:en]
    name
  end

  def default_measures
    [
      {
        'type' => ['export_license_requirement'],
        'ja' => '輸出に際して許可が必要',
        'en' => 'Export license required'
      }
    ]
  end
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  xlsx_path = ARGV[0] || 'reference-docs/20250929_4.xlsx'
  output_path = ARGV[1] || 'sources/sanction-lists/foreign-user-list/20250929.yml'

  puts "Converting #{xlsx_path} to #{output_path}..."

  converter = ForeignUserListConverter.new(xlsx_path)
  result = converter.convert

  if result
    # Add YAML schema reference at the top
    schema_comment = "# yaml-language-server: $schema=../../../schemas/jp-announcement.yml\n"

    # Write to file with proper formatting
    FileUtils.mkdir_p(File.dirname(output_path))
    File.write(output_path, schema_comment + result.to_yaml(line_width: -1))

    entities_count = result['sanction_details']['entities'].size
    puts "Successfully converted to #{output_path}"
    puts "Total entities: #{entities_count}"
  else
    puts "ERROR: Failed to convert Excel"
    exit 1
  end
end
