#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to convert Japanese FEFTA End User List HTML to YAML sanction list format
# Usage: ruby scripts/convert_html_to_yaml.rb [html_path] [output_path]

require 'nokogiri'
require 'yaml'
require 'fileutils'
require 'date'

class HtmlEndUserListConverter
  # WMD Type mappings (single letter codes in HTML)
  WMD_TYPES = {
    'N' => { ja: '核', en: 'Nuclear', reason_ja: '核兵器の開発・拡散に関与', reason_en: 'Involved in development or proliferation of nuclear weapons' },
    'M' => { ja: 'ミサイル', en: 'Missile', reason_ja: 'ミサイルの開発・拡散に関与', reason_en: 'Involved in development or proliferation of missiles' },
    'B' => { ja: '生物', en: 'Biological', reason_ja: '生物兵器の開発・拡散に関与', reason_en: 'Involved in development or proliferation of biological weapons' },
    'C' => { ja: '化学', en: 'Chemical', reason_ja: '化学兵器の開発・拡散に関与', reason_en: 'Involved in development or proliferation of chemical weapons' }
  }.freeze

  # ISO 3166-1 alpha-2 country code mappings (Japanese names to codes)
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
    'ザンビア' => 'ZW',
    'ジンバブエ' => 'ZW'
  }.freeze

  def initialize(html_path)
    @html_path = html_path
    @doc = Nokogiri::HTML(File.read(html_path, encoding: 'UTF-8'))
  end

  def convert
    rows = extract_table_rows
    return nil if rows.empty?

    entities = []
    row_num = 0

    rows.each do |row|
      row_num += 1
      entity = process_row(row, row_num)
      entities << entity if entity
    end

    {
      'announcement' => extract_announcement_info,
      'sanction_details' => {
        'instruments' => extract_legal_instruments,
        'entities' => entities.compact
      }
    }
  end

  private

  def extract_table_rows
    table = @doc.at('table')
    return [] unless table

    rows = table.search('tr')
    # Skip header row (first row)
    rows[1..-1] || []
  end

  def extract_announcement_info
    filename = File.basename(@html_path)
    date_match = filename.match(/(\d{8})/)
    publish_date = date_match ? format_date(date_match[1]) : Date.today.to_s

    {
      'title' => [
        { 'ja' => '我が国の平和及び安全の維持のための措置に関するリスト' },
        { 'en' => 'List concerning Measures for the Maintenance of Peace and Security of Japan' }
      ],
      'url' => 'https://www.meti.go.jp/policy/anpo/index.html',
      'publish_date' => publish_date,
      'authority' => 'jp/meti',
      'type' => 'jp/fefta-end-user-list-announcement'
    }
  end

  def format_date(date_str)
    "#{date_str[0,4]}-#{date_str[4,2]}-#{date_str[6,2]}"
  end

  def extract_legal_instruments
    [
      { 'id' => 'jp/diet-foreign-exchange-and-foreign-trade-act' },
      { 'id' => 'jp/cabinet-order-foreign-exchange' }
    ]
  end

  def process_row(row, _row_num)
    cells = row.search('td')
    return nil if cells.empty? || cells.length < 5

    # Column structure:
    # 0: No.
    # 1: Country or Region (国名、地域名)
    # 2: Company or Organization (企業名､組織名)
    # 3: Also Known As (別名)
    # 4: Type of WMD (懸念区分) - single letter code (N, M, B, C)

    country_raw = extract_cell_text(cells[1])
    company_raw = extract_cell_text(cells[2])
    aliases_raw = extract_cell_text(cells[3])
    wmd_code = extract_wmd_code(cells[4])

    return nil if company_raw.nil? || company_raw.strip.empty?

    # Parse country (Japanese and English)
    country = parse_bilingual_text(country_raw)

    # Parse company name
    company = parse_bilingual_text(company_raw)

    # Parse aliases - split by '・' (Japanese bullet point)
    aliases = parse_aliases(aliases_raw)

    # Parse WMD type
    wmd_info = WMD_TYPES[wmd_code] || { reason_ja: nil, reason_en: nil }

    # Get ISO country code
    country_code = lookup_country_code(country[:ja], country[:en])

    # Build entity record
    entity = {
      'name' => build_name_hash(company),
      'type' => 'organization',
      'effective_date' => extract_publish_date,
      'sanction_list' => 'jp/fefta-end-user-list',
      'reason' => build_reason(wmd_info)
    }

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

  def extract_wmd_code(cell)
    return nil unless cell

    # The WMD code is usually a single letter (N, M, B, C) in the last cell
    # Sometimes it's combined with Japanese text like "ミサイルM"
    text = cell.text.strip.gsub(/\s+/, '')

    # Find single letter code at the end or standalone
    match = text.match(/([NMBC])\z/) || text.match(/\b([NMBC])\b/)
    match ? match[1] : nil
  end

  def extract_cell_text(cell)
    return nil unless cell

    # Get all text from paragraphs
    paragraphs = cell.search('p')
    texts = paragraphs.map do |p|
      # Normalize whitespace: replace newlines and multiple spaces with single space
      p.text.strip.gsub(/\s+/, ' ')
    end.reject(&:empty?)

    texts.empty? ? cell.text.strip.gsub(/\s+/, ' ') : texts.join(' ')
  end

  def parse_bilingual_text(text)
    return { ja: nil, en: nil } unless text

    # Try to split Japanese and English text
    # Pattern: Japanese text followed by English text
    # Example: "アフガニスタン Islamic Republic of Afghanistan"

    # Find where English starts (first Latin character sequence after Japanese)
    match = text.match(/^([\p{Hiragana}\p{Katakana}\p{Han}\s\p{Punctuation}]+)\s+([A-Za-z].*)$/)

    if match
      ja_part = match[1].strip
      en_part = match[2].strip

      return { ja: ja_part, en: en_part } unless ja_part.empty?
    end

    # If no clear split, check if text is primarily Japanese or English
    if text.match?(/^[\p{Hiragana}\p{Katakana}\p{Han}\s\p{Punctuation}]+$/)
      { ja: text.strip, en: nil }
    else
      { ja: nil, en: text.strip }
    end
  end

  def parse_aliases(text)
    return [] unless text

    # Split by Japanese bullet point '・'
    aliases = []

    text.split(/[・•]/).each do |part|
      cleaned = part.strip
                   .sub(/^[\-\*]\s*/, '')  # Remove leading dashes/asterisks
                   .gsub(/\s+/, ' ')        # Normalize whitespace
      aliases << cleaned if cleaned && !cleaned.empty?
    end

    aliases.uniq
  end

  def lookup_country_code(ja_name, en_name)
    # Try Japanese name first
    if ja_name
      # Try exact match
      return COUNTRY_CODES[ja_name] if COUNTRY_CODES[ja_name]

      # Try partial match
      COUNTRY_CODES.each do |name, code|
        return code if ja_name.include?(name) || name.include?(ja_name)
      end
    end

    # Try English name
    if en_name
      en_lower = en_name.downcase
      COUNTRY_CODES.each do |_name, code|
        # This is a simplified lookup - you may need a more comprehensive mapping
        case code
        when 'AF' then return 'AF' if en_lower.include?('afghanistan')
        when 'AE' then return 'AE' if en_lower.include?('arab emirates') || en_lower.include?('uae')
        when 'CN' then return 'CN' if en_lower.include?('china')
        when 'KP' then return 'KP' if en_lower.include?('north korea') || en_lower.include?("democratic people's")
        when 'KR' then return 'KR' if en_lower.include?('korea') && !en_lower.include?('north')
        when 'IR' then return 'IR' if en_lower.include?('iran')
        when 'IQ' then return 'IQ' if en_lower.include?('iraq')
        when 'RU' then return 'RU' if en_lower.include?('russia')
        when 'SY' then return 'SY' if en_lower.include?('syria')
        when 'HK' then return 'HK' if en_lower.include?('hong kong')
        when 'TW' then return 'TW' if en_lower.include?('taiwan')
        end
      end
    end

    nil
  end

  def build_name_hash(company)
    name = {}

    name['ja'] = company[:ja] if company[:ja]
    name['en'] = company[:en] if company[:en]

    # If no clear split, treat entire text as English
    if !name['ja'] && !name['en']
      name['en'] = company[:ja] || company[:en]
    end

    name
  end

  def build_country_name(country)
    name = {}
    name['ja'] = country[:ja] if country[:ja]
    name['en'] = country[:en] if country[:en]
    name
  end

  def build_reason(wmd_info)
    return [] unless wmd_info[:reason_ja] || wmd_info[:reason_en]

    reason = {}
    reason['ja'] = wmd_info[:reason_ja] if wmd_info[:reason_ja]
    reason['en'] = wmd_info[:reason_en] if wmd_info[:reason_en]
    [reason]
  end

  def default_measures
    [
      {
        'type' => ['export_license_requirement'],
        'ja' => '輸出に際して許可が必要',
        'en' => 'Export license required'
      },
      {
        'type' => ['asset_freeze'],
        'ja' => '資産凍結の対象',
        'en' => 'Subject to asset freeze'
      }
    ]
  end

  def extract_publish_date
    filename = File.basename(@html_path)
    date_match = filename.match(/(\d{8})/)
    date_match ? format_date(date_match[1]) : Date.today.to_s
  end
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  html_path = ARGV[0] || 'reference-docs/20250131-jp-end-user-list.html'
  output_path = ARGV[1] || 'sources/sanction-lists/fefta-list/20250131.yml'

  puts "Converting #{html_path} to #{output_path}..."

  converter = HtmlEndUserListConverter.new(html_path)
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
    puts "ERROR: Failed to convert HTML"
    exit 1
  end
end
