#!/usr/bin/env ruby
# frozen_string_literal: true

require 'ammitto'
require 'ammitto/data/japan/validator'
require 'json'

sources = File.expand_path(ARGV.fetch(0, '../sources'), __dir__)
directories = %w[sanction-lists legal-instruments].map { |name| File.join(sources, name) }
files = directories.flat_map do |directory|
  paths = Dir.glob(File.join(directory, '**', '*.{yml,yaml}'))
             .reject { |path| File.basename(path).start_with?('_') }
  abort "No source documents found: #{directory}" if paths.empty?

  paths
end
files += %w[document-types organizations].map do |name|
  File.join(sources, 'supporting', "#{name}.yml")
end

report = Ammitto::Data::Japan::Validator.new.validate_files(files.sort)
puts JSON.pretty_generate(report)
exit(report[:valid] ? 0 : 1)
