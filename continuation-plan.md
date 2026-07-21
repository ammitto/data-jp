# MOF Sanctions Parser - Continuation Plan

## Status: COMPLETED

## Overview

This document tracks the implementation status and remaining work for the MOF (Ministry of Finance) asset freeze sanctions parser.

## Implementation Status

### Completed
- [x] Basic parser structure (`lib/mof_sanctions/`)
- [x] Entity model (`lib/mof_sanctions/entity.rb`)
- [x] Field mapping configuration (`lib/mof_sanctions/field_mapping.rb`)
- [x] Main parser (`lib/mof_sanctions/parser.rb`)
- [x] CLI script (`scripts/parse_mof_sanctions.rb`)
- [x] Download script (`scripts/download_mof_sanctions.rb`)
- [x] Entity ID format: `jp.mof.{list-slug}.{entity-number}`
- [x] Title field: multilingual object `{ ja: ..., en: ... }`
- [x] Position field: removed (merged into title)
- [x] Aliases: split by semicolon,- [x] Filter "不明" from title, place_of_birth, nationality, honorific
- [x] "告示番号" used as entity ID number (not in reasons)
- [x] Removed `source_file` from entity level
- [x] Directory structure: `{NN}-{slug}/YYYYMMDD.yml`
- [x] Date of birth: Excel serial date parsing and Japanese year format
- [x] **Remarks field**: Added `remarks` field to entity model
- [x] **"その他の情報" field**: Mapped to `remarks`, not `reason`
- [x] **UN designation date column**: Parsed as date field `un_designation_date`
- [x] **Excel serial date conversion**: Applied conversion to ALL date fields
- [x] **Entity type detection**: Content-based detection using `date_of_birth` field
- [x] **Configurable field mapping system**: Refactored to data-driven architecture
- [x] **"称号" field**: Mapped to `title` (not `honorific`)
- [x] **Sheet titles**: English titles now use comprehensive `SANCTION_list_names_EN` mapping
- [x] **Entity title splitting**: Works correctly - splits Japanese/English parts
- [x] **Sheet name lookup**: Fixed `.strip` on sheet name in `parse_sheet` method
- [x] **Entity ID cleaning**: Strip `*`, `(`, `)` from gazette_number in entity IDs
- [x] **Alias splitting**: Split by full-width semicolon (；), newline, and labels (（別称）, （旧称）) - labels preserved

### Not Started
- [ ] RSpec tests for parser
- [ ] RSpec tests for entity model
- [ ] RSpec tests for field mapping
- [ ] Documentation in README.adoc
- [ ] Update docs/ with MOF parser documentation

## Architecture Refactoring

### Configurable Field Mapping System

The field mapping system has been refactored to be **configurable** rather than hardcoded:

```
lib/mof_sanctions/field_mapping.rb
├── HANDLERS              # Lambda handlers for each field type
├── DEFAULT_FIELD_MAPPINGS # Default column name → field configurations
├── SHEET_SPECIFIC_MAPPINGS # Per-sheet overrides
├── PATTERN_MAPPINGS      # Regex patterns for fuzzy matching
└── Helper methods
    ├── split_aliases()    # Handles Japanese ten (、), comma, semicolon
    ├── split_multilingual_title() # Splits Japanese/English title parts
    ├── get_mapping()      # Look up mapping for a column
    ├── determine_entity_type() # Sheet-level type detection
    └── apply_mapping()    # Apply handler to entity
```

### Key Features

1. **Handler Registry**: Each field type has a lambda handler
   - `string`: Simple string fields (address, nationality)
   - `name`: Multilingual name
   - `title`: Multilingual title
   - `aliases`: Array with smart splitting
   - `remarks`: Multilingual array
   - `reason`: Multilingual array
   - `date_of_birth`: Special date parsing
   - `identifier`: Polymorphic ID (passport, id-card)
   - etc.

2. **Default Mappings**: Common column name variants mapped to fields
   - Address: "住所", "所在地", "住所・所在地", "住所等", "活動地域・住所"
   - Aliases: "別名", "別称・別名", "別称", "旧称", etc.
   - Remarks: "その他の情報", "詳細"
   - Reason: "決議1483上の根拠"

3. **Sheet-Specific Overrides**: Per-sheet column mappings
   - Iraq sheets: "所在地・住所 登録された事務所の住所" → address
   - "詳細" → remarks

4. **Pattern Matching**: Fuzzy matching for unmapped columns
   - `/所在地.*住所/` → address
   - `/詳細/` → remarks
   - `/別名/` → aliases

5. **Smart Alias Splitting**:
   - Splits by Japanese ten (、), comma, semicolon
   - Preserves English company names like "COMPANY, LTD"
   - Uses regex to avoid splitting in the middle of company names

### Entity Type Detection

Two-level detection:
1. **Sheet-level**: Based on sheet name
   - "個人" → individual
   - "団体", "銀行" → organization
   - "リビア", "コンゴ" → organization

2. **Row-level**: For unknown sheets, based on content
   - Has "生年月日" (date of birth) field → individual
   - Otherwise → organization

## Resolved Issues

### 1. Remarks vs Reason Field ✅
- "その他の情報" → `remarks`
- "詳細" → `remarks`
- "決議1483上の根拠" → `reason` (correct - legal basis for sanction)

### 2. Address Field Mapping ✅
- "所在地・住所 登録された事務所の住所" → address
- "活動地域・住所" → address

### 3. Alias Splitting ✅
- Splits by Japanese ten (、), comma, semicolon
- Preserves "COMPANY, LTD" patterns

### 4. Entity Type Detection ✅
- Iraq-1 entities (Saddam Hussein, etc.) → `individual` (has date_of_birth)
- Iraq-3 entities (trading companies) → `organization` (no date_of_birth)

### 5. "称号" Field ✅
- Now correctly mapped to `title` (not `honorific`)

### 6. Sheet Name Lookup & Entity IDs ✅
- Sheet name lookup in `parse_sheet` now uses `.strip` to handle trailing spaces
- Entity IDs now strip `*`, `(`, `)` characters from gazette_number values
- Fixed entities with `jp.mof.unknown.*1` → `jp.mof.dprk-un-organizations.1`

### 7. Alias Splitting ✅
- Split by full-width semicolon `；` (U+FF1B)
- Split by newline characters
- Split by label markers: `（別称）`, `（旧称）`, `（別名）`, etc.
- **Labels are PRESERVED** in the alias (they indicate "also known as", "old name")
- Example: `（別称）A （旧称）B` → 2 aliases: `（別称）A`, `（旧称）B`

## Next Steps

1. Create RSpec tests for parser, entity model, and field mapping
2. Update README.adoc with MOF parser documentation
3. Create docs/mof-sanctions-parser.adoc
