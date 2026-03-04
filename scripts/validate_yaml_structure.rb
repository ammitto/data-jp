#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to validate generated YAML against example file
# Compares structure and content up to clause 6 (Article 6)

require 'yaml'
require 'json'

class YamlValidator
  def initialize(generated_path, example_path)
    @generated_path = generated_path
    @example_path = example_path
    @errors = []
    @warnings = []
  end

  def validate
    puts "Loading YAML files..."

    generated = load_yaml(@generated_path)
    example = load_yaml(@example_path)

    return false unless generated && example

    puts "\n=== Validating metadata ==="
    validate_metadata(generated, example)

    puts "\n=== Validating content structure (up to Article 6) ==="
    validate_content(generated, example)

    puts "\n=== Validation Results ==="
    if @errors.empty?
      puts "✅ All validations passed!"
      true
    else
      puts "❌ Validation failed with #{@errors.size} error(s):"
      @errors.each_with_index do |error, idx|
        puts "  #{idx + 1}. #{error}"
      end
      false
    end

    if @warnings.any?
      puts "\n⚠️  Warnings (#{@warnings.size}):"
      @warnings.each_with_index do |warning, idx|
        puts "  #{idx + 1}. #{warning}"
      end
    end
  end

  private

  def load_yaml(path)
    content = File.read(path)
    # Skip comment lines at the beginning
    content = content.lines.drop_while { |l| l.start_with?('#') }.join
    YAML.safe_load(content, permitted_classes: [Date, Time, Symbol])
  rescue => e
    @errors << "Failed to load #{path}: #{e.message}"
    nil
  end

  def validate_metadata(generated, example)
    # Check required fields
    required_fields = %w[id type authority document_id lang]

    required_fields.each do |field|
      if generated[field].nil?
        @errors << "Missing required field: #{field}"
      elsif example[field] && generated[field] != example[field]
        @warnings << "Field '#{field}' differs: generated='#{generated[field]}' vs example='#{example[field]}'"
      end
    end

    # Check title structure
    if generated['title'].is_a?(Array)
      puts "  ✓ Title is an array with #{generated['title'].size} element(s)"
    else
      @errors << "Title should be an array"
    end

    # Check approval_history
    if generated['approval_history'].is_a?(Array)
      puts "  ✓ approval_history is an array with #{generated['approval_history'].size} entries"

      # Validate format of each entry
      generated['approval_history'].each_with_index do |entry, idx|
        unless entry.is_a?(String) && entry.include?('施行')
          @warnings << "approval_history[#{idx}] may not be in expected format: #{entry[0..50]}..."
        end
      end
    else
      @errors << "approval_history should be an array"
    end
  end

  def validate_content(generated, example)
    gen_content = generated['content']
    ex_content = example['content']

    return @errors << "Missing content in generated file" unless gen_content
    return @errors << "Missing content in example file" unless ex_content

    # Find Chapter 1 in both
    gen_chapter1 = find_chapter(gen_content, 1)
    ex_chapter1 = find_chapter(ex_content, 1)

    return @errors << "Chapter 1 not found in generated file" unless gen_chapter1
    return @errors << "Chapter 1 not found in example file" unless ex_chapter1

    puts "  Found Chapter 1 in both files"

    # Compare chapters
    validate_chapter(gen_chapter1, ex_chapter1)
  end

  def find_chapter(content, index)
    content.find { |c| c['type'] == 'chapter' && c['index'].to_s == index.to_s }
  end

  def validate_chapter(gen_chapter, ex_chapter)
    # Compare chapter metadata
    if gen_chapter['label'] != ex_chapter['label']
      @errors << "Chapter label differs: #{gen_chapter['label']} vs #{ex_chapter['label']}"
    else
      puts "  ✓ Chapter label matches: #{gen_chapter['label']}"
    end

    if gen_chapter['title'] != ex_chapter['title']
      @errors << "Chapter title differs: #{gen_chapter['title']} vs #{ex_chapter['title']}"
    else
      puts "  ✓ Chapter title matches: #{gen_chapter['title']}"
    end

    # Compare clauses up to Article 6
    gen_clauses = gen_chapter['content'].select { |c| c['type'] == 'clause' }
    ex_clauses = ex_chapter['content'].select { |c| c['type'] == 'clause' }

    # Only compare up to clause 6 (using string indices)
    %w[1 2 3 4 5 6].each do |clause_num|
      ex_clause = ex_clauses.find { |c| c['index'].to_s == clause_num }

      # Skip if clause doesn't exist in example (no need to validate)
      if ex_clause.nil?
        gen_clause = gen_clauses.find { |c| c['index'].to_s == clause_num || c['index'].to_s.start_with?("#{clause_num}-") }
        puts "  ⚠ Clause #{clause_num} not in example (skipping)" if gen_clause.nil?
        next
      end

      # Find generated clause by label (more stable than index for range articles)
      gen_clause = gen_clauses.find { |c| c['label'] == ex_clause['label'] }

      # Only error if clause exists in example but not in generated
      if gen_clause.nil?
        @errors << "Clause #{clause_num} (#{ex_clause['label']}) not found in generated file"
        next
      end

      puts "\n  Validating Clause #{clause_num} (#{gen_clause['label']})..."
      validate_clause(gen_clause, ex_clause, clause_num)
    end
  end

  def validate_clause(gen_clause, ex_clause, clause_num)
    # Compare label
    if gen_clause['label'] != ex_clause['label']
      @errors << "Clause #{clause_num} label differs: #{gen_clause['label']} vs #{ex_clause['label']}"
    else
      puts "    ✓ Label matches: #{gen_clause['label']}"
    end

    # Compare title (may have quotes difference)
    gen_title = normalize_string(gen_clause['title'])
    ex_title = normalize_string(ex_clause['title'])
    if gen_title != ex_title
      @errors << "Clause #{clause_num} title differs: #{gen_title} vs #{ex_title}"
    else
      puts "    ✓ Title matches: #{gen_title}" if gen_title
    end

    # Compare content
    validate_clause_content(gen_clause['content'], ex_clause['content'], clause_num)
  end

  def validate_clause_content(gen_content, ex_content, clause_num)
    return unless gen_content && ex_content

    # Track position in both arrays
    gen_idx = 0
    ex_idx = 0

    while gen_idx < gen_content.length && ex_idx < ex_content.length
      gen_item = gen_content[gen_idx]
      ex_item = ex_content[ex_idx]

      # Check if both are strings
      if gen_item.is_a?(String) && ex_item.is_a?(String)
        gen_normalized = normalize_string(gen_item)
        ex_normalized = normalize_string(ex_item)

        if gen_normalized == ex_normalized
          puts "    ✓ Text matches: #{truncate(gen_normalized, 50)}"
        else
          @errors << "Clause #{clause_num} text differs at position #{gen_idx}:\n      Generated: #{truncate(gen_normalized, 80)}\n      Example:   #{truncate(ex_normalized, 80)}"
        end
        gen_idx += 1
        ex_idx += 1

      # Check if both are hashes (numbered-list, etc.)
      elsif gen_item.is_a?(Hash) && ex_item.is_a?(Hash)
        if gen_item['type'] == ex_item['type']
          validate_list(gen_item, ex_item, clause_num)
        else
          @errors << "Clause #{clause_num} type differs: #{gen_item['type']} vs #{ex_item['type']}"
        end
        gen_idx += 1
        ex_idx += 1

      # Type mismatch
      else
        gen_type = gen_item.is_a?(Hash) ? gen_item['type'] : 'string'
        ex_type = ex_item.is_a?(Hash) ? ex_item['type'] : 'string'
        @errors << "Clause #{clause_num} item type mismatch at position #{gen_idx}: generated=#{gen_type}, example=#{ex_type}"

        # Try to resync
        if gen_item.is_a?(String)
          gen_idx += 1
        elsif ex_item.is_a?(String)
          ex_idx += 1
        else
          gen_idx += 1
          ex_idx += 1
        end
      end
    end

    # Check for remaining items
    if gen_idx < gen_content.length
      remaining = gen_content[gen_idx..].map { |i| i.is_a?(Hash) ? i['type'] : 'string' }
      puts "    ⚠ Generated has #{remaining.size} additional item(s): #{remaining.join(', ')}"
    end

    if ex_idx < ex_content.length
      remaining = ex_content[ex_idx..].map { |i| i.is_a?(Hash) ? i['type'] : 'string' }
      puts "    ⚠ Example has #{remaining.size} additional item(s): #{remaining.join(', ')}"
    end
  end

  def validate_list(gen_list, ex_list, clause_num)
    # Compare list metadata
    if gen_list['index'] != ex_list['index']
      @warnings << "Clause #{clause_num} list index differs: #{gen_list['index']} vs #{ex_list['index']}"
    end

    # Compare list items
    gen_items = gen_list['content'] || []
    ex_items = ex_list['content'] || []

    # For Article 6, compare all items in example
    # The example has items 1-17, but we only validate up to what's in example
    ex_items_to_check = ex_items.size

    puts "    ✓ Found numbered-list with #{gen_items.size} items (example has #{ex_items.size})"

    # Validate each list item
    ex_items.each_with_index do |ex_item, idx|
      gen_item = gen_items.find { |i| i['index'].to_s == ex_item['index'].to_s }

      unless gen_item
        @errors << "Clause #{clause_num} list-item #{ex_item['index']} not found in generated"
        next
      end

      validate_list_item(gen_item, ex_item, clause_num)
    end
  end

  def validate_list_item(gen_item, ex_item, clause_num)
    item_num = gen_item['index']

    # Compare label
    if gen_item['label'] != ex_item['label']
      @errors << "Clause #{clause_num} item #{item_num} label differs: #{gen_item['label']} vs #{ex_item['label']}"
    end

    # Compare content
    gen_content = gen_item['content'] || []
    ex_content = ex_item['content'] || []

    # For items with nested lists (like item 7), handle specially
    ex_content.each_with_index do |ex_c, idx|
      gen_c = gen_content[idx]

      if ex_c.is_a?(String) && gen_c.is_a?(String)
        gen_normalized = normalize_string(gen_c)
        ex_normalized = normalize_string(ex_c)

        if gen_normalized != ex_normalized
          @errors << "Clause #{clause_num} item #{item_num} content[#{idx}] differs:\n      Generated: #{truncate(gen_normalized, 80)}\n      Example:   #{truncate(ex_normalized, 80)}"
        end
      elsif ex_c.is_a?(Hash) && gen_c.is_a?(Hash) && ex_c['type'] == 'numbered-list'
        # Nested list (e.g., item 7's イ, ロ, ハ, ニ)
        puts "      ✓ Item #{item_num} has nested list with #{gen_c['content']&.size || 0} subitems"

        # Compare nested items
        (ex_c['content'] || []).each do |ex_subitem|
          gen_subitem = (gen_c['content'] || []).find { |si| si['index'].to_s == ex_subitem['index'].to_s }
          if gen_subitem
            # Compare subitem content
            ex_sub_content = ex_subitem['content']&.first
            gen_sub_content = gen_subitem['content']&.first

            if ex_sub_content.is_a?(String) && gen_sub_content.is_a?(String)
              if normalize_string(gen_sub_content) == normalize_string(ex_sub_content)
                puts "        ✓ Subitem #{ex_subitem['label']} content matches"
              else
                @errors << "Clause #{clause_num} item #{item_num} subitem #{ex_subitem['label']} content differs"
              end
            end
          else
            @errors << "Clause #{clause_num} item #{item_num} subitem #{ex_subitem['index']} not found"
          end
        end
      elsif ex_c.is_a?(String) && gen_c.nil?
        @errors << "Clause #{clause_num} item #{item_num} missing content at index #{idx}"
      end
    end
  end

  def normalize_string(str)
    return nil unless str
    # Remove surrounding quotes if present
    str = str.gsub(/\A"/, '').gsub(/"\z/, '')
    # Normalize whitespace
    str.strip
  end

  def truncate(str, max_len)
    return str if str.nil? || str.length <= max_len
    str[0..max_len - 3] + '...'
  end
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  generated_path = ARGV[0] || 'sources/legal-instruments/diet-foreign-exchange-and-foreign-trade-act.yml'
  example_path = ARGV[1] || 'sources/legal-instruments/diet-foreign-exchange-and-foreign-trade-act-example.yml'

  puts "=" * 60
  puts "YAML Structure Validator"
  puts "=" * 60
  puts "Generated: #{generated_path}"
  puts "Example:   #{example_path}"
  puts "=" * 60

  validator = YamlValidator.new(generated_path, example_path)
  success = validator.validate

  exit(success ? 0 : 1)
end
