# frozen_string_literal: true

module MofSanctions
  # Entity model conforming to jp-announcement.yml schema
  # Represents a sanctioned entity (individual or organization)
  class Entity
    # Required fields
    attr_accessor :id, :type, :effective_date, :sanction_list

    # Name as multilingual hash
    attr_reader :name

    # Optional fields (matching schema)
    attr_accessor :sanction_list_en, :country, :address,
                  :date_of_birth, :place_of_birth, :nationality,
                  :honorific, :gender,
                  :source_url, :list_date

    # Title as multilingual hash (like name)
    attr_reader :title

    # Array fields (schema: arrays of objects or strings)
    attr_reader :aliases, :reason, :measures, :phones, :fax

    # Identification object (schema: { passport, national_id, tax_id })
    attr_accessor :identification

    # New fields
    attr_reader :remarks
    attr_accessor :un_designation_date

    def initialize(attributes = {})
      @name = {}
      @title = {}
      @aliases = []
      @reason = []
      @remarks = []
      @measures = []
      @phones = []
      @fax = []
      @identification = {}
      @un_designation_date = nil

      attributes.each do |key, value|
        instance_variable_set("@#{key}", value) if respond_to?("#{key}=")
      end
    end

    # Convert to Hash for YAML serialization per schema
    def to_h
      hash = {}

      # Required fields
      hash["id"] = id if id
      hash["name"] = compact_hash(@name)
      hash["type"] = type
      hash["effective_date"] = effective_date if effective_date
      hash["sanction_list"] = sanction_list

      # Optional fields
      hash["sanction_list_en"] = sanction_list_en if sanction_list_en && !sanction_list_en.empty?
      hash["country"] = country if country && !country.empty?
      hash["address"] = address if address && address != "不明"
      hash["title"] = compact_hash(@title) if @title && @title.values.any? { |v| v && !v.empty? }
      hash["date_of_birth"] = date_of_birth if date_of_birth && !date_of_birth.empty?
      hash["place_of_birth"] = place_of_birth if place_of_birth && !place_of_birth.empty?
      hash["nationality"] = nationality if nationality && !nationality.empty?
      hash["honorific"] = honorific if honorific && !honorific.empty?
      hash["list_date"] = list_date if list_date && !list_date.empty?
      hash["source_url"] = source_url if source_url

      # Array fields
      hash["aliases"] = aliases if aliases.any?
      hash["reason"] = reason if reason.any?
      hash["measures"] = measures if measures.any?
      hash["phones"] = phones if phones.any?
      hash["fax"] = fax if fax.any?

      # Identification object
      hash["identification"] = compact_hash(@identification) if @identification && @identification.values.any? { |v| v && !v.empty? }

      # Remarks
      hash["remarks"] = remarks if remarks.any?

      # UN designation date
      hash["un_designation_date"] = un_designation_date if un_designation_date

      hash
    end

    # === NAME ===
    def add_name(lang, value)
      return if value.nil? || value.to_s.strip.empty?
      @name[lang.to_s] = value.to_s.strip
    end

    # === ALIASES (simple strings per schema) ===
    # Adds a single alias (splitting is handled by FieldMapping.split_aliases)
    def add_alias(alias_name)
      return if alias_name.nil? || alias_name.to_s.strip.empty?
      clean = alias_name.to_s.strip
      return if clean.empty? || clean == "不明"
      @aliases << clean unless @aliases.include?(clean)
    end

    # === REASON (array of multilingual strings) ===
    def add_reason(ja:, en: nil)
      return if ja.nil? || ja.to_s.strip.empty?
      entry = { "ja" => ja.to_s.strip }
      entry["en"] = en.to_s.strip if en && !en.to_s.strip.empty?
      @reason << entry
    end

    # === REMARKS (array of multilingual strings) ===
    def add_remark(ja:, en: nil)
      return if ja.nil? || ja.to_s.strip.empty?
      entry = { "ja" => ja.to_s.strip }
      entry["en"] = en.to_s.strip if en && !en.to_s.strip.empty?
      @remarks << entry
    end

    # === MEASURES ===
    def add_measure(types:, ja: nil, en: nil)
      return if types.nil? || types.empty?
      measure = { "type" => Array(types) }
      measure["ja"] = ja if ja && !ja.to_s.strip.empty?
      measure["en"] = en if en && !en.to_s.strip.empty?
      @measures << measure
    end

    # === TITLE (multilingual object per schema) ===
    def add_title(lang, value)
      return if value.nil? || value.to_s.strip.empty?
      clean = value.to_s.strip
      return if clean == "不明"
      @title[lang.to_s] = clean
    end

    def set_title(value)
      add_title("ja", value)
    end

    # === IDENTIFICATION (object with passport/national_id/tax_id) ===
    def add_identifier(id_type, number)
      return if number.nil? || number.to_s.strip.empty?
      return if number.to_s.strip == "不明"
      @identification ||= {}
      case id_type
      when "passport"
        @identification["passport"] = number.to_s.strip
      when "id", "id-card"
        @identification["national_id"] = number.to_s.strip
      else
        @identification["other"] = number.to_s.strip
      end
    end

    # === PHONES ===
    def add_phone(number)
      return if number.nil? || number.to_s.strip.empty?
      return if number.to_s.strip == "不明"
      clean = number.to_s.strip
      @phones << clean unless @phones.include?(clean)
    end

    # === FAX ===
    def add_fax(number)
      return if number.nil? || number.to_s.strip.empty?
      return if number.to_s.strip == "不明"
      clean = number.to_s.strip
      @fax << clean unless @fax.include?(clean)
    end

    # Check if entity has minimum required data
    def valid?
      (@name["ja"] || @name["en"]) && type && sanction_list
    end

    private

    def compact_hash(hash)
      return nil unless hash
      result = hash.reject { |_, v| v.nil? || v.to_s.strip.empty? }
      result.empty? ? nil : result
    end
  end
end
