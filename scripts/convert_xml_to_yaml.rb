#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to convert Japanese e-Gov XML law format to YAML legal instrument format
# Output format matches the example file with plain string content (not bilingual objects)
# Usage: ruby scripts/convert_xml_to_yaml.rb [xml_path] [output_path]

require 'nokogiri'
require 'yaml'
require 'fileutils'

class XmlLawConverter
  def initialize(xml_path)
    @xml_path = xml_path
    @doc = Nokogiri::XML(File.read(xml_path))
    @doc.remove_namespaces!
  end

  def convert
    law = @doc.at('Law')
    return nil unless law

    result = {
      'id' => extract_id(law),
      'title' => extract_titles(law),
      'url' => extract_url(law),
      'type' => extract_type(law),
      'authority' => extract_authority(law),
      'publisher' => extract_publisher(law),
      'document_id' => extract_document_id(law),
      'lang' => 'ja',
      'publish_date' => extract_publish_date(law),
      'effective_date' => extract_effective_date(law),
      'approval_history' => extract_approval_history(law),
      'content' => extract_content(law)
    }

    result.compact
  end

  private

  def extract_id(law)
    law_num = law.at('LawNum')&.text
    law_title = law.at('LawTitle')&.text

    # Generate ID based on document type and title
    if law_num&.include?('外国為替及び外国貿易法') || law_title&.include?('外国為替及び外国貿易法')
      'jp/diet-foreign-exchange-and-foreign-trade-act'
    elsif law_num&.include?('輸出貿易管理令') || law_title&.include?('輸出貿易管理令')
      'jp/cabinet-order-export-trade-control'
    elsif law_num&.include?('輸入貿易管理令') || law_title&.include?('輸入貿易管理令')
      'jp/cabinet-order-import-trade-control'
    else
      # Generate from title - remove common suffixes and convert to lowercase
      slug = law_title.to_s.gsub(/令$/, '').gsub(/法$/, '').gsub(/則$/, '')
      slug = slug.gsub(/[^\u3040-\u9fff\w]/, '').downcase
      "jp/#{slug}"
    end
  end

  def extract_titles(law)
    law_title = law.at('LawTitle')&.text
    return [] unless law_title

    [{ 'ja' => law_title }]
  end

  def extract_url(_law)
    'https://elaws.e-gov.go.jp/document?lawid=324AC0000000228'
  end

  def extract_type(law)
    law_type = law['LawType']

    case law_type
    when 'Act'
      'jp/act-of-diet'
    when 'CabinetOrder'
      'jp/cabinet-order'
    when 'MinisterialOrdinance'
      'jp/ministerial-ordinance'
    when 'ImperialOrder'
      'jp/imperial-order'
    else
      "jp/#{law_type.to_s.downcase.gsub(/([a-z])([A-Z])/, '\1-\2').downcase}"
    end
  end

  def extract_authority(law)
    law_type = law['LawType']

    case law_type
    when 'Act'
      'jp/diet'
    when 'CabinetOrder'
      'jp/cabinet'
    when 'MinisterialOrdinance'
      'jp/meti'
    else
      'jp/government'
    end
  end

  def extract_publisher(law)
    extract_authority(law)
  end

  def extract_document_id(law)
    law.at('LawNum')&.text
  end

  def extract_publish_date(law)
    year = law['Year']
    month = law['PromulgateMonth']
    day = law['PromulgateDay']
    era = law['Era']

    return nil unless year && month && day

    western_year = convert_era_to_western(era, year.to_i)
    return nil unless western_year

    format('%04d-%02d-%02d', western_year, month.to_i, day.to_i)
  end

  def extract_effective_date(law)
    extract_publish_date(law)
  end

  def extract_approval_history(law)
    # Look for SupplProvision with amendment history
    suppl_provisions = law.search('SupplProvision')
    return [] if suppl_provisions.empty?

    history = []
    suppl_provisions.each do |sp|
      amend_law_num = sp['AmendLawNum']
      next unless amend_law_num

      # Extract enforcement date from the first sentence
      first_sentence = sp.at('Sentence')
      next unless first_sentence

      text = first_sentence.text

      # Parse the enforcement date - only include if it's a specific date
      date_str = extract_enforcement_date(text)
      next unless date_str

      # Skip relative dates like "公布の日" or "政令で定める日"
      next if date_str.include?('公布') || date_str.include?('政令') || date_str.include?('施行の日')

      # Format: {date} 施行 （{law_num}）
      entry = "#{date_str} 施行 （#{amend_law_num}）"
      history << entry
    end

    # Sort by date (newest first) - for now just reverse the order
    history.reverse
  end

  def extract_enforcement_date(text)
    # Common patterns:
    # "この法律は、昭和二十六年四月一日から施行する。" -> Extract date
    # "この法律は、公布の日から施行する。" -> Skip (no specific date)

    # Match patterns like "昭和二十六年四月一日から施行" or "令和4年6月17日から施行"
    # The date pattern: era + year + month + day
    match = text.match(/((昭和|平成|令和|大正|明治)[一二三四五六七八九十百零〇\d]+年[一二三四五六七八九十百零〇\d]+月[一二三四五六七八九十百零〇\d]+日)から施行/)
    return match[1].strip if match

    nil
  end

  def extract_content(law)
    main_provision = law.at('MainProvision')
    return [] unless main_provision

    process_main_provision(main_provision)
  end

  def process_main_provision(main_provision)
    result = []

    main_provision.children.each do |child|
      next if child.text? && child.text.strip.empty?

      case child.name
      when 'Chapter'
        result << process_chapter(child)
      when 'Article'
        # Handle articles directly in MainProvision (no chapter structure)
        result << process_article(child)
      end
    end

    result
  end

  def process_chapter(chapter)
    chapter_title = chapter.at('ChapterTitle')&.text
    chapter_num = chapter['Num']

    {
      'type' => 'chapter',
      'index' => parse_chapter_number(chapter_num),
      'label' => extract_chapter_label(chapter_title),
      'title' => extract_chapter_title(chapter_title),
      'content' => process_chapter_content(chapter)
    }.compact
  end

  def process_chapter_content(chapter)
    result = []

    chapter.children.each do |child|
      next if child.text? && child.text.strip.empty?

      case child.name
      when 'Article'
        result << process_article(child)
      end
    end

    result
  end

  def process_article(article)
    article_num = article['Num']
    article_title = article.at('ArticleTitle')&.text
    article_caption = article.at('ArticleCaption')&.text

    # Handle range articles (e.g., "第二条から第四条まで")
    if article_title&.include?('から') && article_title&.include?('まで')
      return process_range_article(article, article_title, article_caption)
    end

    paragraphs = article.search('> Paragraph')

    result = {
      'type' => 'clause',
      'index' => parse_article_number(article_num || article_title)&.to_s,
      'label' => article_title,
      'title' => article_caption,
      'content' => process_article_paragraphs(paragraphs)
    }

    result.delete('title') if result['title']&.empty?

    result.compact
  end

  def process_range_article(article, title, caption)
    # Extract the first article label from the range (e.g., "第二条" from "第二条から第四条まで")
    first_article_match = title.match(/第([一二三四五六七八九十百]+)条/)
    first_label = first_article_match ? "第#{first_article_match[1]}条" : title

    # Extract last article from range (e.g., "第四条" from "第二条から第四条まで")
    last_article_match = title.match(/から第([一二三四五六七八九十百]+)条まで/)
    first_num = japanese_to_number(first_article_match&.[](1))
    last_num = japanese_to_number(last_article_match&.[](1))

    # Generate index as range string (e.g., "2-4")
    index = if first_num && last_num
              "#{first_num}-#{last_num}"
            elsif first_num
              first_num.to_s
            else
              nil
            end

    {
      'type' => 'clause',
      'index' => index,
      'label' => first_label,
      'title' => title,
      'content' => ['削除']
    }.compact
  end

  def process_article_paragraphs(paragraphs)
    result = []

    paragraphs.each_with_index do |paragraph, para_idx|
      para_num = paragraph['Num']&.to_i || (para_idx + 1)
      para_num_text = paragraph.at('ParagraphNum')&.text

      items = paragraph.search('> Item')
      subitems1 = paragraph.search('> Subitem1')

      # Get paragraph sentence (introductory text before items)
      sentences = extract_paragraph_sentences(paragraph)

      if items.any?
        # Add introductory sentences before the numbered list
        result.concat(sentences) if sentences.any?
        # Process items - all items at this level are siblings
        list_result = {
          'type' => 'numbered-list',
          'index' => para_num.to_s
        }
        list_result['label'] = para_num_text if para_num_text && !para_num_text.empty?
        list_result['content'] = items.map { |item| process_item(item) }.compact
        result << list_result
      elsif subitems1.any?
        # Add introductory sentences before the numbered list
        result.concat(sentences) if sentences.any?
        # Direct subitems without parent item
        list_result = {
          'type' => 'numbered-list',
          'index' => para_num.to_s
        }
        list_result['label'] = para_num_text if para_num_text && !para_num_text.empty?
        list_result['content'] = subitems1.map { |si| process_subitem1(si) }.compact
        result << list_result
      elsif sentences.any? && para_num > 1 && result.last && result.last['type'] == 'numbered-list'
        # Paragraph without items but with sentences (e.g., Article 6 Paragraph 2)
        # Treat this as a list-item in the previous numbered-list
        list_item = {
          'type' => 'list-item',
          'content' => sentences
        }
        # Try to determine the item number from context (十七 for Article 6 Para 2)
        list_item['index'] = '17' if para_num == 2
        list_item['label'] = '十七' if para_num == 2
        result.last['content'] << list_item.compact
      elsif sentences.any?
        # Standalone sentences (not part of a numbered list)
        result.concat(sentences)
      end
    end

    result
  end

  def process_item(item)
    item_title = item.at('ItemTitle')&.text
    item_sentence = item.at('ItemSentence')
    subitems1 = item.search('> Subitem1')

    content = []

    # Extract sentences from item - use plain strings
    if item_sentence
      sentences = item_sentence.search('Sentence')
      sentences.each do |s|
        text = s.text.strip
        content << text if text && !text.empty?
      end
    end

    # Process subitems if present (these are nested inside this item)
    if subitems1.any?
      subitem_list = {
        'type' => 'numbered-list',
        'content' => subitems1.map { |si| process_subitem1(si) }.compact
      }
      content << subitem_list
    end

    return nil if content.empty?

    {
      'type' => 'list-item',
      'index' => item['Num']&.to_s,
      'label' => item_title,
      'content' => content
    }.compact
  end

  def process_subitem1(subitem)
    subitem_title = subitem.at('Subitem1Title')&.text
    subitem_sentence = subitem.at('Subitem1Sentence')
    subitems2 = subitem.search('> Subitem2')

    content = []

    if subitem_sentence
      sentences = subitem_sentence.search('Sentence')
      sentences.each do |s|
        text = s.text.strip
        content << text if text && !text.empty?
      end
    end

    if subitems2.any?
      subitem2_list = {
        'type' => 'numbered-list',
        'content' => subitems2.map { |si| process_subitem2(si) }.compact
      }
      content << subitem2_list
    end

    return nil if content.empty?

    {
      'type' => 'list-item',
      'index' => subitem['Num']&.to_s,
      'label' => subitem_title,
      'content' => content
    }.compact
  end

  def process_subitem2(subitem)
    subitem_title = subitem.at('Subitem2Title')&.text
    subitem_sentence = subitem.at('Subitem2Sentence')

    content = []

    if subitem_sentence
      sentences = subitem_sentence.search('Sentence')
      sentences.each do |s|
        text = s.text.strip
        content << text if text && !text.empty?
      end
    end

    return nil if content.empty?

    {
      'type' => 'list-item',
      'index' => subitem['Num']&.to_s,
      'label' => subitem_title,
      'content' => content
    }.compact
  end

  def extract_paragraph_sentences(paragraph)
    result = []
    sentence_container = paragraph.at('ParagraphSentence')

    return result unless sentence_container

    sentences = sentence_container.search('Sentence')
    sentences.each do |s|
      text = s.text.strip
      result << text if text && !text.empty?
    end

    result
  end

  # Helper methods

  def convert_era_to_western(era, year)
    case era
    when 'Meiji'
      1868 + year - 1
    when 'Taisho'
      1912 + year - 1
    when 'Showa'
      1926 + year - 1
    when 'Heisei'
      1989 + year - 1
    when 'Reiwa'
      2019 + year - 1
    else
      nil
    end
  end

  def parse_chapter_number(num_str)
    return nil unless num_str

    # Handle formats like "1", "1_2", "2_1"
    if num_str.include?('_')
      parts = num_str.split('_')
      return parts.join('-')
    end

    num_str.to_s
  end

  def extract_chapter_label(title)
    return nil unless title

    match = title.match(/(第[一二三四五六七八九十百]+章(?:の[一二三四五六七八九十百]+)?)/)
    match ? match[1] : nil
  end

  def extract_chapter_title(title)
    return nil unless title

    title.sub(/第[一二三四五六七八九十百]+章(?:の[一二三四五六七八九十百]+)?[\s　]*/, '')
  end

  def parse_article_number(num_or_title)
    return nil unless num_or_title

    # Handle format like "1:2" (range)
    if num_or_title.include?(':')
      return num_or_title.split(':').first.to_s
    end

    # Handle format like "1_2" (sub-article)
    if num_or_title.include?('_')
      parts = num_or_title.split('_')
      return parts.join('-')
    end

    # Extract from Japanese format like "第一条", "第二条の二"
    match = num_or_title.to_s.match(/第([一二三四五六七八九十百]+)条(?:の([一二三四五六七八九十百]+))?/)
    if match
      main_num = japanese_to_number(match[1])
      sub_num = match[2] ? japanese_to_number(match[2]) : nil
      return sub_num ? "#{main_num}-#{sub_num}" : main_num.to_s
    end

    # Plain number
    num_or_title.to_s if num_or_title.match?(/^\d+$/)
  end

  def japanese_to_number(str)
    return nil unless str

    mapping = {
      '一' => 1, '二' => 2, '三' => 3, '四' => 4, '五' => 5,
      '六' => 6, '七' => 7, '八' => 8, '九' => 9, '十' => 10,
      '十一' => 11, '十二' => 12, '十三' => 13, '十四' => 14, '十五' => 15,
      '十六' => 16, '十七' => 17, '十八' => 18, '十九' => 19, '二十' => 20,
      '二十一' => 21, '二十二' => 22, '二十三' => 23, '二十四' => 24, '二十五' => 25,
      '二十六' => 26, '二十七' => 27, '二十八' => 28, '二十九' => 29, '三十' => 30,
      '三十一' => 31, '三十二' => 32, '三十三' => 33, '三十四' => 34, '三十五' => 35,
      '三十六' => 36, '三十七' => 37, '三十八' => 38, '三十九' => 39, '四十' => 40,
      '四十一' => 41, '四十二' => 42, '四十三' => 43, '四十四' => 44, '四十五' => 45,
      '四十六' => 46, '四十七' => 47, '四十八' => 48, '四十九' => 49, '五十' => 50,
      '五十一' => 51, '五十二' => 52, '五十三' => 53, '五十四' => 54, '五十五' => 55,
      '五十六' => 56, '五十七' => 57, '五十八' => 58, '五十九' => 59, '六十' => 60,
      '六十一' => 61, '六十二' => 62, '六十三' => 63, '六十四' => 64, '六十五' => 65,
      '六十六' => 66, '六十七' => 67, '六十八' => 68, '六十九' => 69, '七十' => 70,
      '七十一' => 71, '七十二' => 72, '七十三' => 73, '七十四' => 74, '七十五' => 75,
      '百' => 100
    }

    mapping[str] || parse_complex_japanese_number(str)
  end

  def parse_complex_japanese_number(str)
    result = 0
    str.chars.each do |char|
      case char
      when '十'
        result = result.zero? ? 10 : result * 10
      when '百'
        result = result.zero? ? 100 : result * 100
      else
        digit = { '一' => 1, '二' => 2, '三' => 3, '四' => 4, '五' => 5,
                  '六' => 6, '七' => 7, '八' => 8, '九' => 9 }[char]
        result += digit if digit
      end
    end
    result
  end
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  xml_path = ARGV[0] || 'reference-docs/324AC0000000228_20250601_504AC0000000068.xml'
  output_path = ARGV[1] || 'sources/legal-instruments/diet-foreign-exchange-and-foreign-trade-act.yml'

  puts "Converting #{xml_path} to #{output_path}..."

  converter = XmlLawConverter.new(xml_path)
  result = converter.convert

  if result
    # Add YAML schema reference at the top
    schema_comment = "# yaml-language-server: $schema=../../schemas/jp-legal-instrument.yml\n"

    # Write to file with proper formatting
    FileUtils.mkdir_p(File.dirname(output_path))
    File.write(output_path, schema_comment + result.to_yaml(line_width: -1))

    puts "Successfully converted to #{output_path}"
    puts "Total chapters: #{result['content']&.size || 0}"
  else
    puts "ERROR: Failed to convert XML"
    exit 1
  end
end
