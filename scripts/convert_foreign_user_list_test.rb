#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'convert_foreign_user_list_to_yaml'

converter = ForeignUserListConverter.new(File.expand_path('../reference-docs/20250929_4.xlsx', __dir__))
expected = {
  297 => ['4.27 Co. Pyongyang Branch', '4.27貿易会社平壌支社', '4.27 Corporation'],
  475 => ['10th Research Institute of China Electronic Technology Group Corporation (CETC)',
          '中国電子科技集団公司第十研究所', 'CETC 10th Research Institute'],
  476 => ['13th Research Institute, 9th Academy, China Aerospace Science and Technology Corporation (CASC)',
          '中国航天科技集団公司第九研究院第十三研究所', '13th Institute'],
  477 => ['20th Research Institute of China Electronic Technology Group Corporation (CETC)',
          '中国電子科技集団公司第二十研究所', 'CETC 20th Research Institute']
}
expected.each do |number, (english, japanese, alias_name)|
  row = converter.send(:process_row, number + 1)
  raise "Wrong ID for authority row #{number + 1}" unless row['id'] == "jp.meti.ful.#{number}"
  raise "Wrong names for #{row['id']}: #{row['name'].inspect}" unless row['name'] == { 'en' => english, 'ja' => japanese }
  raise "Alias lost for #{row['id']}" unless row['aliases'].include?(alias_name)
end

layouts = {
  'Example Company' => { 'en' => 'Example Company' },
  '貿易会社' => { 'ja' => '貿易会社' },
  "貿易会社\nExample Company" => { 'ja' => '貿易会社', 'en' => 'Example Company' },
  "Example Company\n(貿易会社)" => { 'en' => 'Example Company', 'ja' => '貿易会社' },
  "4.27 Co.\r\n（貿易会社）" => { 'en' => '4.27 Co.', 'ja' => '貿易会社' }
}
layouts.each do |text, names|
  actual = converter.send(:build_name, text)
  raise "Wrong name layout #{text.inspect}: #{actual.inspect}" unless actual == names
end
puts "Passed #{expected.size} authority-row regressions and #{layouts.size} name layouts"
