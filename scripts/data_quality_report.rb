#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'

data = YAML.load_file('sources/sanction-lists/foreign-user-list/20250929.yml')
entities = data['sanction_details']['entities']

puts '=== Data Quality Report ==='
puts "Total entities: #{entities.size}"

# Check IDs
ids = entities.map { |e| e['id'] }
puts "Unique IDs: #{ids.uniq.size}"
puts "ID format sample: #{ids.first(3).join(', ')}"

# Check country codes
with_country = entities.count { |e| e['country_code'] }
without_country = entities.count { |e| e['country_code'].nil? }
puts "Entities with country_code: #{with_country}"
puts "Entities without country_code: #{without_country}"

# Check reasons
with_reason = entities.count { |e| e['reason'] && !e['reason'].empty? }
without_reason = entities.count { |e| e['reason'].nil? || e['reason'].empty? }
puts "Entities with reason: #{with_reason}"
puts "Entities without reason: #{without_reason}"

# Check aliases
with_aliases = entities.count { |e| e['aliases'] && !e['aliases'].empty? }
puts "Entities with aliases: #{with_aliases}"

# Country distribution
puts
puts '=== Top 10 Countries ==='
country_counts = entities.group_by { |e| e['country_code'] }.transform_values(&:size)
country_counts.sort_by { |_, v| -v }.first(10).each do |code, count|
  puts "  #{code || 'nil'}: #{count}"
end

# WMD type distribution (from reasons)
puts
puts '=== WMD Type Distribution ==='
wmd_counts = Hash.new(0)
entities.each do |e|
  reasons = e['reason'] || []
  reasons.each do |r|
    en = r['en'] || ''
    if en.include?('nuclear')
      wmd_counts['Nuclear'] += 1
    elsif en.include?('missile')
      wmd_counts['Missile'] += 1
    elsif en.include?('biological')
      wmd_counts['Biological'] += 1
    elsif en.include?('chemical')
      wmd_counts['Chemical'] += 1
    elsif en.include?('conventional')
      wmd_counts['Conventional'] += 1
    end
  end
end
wmd_counts.sort_by { |_, v| -v }.each do |type, count|
  puts "  #{type}: #{count}"
end
