# frozen_string_literal: true

module MofSanctions
  # Field mapping configuration for MOF sanctions data
  # Maps Japanese Excel column names to schema fields with configurable handlers
  class FieldMapping
    # ============================================================
    # FIELD HANDLERS
    # Each handler defines how to process a specific field type
    # ============================================================

    # Handler registry - maps handler names to callable methods
    HANDLERS = {
      # Simple string field (e.g., address, nationality)
      string: ->(entity, field, value, **_opts) {
        entity.send("#{field}=", value) unless value == "不明"
      },

      # Multilingual name field
      name: ->(entity, _field, value, lang:, **_opts) {
        entity.add_name(lang, value)
      },

      # Multilingual title field
      # Auto-detects Japanese and English parts if lang not specified
      # Patterns: "日本語 English" or "「日本語」 "English""
      title: ->(entity, _field, value, lang: nil, **_opts) {
        if lang
          entity.add_title(lang, value)
        else
          # Auto-detect and split Japanese/English parts
          split_multilingual_title(value).each do |l, v|
            entity.add_title(l, v)
          end
        end
      },

      # Date of birth with special parsing
      date_of_birth: ->(entity, _field, value, parser:, **_opts) {
        entity.date_of_birth = parser.call(value)
      },

      # Array field with configurable separator (aliases)
      # Handles Japanese ten (、), comma, and semicolon
      aliases: ->(entity, _field, value, **_opts) {
        split_aliases(value).each { |alias_name| entity.add_alias(alias_name) }
      },

      # Remarks (multilingual array)
      remarks: ->(entity, _field, value, **_opts) {
        entity.add_remark(ja: value)
      },

      # Reason (multilingual array)
      reason: ->(entity, _field, value, **_opts) {
        entity.add_reason(ja: value)
      },

      # Identifier (polymorphic)
      identifier: ->(entity, _field, value, id_type:, **_opts) {
        entity.add_identifier(id_type, value)
      },

      # Phone numbers
      phones: ->(entity, _field, value, **_opts) {
        entity.add_phone(value)
      },

      # Fax numbers
      fax: ->(entity, _field, value, **_opts) {
        entity.add_fax(value)
      },

      # List date with Excel serial date support
      list_date: ->(entity, _field, value, parser:, **_opts) {
        entity.list_date = parser.call(value)
      },

      # UN designation date
      un_designation_date: ->(entity, _field, value, parser:, **_opts) {
        entity.un_designation_date = parser.call(value)
      },

      # Gazette date (returns value for effective_date)
      gazette_date: ->(_entity, _field, value, **_opts) {
        { gazette_date: value }
      },

      # Gazette number (entity ID component)
      gazette_number: ->(_entity, _field, value, **_opts) {
        { gazette_number: value }
      }
    }.freeze

    # ============================================================
    # COLUMN NAME PATTERNS
    # Maps column name patterns to field configurations
    # Patterns can be exact strings or regex
    # ============================================================

    # Default field mappings (applies to all sheets)
    DEFAULT_FIELD_MAPPINGS = {
      # === CORE FIELDS ===
      "告示日付" => { handler: :gazette_date },
      "告示番号" => { handler: :gazette_number },
      "日本語表記" => { handler: :name, lang: "ja" },
      "英語表記" => { handler: :name, lang: "en" },

      # === DATE OF BIRTH ===
      "生年月日" => { handler: :date_of_birth, parser: :parse_date_of_birth },

      # === ADDRESS VARIANTS ===
      "住所" => { handler: :string, field: :address },
      "所在地" => { handler: :string, field: :address },
      "住所・所在地" => { handler: :string, field: :address },
      "住所等" => { handler: :string, field: :address },
      "活動地域・住所" => { handler: :string, field: :address },

      # === INDIVIDUAL FIELDS ===
      "出生地" => { handler: :string, field: :place_of_birth },
      "出生地・出身地" => { handler: :string, field: :place_of_birth },
      "国籍" => { handler: :string, field: :nationality },

      # === TITLE VARIANTS ===
      "役職" => { handler: :title, lang: "ja" },
      "肩書等" => { handler: :title, lang: "ja" },
      "肩書" => { handler: :title, lang: "ja" },
      "称号" => { handler: :title },  # Contains titles like "元首", "教授" - auto-split JA/EN

      # === ALIASES VARIANTS ===
      "別名" => { handler: :aliases },
      "別称・別名" => { handler: :aliases },
      "別称" => { handler: :aliases },
      "別名・別称" => { handler: :aliases },
      "確定に十分でない別名" => { handler: :aliases },
      "確定可能な別名" => { handler: :aliases },
      "旧称" => { handler: :aliases },
      "別称・旧称" => { handler: :aliases },
      "過去の別名" => { handler: :aliases },
      "以前の別名" => { handler: :aliases },
      "旧称・以前の呼称" => { handler: :aliases },

      # === IDENTIFIERS ===
      "旅券番号" => { handler: :identifier, id_type: "passport" },
      "身分登録番号" => { handler: :identifier, id_type: "id" },
      "身分証番号" => { handler: :identifier, id_type: "id-card" },
      "ID番号" => { handler: :identifier, id_type: "id" },

      # === CONTACT INFO ===
      "電話" => { handler: :phones },
      "電話番号" => { handler: :phones },
      "FAX" => { handler: :fax },

      # === DATES ===
      "リスト掲載日" => { handler: :list_date, parser: :parse_list_date },
      "国連制裁委員会による指定日" => { handler: :un_designation_date, parser: :parse_list_date },

      # === REMARKS ===
      "その他の情報" => { handler: :remarks },
      "詳細" => { handler: :remarks },

      # === REASON ===
      "決議1483上の根拠" => { handler: :reason },
      "指定の根拠" => { handler: :reason },
    }.freeze

    # ============================================================
    # SHEET-SPECIFIC OVERRIDES
    # Per-sheet column name mappings that override defaults
    # ============================================================

    SHEET_SPECIFIC_MAPPINGS = {
      # Iraq sheets have combined address column
      "5.イラク前政権関係者等（Ⅰ）" => {
        "所在地・住所" => { handler: :string, field: :address },
        "所在地・住所 登録された事務所の住所" => { handler: :string, field: :address },
        "詳細" => { handler: :remarks }
      },
      "6.イラク前政権関係者等 (Ⅱ)" => {
        "所在地・住所" => { handler: :string, field: :address },
        "所在地・住所 登録された事務所の住所" => { handler: :string, field: :address },
        "詳細" => { handler: :remarks }
      },
      "7.イラク前政権関係者等 (Ⅲ)" => {
        "所在地・住所" => { handler: :string, field: :address },
        "所在地・住所 登録された事務所の住所" => { handler: :string, field: :address },
        "詳細" => { handler: :remarks }
      },

      # Add more sheet-specific mappings as needed
    }.freeze

    # ============================================================
    # REGEX PATTERNS FOR FUZZY MATCHING
    # Used when exact match fails
    # ============================================================

    PATTERN_MAPPINGS = [
      # Address patterns
      [/所在地.*住所/, { handler: :string, field: :address }],
      [/住所.*所在地/, { handler: :string, field: :address }],

      # Details/remarks patterns
      [/詳細/, { handler: :remarks }],

      # Alias patterns
      [/別名/, { handler: :aliases }],
      [/別称/, { handler: :aliases }],
      [/旧称/, { handler: :aliases }]
    ].freeze

    # ============================================================
    # HELPER METHODS
    # ============================================================

    # Split aliases by multiple separators
    # Handles:
    # - Japanese ten (、), full-width semicolon (；), half-width semicolon (;)
    # - Newlines
    # - Labels like （別称）, （旧称）, （別名） act as separators but are KEPT with the following alias
    # - Comma in English names (e.g., "Name1, Name2" → "Name1", "Name2")
    # - Japanese text followed by English (e.g., "日本語 English" → "日本語", "English")
    # Preserves English company names like "COMPANY, LTD"
    def self.split_aliases(value)
      return [] if value.nil? || value.to_s.strip.empty?

      str = value.to_s.strip

      # First, insert a marker before each label, then split by the marker
      # This keeps the label with the following content
      label_pattern = /（(?:別称|旧称|別名|別名・旧称|旧称・別名)）/
      # Insert \x00 marker before labels (except at the very start)
      marked = str.gsub(/\s*(#{label_pattern.source})/, "\x00\\1")

      # Split by the marker
      parts = marked.split("\x00").map(&:strip)

      # Then split each part by Japanese ten (、), full-width semicolon (；), half-width semicolon (;), newline
      result = []
      parts.each do |part|
        next if part.empty?
        subparts = part.split(/[、；;\n]+/).map(&:strip)
        result.concat(subparts)
      end

      # Handle Japanese followed by English (e.g., "日本語 English Name" → "日本語", "English Name")
      # And comma-separated English names
      final_result = []
      result.each do |part|
        next if part.empty?

        # Check for pattern: Japanese text followed by English text
        # Pattern: CJK characters followed by space then ASCII letters
        if part.match?(/^[\p{Hiragana}\p{Katakana}\p{Han}・\s]+\s+[A-Z]/)
          # Split Japanese from English
          match = part.match(/^([\p{Hiragana}\p{Katakana}\p{Han}・\s]+)\s+(.+)$/)
          if match
            ja_part = match[1].strip
            en_part = match[2].strip
            final_result << ja_part unless ja_part.empty?

            # Now split the English part by comma
            en_aliases = split_english_aliases(en_part)
            final_result.concat(en_aliases)
            next
          end
        end

        # Check if this part contains comma-separated English names
        if part.match?(/[A-Z].*,\s*[A-Z]/)
          en_aliases = split_english_aliases(part)
          final_result.concat(en_aliases)
        else
          final_result << part
        end
      end

      # Filter empty and duplicates
      final_result.reject { |a| a.empty? || a == "不明" }.uniq
    end

    # Split English aliases by comma, preserving company suffixes
    def self.split_english_aliases(en_part)
      return [en_part] unless en_part.include?(",")

      # Split by ", " but preserve "COMPANY, LTD" patterns
      # Strategy: split by ", " followed by a word that looks like a name start
      en_part.split(/,\s+(?=[A-Z][A-Z\s\-']*(?:TRADING|COMPANY|LTD|INC|CORP|CO|LTD\.|LLC|SA|AG|GMBH|BV|NV|BANK|CORPORATION|INDUSTRY|GROUP))/i)
        .map(&:strip)
        .reject(&:empty?)
    end

    # Split a title value that may contain both Japanese and English parts
    # Patterns handled:
    # - "日本語 English" → { ja: "日本語", en: "English" }
    # - "「日本語」 "English"" → { ja: "「日本語」", en: "\"English\"" }
    # - "日本語\nEnglish" (multiline) → { ja: "日本語", en: "English" }
    def self.split_multilingual_title(value)
      return {} if value.nil? || value.to_s.strip.empty?

      str = value.to_s.strip

      # Check for multiline format (newline separator)
      if str.include?("\n")
        lines = str.split("\n").map(&:strip).reject(&:empty?)
        result = {}
        lines.each do |line|
          if line.match?(/^[\p{Hiragana}\p{Katakana}\p{Han}]/)
            result["ja"] = line
          elsif line.match?(/^[A-Za-z"'\(]/)
            result["en"] = line
          end
        end
        return result if result.size > 1
      end

      # Pattern 1: "日本語 English" - space separated
      # Find where Japanese ends and English begins
      # Japanese text: Hiragana, Katakana, Han, full-width punctuation
      # English text: ASCII letters, quotes, parentheses

      # Try to find the boundary between Japanese and English
      # Look for pattern: Japanese text followed by space followed by non-Japanese text
      match = str.match(/^([\p{Hiragana}\p{Katakana}\p{Han}\s「」『』〈〉《》【】〔〕()（）・]+)\s+([A-Za-z"'\(\[][^\p{Hiragana}\p{Katakana}\p{Han}]*)$/)

      if match
        ja_part = match[1].strip
        en_part = match[2].strip
        return { "ja" => ja_part, "en" => en_part } unless ja_part.empty? || en_part.empty?
      end

      # Pattern 2: "「日本語」 "English"" - quote separated (handles curly quotes)
      match = str.match(/^(「[^」]+」)\s*[""]([^""]+)[""]/)
      if match
        return { "ja" => match[1], "en" => match[2] }
      end

      # Pattern 2b: "「日本語」 "English"" - with regular quotes
      match = str.match(/^(「[^」]+」)\s*"([^"]+)"/)
      if match
        return { "ja" => match[1], "en" => match[2] }
      end

      # Pattern 3: Mixed with specific format "日本語 Former English Title"
      # Look for common English title words
      english_indicators = %w[Former Acting President Minister Head Director General Deputy Secretary Council Republic of the and]
      words = str.split(/\s+/)

      # Find the first English word that looks like a title start
      en_start_idx = nil
      words.each_with_index do |word, idx|
        next if idx == 0
        # Check if this word is an English title indicator
        if english_indicators.any? { |ind| word.include?(ind) } || word.match?(/^[A-Z][a-z]+$/)
          # Check if previous words were Japanese
          prev_text = words[0..idx-1].join(" ")
          if prev_text.match?(/[\p{Hiragana}\p{Katakana}\p{Han}]/)
            en_start_idx = idx
            break
          end
        end
      end

      if en_start_idx
        ja_part = words[0..en_start_idx-1].join(" ").strip
        en_part = words[en_start_idx..-1].join(" ").strip
        return { "ja" => ja_part, "en" => en_part }
      end

      # Fallback: if contains Japanese, treat as Japanese only
      if str.match?(/[\p{Hiragana}\p{Katakana}\p{Han}]/)
        { "ja" => str }
      else
        { "en" => str }
      end
    end

    # Get field mapping for a column header
    # Returns { handler: ..., **options } or nil
    def self.get_mapping(sheet_name, column_header)
      return nil if column_header.nil?

      # Clean the header for matching
      clean_header = column_header.to_s.gsub(/[\s\u3000]+/, " ").strip

      # 1. Check sheet-specific mappings first
      sheet_mappings = SHEET_SPECIFIC_MAPPINGS[sheet_name]
      if sheet_mappings
        mapping = sheet_mappings[clean_header]
        return mapping if mapping
      end

      # 2. Check default mappings
      mapping = DEFAULT_FIELD_MAPPINGS[clean_header]
      return mapping if mapping

      # 3. Try pattern matching for fuzzy matches
      PATTERN_MAPPINGS.each do |pattern, config|
        return config if clean_header.match?(pattern)
      end

      nil
    end

    # Determine entity type from sheet name
    def self.determine_entity_type(sheet_name)
      if sheet_name.include?("個人")
        :individual
      elsif sheet_name.include?("団体") || sheet_name.include?("銀行")
        :organization
      elsif sheet_name.include?("リビア") || sheet_name.include?("コンゴ")
        # Libya and Congo sheets contain organizations
        :organization
      else
        # Unknown - will be determined by row content (e.g., presence of date_of_birth)
        :unknown
      end
    end

    # Apply a field mapping to an entity
    # Returns nil, or a hash with gazette_date/gazette_number
    def self.apply_mapping(entity, mapping, value, parser_instance)
      return nil if mapping.nil? || value.nil?

      handler_name = mapping[:handler]
      handler = HANDLERS[handler_name]
      return nil if handler.nil?

      # Prepare options for handler
      opts = mapping.dup
      opts.delete(:handler)

      # Resolve parser method references
      if opts[:parser].is_a?(Symbol)
        opts[:parser] = parser_instance.method(opts[:parser])
      end

      # Call the handler
      handler.call(entity, mapping[:field], value, **opts)
    end
  end
end
