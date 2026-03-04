#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to add English translations to Japanese legal instrument YAML
# Uses TMX translation memory file for translations
# Usage: ruby scripts/add_translations.rb [yaml_path] [tmx_path] [output_path]

require 'nokogiri'
require 'yaml'
require 'fileutils'

class TranslationAdder
  def initialize(tmx_path)
    @translations = load_tmx_translations(tmx_path)
    puts "Loaded #{@translations.size} translation pairs from TMX"
  end

  def load_tmx_translations(tmx_path)
    return {} unless tmx_path && File.exist?(tmx_path)

    tmx_doc = Nokogiri::XML(File.read(tmx_path, encoding: 'UTF-8'))
    tmx_doc.remove_namespaces!

    translations = {}

    tmx_doc.search('tu').each do |tu|
      ja_seg = tu.at('tuv[xml:lang="ja-JP"] seg')&.text
      en_seg = tu.at('tuv[xml:lang="en-US"] seg')&.text

      next unless ja_seg && en_seg

      # Store with normalized key (whitespace normalized)
      normalized_ja = normalize_text(ja_seg)
      translations[normalized_ja] = en_seg

      # Also store with original key
      translations[ja_seg] = en_seg
    end

    translations
  end

  def normalize_text(text)
    text.gsub(/\s+/, ' ').strip
  end

  def find_translation(ja_text)
    return nil unless ja_text

    # Try exact match first
    return @translations[ja_text] if @translations[ja_text]

    # Try normalized match
    normalized = normalize_text(ja_text)
    return @translations[normalized] if @translations[normalized]

    # Try partial match (for longer texts)
    @translations.each do |ja, en|
      if ja.include?(normalized) || normalized.include?(ja)
        return en
      end
    end

    nil
  end

  def process_yaml(input_path, output_path)
    yaml_content = File.read(input_path)

    # Skip the schema comment line
    schema_line = ''
    if yaml_content.start_with?('# yaml-language-server')
      lines = yaml_content.lines
      schema_line = lines.shift
      yaml_content = lines.join
    end

    data = YAML.safe_load(yaml_content, permitted_classes: [Date, Time])

    # Process the data structure
    processed_data = process_data(data)

    # Write output
    FileUtils.mkdir_p(File.dirname(output_path))
    output_content = schema_line + processed_data.to_yaml(line_width: -1)
    File.write(output_path, output_content)

    puts "Successfully wrote bilingual YAML to #{output_path}"
  end

  private

  def process_data(data)
    return data unless data.is_a?(Hash)

    result = data.dup

    # Process title array
    if result['title'].is_a?(Array)
      result['title'] = process_title_array(result['title'])
    end

    # Process content recursively
    if result['content'].is_a?(Array)
      result['content'] = process_content_array(result['content'])
    end

    result
  end

  def process_title_array(titles)
    # Titles are already in format [{ 'ja' => '...', 'en' => '...' }]
    # Just ensure they have translations
    titles.map do |title|
      if title.is_a?(Hash)
        if title['ja'] && !title['en']
          translation = find_translation(title['ja'])
          title['en'] = translation if translation
        end
        title
      else
        # Convert string to hash
        { 'ja' => title, 'en' => find_translation(title) }.compact
      end
    end
  end

  def process_content_array(content)
    content.map do |item|
      process_content_item(item)
    end
  end

  def process_content_item(item)
    return item unless item.is_a?(Hash)

    result = item.dup

    # Process title field (article captions like （目的）)
    if result['title']
      result['title'] = process_bilingual_string(result['title'])
    end

    # Process label_en field
    if result['label'] && !result['label_en']
      result['label_en'] = find_translation(result['label'])
    end

    # Process nested content
    if result['content'].is_a?(Array)
      result['content'] = result['content'].map do |sub_item|
        if sub_item.is_a?(String)
          process_bilingual_string(sub_item)
        elsif sub_item.is_a?(Hash)
          process_content_item(sub_item)
        else
          sub_item
        end
      end
    end

    result
  end

  def process_bilingual_string(str)
    return str unless str.is_a?(String)

    translation = find_translation(str)

    if translation
      { 'ja' => str, 'en' => translation }
    else
      str
    end
  end
end

# Custom YAML formatting for cleaner output
class BilingualYAML
  def self.format_bilingual(yaml_str)
    # Post-process YAML to make bilingual content cleaner
    lines = yaml_str.lines
    result = []
    i = 0

    while i < lines.length
      line = lines[i]

      # Check if this is a bilingual string pattern
      if line.match?(/^\s*- ja: /) && i + 1 < lines.length
        next_line = lines[i + 1]
        if next_line.match?(/^\s*en: /)
          # Combine into single entry
          indent = line.match(/^(\s*)/)[1]
          ja_text = line.sub(/^\s*- ja: /, '').strip
          en_text = next_line.sub(/^\s*en: /, '').strip
          result << "#{indent}- ja: #{ja_text}\n"
          result << "#{indent}  en: #{en_text}\n"
          i += 2
          next
        end
      end

      result << line
      i += 1
    end

    result.join
  end
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  yaml_path = ARGV[0] || 'sources/legal-instruments/diet-foreign-exchange-and-foreign-trade-act.yml'
  tmx_path = ARGV[1] || 'reference-docs/9030.tmx'
  output_path = ARGV[2] || 'sources/legal-instruments/diet-foreign-exchange-and-foreign-trade-act-ja-en.yml'

  puts "Adding translations from #{tmx_path} to #{yaml_path}..."
  puts "Output will be written to #{output_path}"

  adder = TranslationAdder.new(tmx_path)
  adder.process_yaml(yaml_path, output_path)
end
