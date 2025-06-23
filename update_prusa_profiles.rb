#!/usr/bin/env ruby

require "bigdecimal"
require "fileutils"
require "optparse"

# INI Parser class to handle PrusaSlicer .ini files
class IniParser
  Profile = Struct.new(:stanza, :properties, :comments, :lines, keyword_init: true)

  def initialize(profile_type, default_stanza_name)
    @profile_type = profile_type
    @default_stanza_name = default_stanza_name
  end

  # Parse an INI file into an array of Profile objects
  def parse(file_path)
    content = File.read(file_path)
    lines = content.lines
    profiles = []
    current_profile = nil
    current_comments = []
    current_properties = {}
    current_lines = []
    index = 0

    while index < lines.length
      line = lines[index]
      clean_line = line.split("#").first.strip

      if (match = clean_line.match(/^\s*\[#{@profile_type}:(.*?)\]\s*$/))
        # New stanza found; save previous profile if exists
        if current_profile
          profiles << Profile.new(
            stanza: current_profile,
            properties: current_properties,
            comments: current_comments,
            lines: current_lines
          )
        end
        # Start new profile
        current_profile = "#{@profile_type}: #{match[1].strip}"
        current_comments = []
        current_properties = {}
        current_lines = [line]
        index += 1
      elsif (match = clean_line.match(/^\s*(\w+)\s*=\s*(.*)$/))
        # Property line
        key = match[1].strip
        value = match[2].strip
        current_properties[key] = value
        current_lines << line
        index += 1
      else
        # Comment, blank line, or other non-property line
        current_comments << line if line.match?(/^\s*#/)
        current_lines << line
        index += 1
      end
    end

    # Save the last profile, or create default if no stanza found
    if current_profile || !current_properties.empty? || !current_comments.empty?
      current_profile ||= "#{@profile_type}: #{@default_stanza_name}"
      profiles << Profile.new(
        stanza: current_profile,
        properties: current_properties,
        comments: current_comments,
        lines: current_lines
      )
    else
      # No content; create empty default profile
      profiles << Profile.new(
        stanza: "#{@profile_type}: #{@default_stanza_name}",
        properties: {},
        comments: [],
        lines: []
      )
    end

    profiles.map do |profile|
      {
        file_path: file_path,
        profile_name: profile.stanza,
        properties: profile.properties,
        comments: profile.comments,
        lines: profile.lines
      }
    end
  rescue StandardError => e
    location = caller_locations(1, 1).first
    puts "Error in #{File.basename(__FILE__)} at #{location.label} (line ~#{location.lineno}): #{e.message}"
    []
  end

  # Write profiles back to a file
  def write(file_path, profiles)
    new_lines = []
    profiles.each do |profile|
      # Write stanza header if not a default profile or if properties/comments exist
      new_lines << "[#{profile[:profile_name]}]\n" if profile[:profile_name] != "#{@profile_type}: #{@default_stanza_name}" || !profile[:properties].empty? || !profile[:comments].empty?
      # Write comments and non-property lines (excluding stanza headers)
      profile[:lines].each do |line|
        clean_line = line.split("#").first.strip
        # Skip property lines and stanza headers
        next if clean_line.match?(/^\s*\w+\s*=/) || clean_line.match?(/^\s*\[.*\]\s*$/)

        new_lines << line
      end
      # Write properties
      profile[:properties].each do |key, value|
        new_lines << "#{key} = #{value}\n"
      end
      new_lines << "\n" unless new_lines.last == "\n"
    end
    File.write(file_path, new_lines.join)
  rescue StandardError => e
    location = caller_locations(1, 1).first
    puts "Error in #{File.basename(__FILE__)} at #{location.label} (line ~#{location.lineno}): #{e.message}"
  end
end

# Parse a value and its unit, returning [BigDecimal value, unit, is_integer]
def parse_value(value_str)
  match = value_str.match(/^(\d*\.?\d*)(%?|mm)?$/)
  raise "Invalid value format: #{value_str}" unless match

  num_str = match[1]
  unit = match[2] || ""
  is_integer = num_str !~ /\./
  value = BigDecimal(num_str)
  [value, unit, is_integer]
end

# Parse a relative adjustment, returning [operation, BigDecimal amount, unit]
def parse_relative_value(value_str)
  match = value_str.match(/^=\s*([+-])\s*(\d*\.?\d*)(%?|mm)?$/)
  raise "Invalid relative value format: #{value_str}" unless match

  op = match[1]
  amount = BigDecimal(match[2])
  unit = match[3] || ""
  [op, amount, unit]
end

# Parse profile name with optional tags, returning [base_name, tags_array]
def parse_profile_name_with_tags(profile_name)
  # Remove profile type prefix if present (e.g., "print: " or "filament: ")
  name_part = profile_name.sub(/^(print|filament):\s*/, "")

  # Find all @tag (non-space, non-asterisk characters) in the name
  tags = name_part.scan(/@([^\s*]+)/).flatten

  # For base name, remove @tags but keep the rest exactly as entered
  base_name = name_part.gsub(/@[^\s*]+/, "").strip.gsub(/\s+/, " ")

  [base_name, tags]
end

# Extract tags from profile name, returning just the tags array
def extract_tags_from_profile_name(profile_name)
  _, tags = parse_profile_name_with_tags(profile_name)
  tags
end

# Format profile name with tags (preserves original format)
# If reconstructing is needed, this puts tags at the end, but generally
# we should preserve the original name format as entered
def format_profile_name_with_tags(base_name, tags = [])
  if tags.empty?
    base_name
  else
    "#{base_name} #{tags.map { |tag| "@#{tag}" }.join(' ')}"
  end
end

# Get the original profile name without removing or reformatting tags
def preserve_original_profile_name(profile_name)
  # Remove only the profile type prefix if present, but keep everything else
  profile_name.sub(/^(print|filament):\s*/, "")
end

# Get the base name without tags from a profile name
def get_base_profile_name(profile_name)
  base_name, = parse_profile_name_with_tags(profile_name)
  base_name
end

# Create a filename-safe version of profile name including tags
def get_filename_with_tags(profile_name)
  # Use the original name format, just remove profile type prefix and sanitize
  original_name = preserve_original_profile_name(profile_name)
  sanitize_filename(original_name)
end

# Sanitize a string to be safe for use as a filename
def sanitize_filename(name)
  # Replace characters that are not safe for filenames
  # Keep alphanumeric, spaces, periods, hyphens, underscores, @, and parentheses
  name.gsub(/[^\w\s@.\-()]+/, "_").strip
end

# Check if a filename contains characters that are unsafe for NTFS or macOS filesystems
def contains_unsafe_filesystem_chars?(name)
  # Characters not allowed on NTFS: < > : " | ? * \ /
  # Characters not allowed on macOS: : (colon gets converted to slash in Finder)
  # Also avoid control characters (ASCII 0-31) and DEL (127)
  unsafe_chars = %r{[<>:"|?*\\/\x00-\x1f\x7f]}
  name.match?(unsafe_chars)
end

# Get a list of unsafe characters found in the name for user feedback
def get_unsafe_filesystem_chars(name)
  unsafe_chars = name.scan(%r{[<>:"|?*\\/\x00-\x1f\x7f]})
  unsafe_chars.uniq
end

# Get filter values from profile properties and name
def get_filter_values(properties, profile_type, profile_name = nil)
  if profile_type == "filament"
    type = properties["filament_type"]&.strip&.downcase
    vendor = properties["filament_vendor"]&.strip&.downcase
    { type: type, vendor: vendor, sub_profile: nil, layer: nil, nozzle: nil }
  else # print
    # Get tags from land_fm_tags property
    tags_from_property = properties["land_fm_tags"]&.split(",")&.map(&:strip)&.map(&:downcase) || []

    # Get tags from profile name if provided
    tags_from_name = []
    if profile_name
      _, name_tags = parse_profile_name_with_tags(profile_name)
      tags_from_name = name_tags.map(&:downcase)
    end

    # Combine tags from both sources
    all_tags = (tags_from_property + tags_from_name).uniq

    layer = properties["layer_height"]&.strip&.downcase
    nozzle = nil
    if properties["compatible_printers_condition"] && (match = properties["compatible_printers_condition"].match(/nozzle_diameter\[0\]==(\d*\.?\d+)/))
      nozzle = "#{match[1]}mm".downcase
    end
    { type: nil, vendor: nil, sub_profile: all_tags, layer: layer, nozzle: nozzle }
  end
rescue StandardError => e
  location = caller_locations(1, 1).first
  puts "Error in #{File.basename(__FILE__)} at #{location.label} (line ~#{location.lineno}): #{e.message}"
  { type: nil, vendor: nil, sub_profile: [], layer: nil, nozzle: nil }
end

# Check if profile matches filter criteria
def matches_filter(properties, filters, profile_type, profile_name = nil)
  values = get_filter_values(properties, profile_type, profile_name)
  if profile_type == "filament"
    type_match = filters[:type].empty? || values[:type] == filters[:type].downcase
    vendor_match = filters[:vendor].empty? || values[:vendor] == filters[:vendor].downcase
    type_match && vendor_match
  else # print
    sub_profile_match = filters[:sub_profile].empty? || values[:sub_profile]&.include?(filters[:sub_profile].downcase)

    # Normalize layer height for comparison (handles with/without "mm")
    layer_match = if filters[:layer].empty?
                    true
                  else
                    normalized_filter_layer = normalize_value_for_comparison(filters[:layer], "mm")
                    normalized_value_layer = normalize_value_for_comparison(values[:layer], "mm")
                    normalized_value_layer == normalized_filter_layer
                  end

    # Normalize nozzle diameter for comparison (handles with/without "mm")
    nozzle_match = if filters[:nozzle].empty?
                     true
                   else
                     normalized_filter_nozzle = normalize_value_for_comparison(filters[:nozzle], "mm")
                     normalized_value_nozzle = normalize_value_for_comparison(values[:nozzle], "mm")
                     normalized_value_nozzle == normalized_filter_nozzle
                   end

    sub_profile_match && layer_match && nozzle_match
  end
rescue StandardError => e
  location = caller_locations(1, 1).first
  puts "Error in #{File.basename(__FILE__)} at #{location.label} (line ~#{location.lineno}): #{e.message}"
  false
end

# Preview changes for a single profile, returning [old_value, new_value, new_properties] or nil
def preview_change(properties, property, value, is_multiline = false)
  old_value = properties[property] || "(not set)"
  new_value = nil
  new_properties = properties.dup

  if is_multiline || !value.start_with?("=")
    new_value = value
  elsif properties.key?(property)
    op, amount, rel_unit = parse_relative_value(value)
    current_value, current_unit, current_is_integer = parse_value(old_value)
    raise "Unit mismatch: expected #{rel_unit}, got #{current_unit}" unless rel_unit == current_unit

    new_value = op == "+" ? current_value + amount : current_value - amount
    new_value = [new_value, BigDecimal("0")].max if current_unit.empty? && new_value < 0
    new_value = format_value(new_value, current_unit, current_is_integer)
  else
    new_value = "(cannot apply relative change)"
    return nil
  end

  new_properties[property] = new_value
  # Alphabetize properties
  new_properties = new_properties.sort.to_h
  [old_value, new_value, new_properties]
rescue StandardError => e
  location = caller_locations(1, 1).first
  puts "Error in #{File.basename(__FILE__)} at #{location.label} (line ~#{location.lineno}): #{e.message}"
  nil
end

# Apply changes to a file, updating matching profiles
def apply_changes(file_path, profiles, preview_data, profile_type)
  parser = IniParser.new(profile_type, File.basename(file_path, ".ini"))
  updated_profiles = profiles.map do |profile|
    preview = preview_data.find { |pd| pd[:profile_name] == profile[:profile_name] }
    if preview && preview[:new_properties]
      {
        profile_name: profile[:profile_name],
        properties: preview[:new_properties],
        comments: profile[:comments],
        lines: profile[:lines]
      }
    else
      profile
    end
  end
  parser.write(file_path, updated_profiles)
rescue StandardError => e
  location = caller_locations(1, 1).first
  puts "Error in #{File.basename(__FILE__)} at #{location.label} (line ~#{location.lineno}): #{e.message}"
end

# Find common properties across profiles
def find_common_properties(profiles)
  return {} if profiles.empty?

  common = profiles.first[:properties].dup
  profiles[1..-1].each do |profile|
    common.keep_if { |k, v| profile[:properties][k] == v }
  end
  common.sort.to_h
end

# Helper function to check if a profile inherits from a given parent
def profile_inherits_from?(profile, parent_name)
  inherits_value = profile[:properties]["inherits"]
  return false unless inherits_value && !inherits_value.empty?

  # Check exact match
  return true if inherits_value == parent_name

  # Check trimmed match
  return true if inherits_value.strip == parent_name.strip

  # Check without profile type prefix
  inherits_without_prefix = inherits_value.sub(/^(print|filament):\s*/, "")
  parent_without_prefix = parent_name.sub(/^(print|filament):\s*/, "")
  return true if inherits_without_prefix == parent_without_prefix
  return true if inherits_without_prefix.strip == parent_without_prefix.strip

  false
end

# Find all descendant profiles that inherit from any of the given parent profiles
def find_descendant_profiles(parent_profile_names, all_profiles, visited = Set.new)
  descendants = []

  parent_profile_names.each do |parent_name|
    # Avoid infinite loops in case of circular inheritance
    next if visited.include?(parent_name)

    visited.add(parent_name)

    # Find direct children that inherit from this parent
    direct_children = all_profiles.select do |profile|
      profile_inherits_from?(profile, parent_name)
    end

    puts "    DEBUG: Parent '#{parent_name}' has #{direct_children.length} direct children:"
    direct_children.each do |child|
      puts "      - #{child[:profile_name]}"
    end

    descendants.concat(direct_children)

    # Recursively find descendants of the direct children
    child_names = direct_children.map { |profile| profile[:profile_name] }
    next if child_names.empty?

    puts "    DEBUG: Recursively searching for descendants of: #{child_names.join(', ')}"
    recursive_descendants = find_descendant_profiles(child_names, all_profiles, visited)
    puts "    DEBUG: Found #{recursive_descendants.length} recursive descendants"
    descendants.concat(recursive_descendants)
  end

  # Remove duplicates while preserving order
  seen = Set.new
  unique_descendants = descendants.select do |profile|
    key = profile[:profile_name]
    if seen.include?(key)
      false
    else
      seen.add(key)
      true
    end
  end

  puts "    DEBUG: Total unique descendants found: #{unique_descendants.length}"
  unique_descendants
end

# Alternative method to find all descendants using a more comprehensive approach
def find_all_descendants_comprehensive(parent_profile_names, all_profiles)
  descendants = []

  # Use breadth-first search to find all descendants
  queue = parent_profile_names.dup
  visited = Set.new

  until queue.empty?
    current_parent = queue.shift
    next if visited.include?(current_parent)

    visited.add(current_parent)

    # Find children of current parent using our robust helper function
    children = all_profiles.select { |profile| profile_inherits_from?(profile, current_parent) }

    children.each do |child|
      # Add child to descendants if not already included
      next if descendants.any? { |d| d[:profile_name] == child[:profile_name] }

      descendants << child
      # Add child to queue to find its descendants
      queue << child[:profile_name]
    end
  end

  descendants
end

# Combine profiles into a single file
def combine_profiles(matching_profiles, parent_name, profile_type)
  parent_properties = find_common_properties(matching_profiles)
  filename_with_tags = get_filename_with_tags(parent_name)
  dir_path = File.dirname(matching_profiles.first[:file_path])
  parent_output_file = File.join(dir_path, "#{filename_with_tags}.ini")

  # Load all profiles from all files to find descendants
  all_ini_files = Dir.glob(File.join(dir_path, "*.ini"))
  all_profiles = []
  all_ini_files.each do |file|
    parser = IniParser.new(profile_type, File.basename(file, ".ini"))
    profiles = parser.parse(file)
    all_profiles.concat(profiles)
  end

  # Find all descendant profiles
  child_profile_names = matching_profiles.map { |profile| profile[:profile_name] }
  puts "\nDEBUG: Looking for descendants of: #{child_profile_names.join(', ')}"
  puts "DEBUG: Total profiles in directory: #{all_profiles.length}"
  puts "DEBUG: All profiles with inherits property:"
  all_profiles.each do |profile|
    puts "  - #{profile[:profile_name]} inherits from #{profile[:properties]['inherits']}" if profile[:properties]["inherits"]
  end

  descendant_profiles = find_descendant_profiles(child_profile_names, all_profiles)

  # Try alternative comprehensive method as well
  comprehensive_descendants = find_all_descendants_comprehensive(child_profile_names, all_profiles)
  puts "DEBUG: Recursive method found #{descendant_profiles.length} descendants"
  puts "DEBUG: Comprehensive method found #{comprehensive_descendants.length} descendants"

  # Use the comprehensive method if it found more descendants
  if comprehensive_descendants.length > descendant_profiles.length
    puts "DEBUG: Using comprehensive method results (found more descendants)"
    descendant_profiles = comprehensive_descendants
  end

  puts "\nFound #{descendant_profiles.length} descendant profile(s) to include:" if descendant_profiles.length > 0
  descendant_profiles.each do |profile|
    puts "  - #{profile[:profile_name]} (from #{File.basename(profile[:file_path])})"
  end

  # Check if all profiles inherit from the same parent
  inherit_values = matching_profiles.map { |profile| profile[:properties]["inherits"] }.uniq
  common_parent = nil
  if inherit_values.length == 1
    # All profiles have the same inherits value (could be nil)
    common_parent = inherit_values.first
    # Remove 'inherits' from parent_properties since we'll handle it specially
    parent_properties.delete("inherits")
  end

  # Check for common compatible_printers_condition
  common_compatible_printers = nil
  compatible_values = matching_profiles.map { |profile| profile[:properties]["compatible_printers_condition"] }.uniq.compact
  if compatible_values.length == 1
    common_compatible_printers = compatible_values.first
    puts "DEBUG: Found common compatible_printers_condition: #{common_compatible_printers}"
    # Keep this in parent properties
  end

  # 1. Create parent profile file (no stanza, filename serves as profile name)
  parent_lines = []
  # Add inherits to parent if all child profiles inherited from the same profile
  parent_lines << "inherits = #{common_parent}\n" if common_parent
  parent_properties.each do |key, value|
    parent_lines << "#{key} = #{value}\n"
  end

  File.write(parent_output_file, parent_lines.join)
  puts "Created parent profile file: #{File.basename(parent_output_file)}"

  # 2. Update child profiles in their original files
  files_processed = []
  matching_profiles.each do |profile|
    file_path = profile[:file_path]
    next if files_processed.include?(file_path)

    files_processed << file_path

    # Parse the file
    parser = IniParser.new(profile_type, File.basename(file_path, ".ini"))
    all_profiles_in_file = parser.parse(file_path)

    # Update the matching profiles in this file
    updated_profiles = all_profiles_in_file.map do |file_profile|
      if matching_profiles.any? { |mp| mp[:profile_name] == file_profile[:profile_name] }
        # This is one of the profiles being combined
        updated_properties = file_profile[:properties].dup

        # Remove common properties (they're now in the parent)
        parent_properties.each_key { |k| updated_properties.delete(k) }

        # Remove the original inherits property and add inherits to new parent
        updated_properties.delete("inherits")
        updated_properties["inherits"] = filename_with_tags

        # Handle compatible_printers_condition inheritance
        updated_properties["compatible_printers_condition"] = common_compatible_printers if common_compatible_printers && !updated_properties["compatible_printers_condition"]

        # Alphabetize
        updated_properties = updated_properties.sort.to_h

        {
          profile_name: file_profile[:profile_name],
          properties: updated_properties,
          comments: file_profile[:comments],
          lines: file_profile[:lines]
        }
      else
        # Check if this profile should inherit compatible_printers_condition
        updated_properties = file_profile[:properties].dup

        # If this profile inherits from one of our combined profiles and doesn't have compatible_printers_condition
        if common_compatible_printers &&
           matching_profiles.any? { |mp| profile_inherits_from?(file_profile, mp[:profile_name]) } &&
           !updated_properties["compatible_printers_condition"]
          updated_properties["compatible_printers_condition"] = common_compatible_printers
          updated_properties = updated_properties.sort.to_h
          puts "Added compatible_printers_condition to #{file_profile[:profile_name]}"
        end

        {
          profile_name: file_profile[:profile_name],
          properties: updated_properties,
          comments: file_profile[:comments],
          lines: file_profile[:lines]
        }
      end
    end

    # Write updated file
    parser.write(file_path, updated_profiles)
    puts "Updated profiles in: #{File.basename(file_path)}"
  end

  # 3. Handle descendant profiles that might need compatible_printers_condition
  descendant_files_processed = []
  descendant_profiles.each do |profile|
    file_path = profile[:file_path]
    next if files_processed.include?(file_path) || descendant_files_processed.include?(file_path)

    descendant_files_processed << file_path

    # Parse the file
    parser = IniParser.new(profile_type, File.basename(file_path, ".ini"))
    all_profiles_in_file = parser.parse(file_path)

    # Check if any profiles need compatible_printers_condition added
    file_updated = false
    updated_profiles = all_profiles_in_file.map do |file_profile|
      updated_properties = file_profile[:properties].dup

      # If this profile inherits from one of our combined profiles and doesn't have compatible_printers_condition
      if common_compatible_printers &&
         matching_profiles.any? { |mp| profile_inherits_from?(file_profile, mp[:profile_name]) } &&
         !updated_properties["compatible_printers_condition"]
        updated_properties["compatible_printers_condition"] = common_compatible_printers
        updated_properties = updated_properties.sort.to_h
        puts "Added compatible_printers_condition to #{file_profile[:profile_name]}"
        file_updated = true
      end

      {
        profile_name: file_profile[:profile_name],
        properties: updated_properties,
        comments: file_profile[:comments],
        lines: file_profile[:lines]
      }
    end

    # Write updated file if changes were made
    if file_updated
      parser.write(file_path, updated_profiles)
      puts "Updated descendant profiles in: #{File.basename(file_path)}"
    end
  end

  # Store info for reporting
  @deleted_files = [] # No files deleted in this new approach
  @included_descendants_count = descendant_profiles.length
  @files_processed = files_processed + descendant_files_processed

  parent_output_file
rescue StandardError => e
  location = caller_locations(1, 1).first
  puts "Error in #{File.basename(__FILE__)} at #{location.label} (line ~#{location.lineno}): #{e.message}"
  nil
end

# Bundle profiles into a single INI file in the vendor folder
def bundle_profiles(matching_profiles, bundle_name, profile_type, custom_bundle_dir = nil, custom_profile_dir = nil)
  # Determine paths
  vendor_dir = custom_bundle_dir || File.join(Dir.pwd, "vendor")
  profile_dir = custom_profile_dir || File.join(Dir.pwd, profile_type)

  unless Dir.exist?(vendor_dir)
    FileUtils.mkdir_p(vendor_dir)
    puts "Created bundle directory: #{vendor_dir}"
  end

  bundle_file_path = File.join(vendor_dir, "#{bundle_name}.ini")

  # Load ALL profiles from the profile directory to build complete inheritance graph
  puts "Loading all #{profile_type} profiles to analyze inheritance..."
  all_ini_files = Dir.glob(File.join(profile_dir, "*.ini"))
  all_profiles = []
  all_ini_files.each do |file|
    parser = IniParser.new(profile_type, File.basename(file, ".ini"))
    profiles = parser.parse(file)
    all_profiles.concat(profiles)
  end
  puts "Loaded #{all_profiles.length} total profiles from #{all_ini_files.length} files"

  # Build inheritance graph within the selected matching profiles
  matching_profile_names = Set.new
  matching_profiles.each do |profile|
    base_name = profile[:profile_name].sub(/^#{profile_type}:\s*/, "")
    matching_profile_names.add(base_name)
  end

  # Find which matching profiles are parents (have children within the matching set)
  parent_profiles_in_selection = Set.new
  matching_profiles.each do |potential_parent|
    parent_base_name = potential_parent[:profile_name].sub(/^#{profile_type}:\s*/, "")
    parent_core_name = get_base_profile_name(potential_parent[:profile_name])

    # Check if any other matching profile inherits from this one
    matching_profiles.each do |potential_child|
      child_inherits = potential_child[:properties]["inherits"]
      next unless child_inherits && !child_inherits.empty?

      inherits_base_name = child_inherits.sub(/^#{profile_type}:\s*/, "")
      inherits_core_name = get_base_profile_name("#{profile_type}: #{child_inherits}")

      # Check both exact match and core name match (without tags)
      next unless inherits_base_name == parent_base_name || inherits_core_name == parent_core_name

      parent_profiles_in_selection.add(parent_base_name)
      puts "  Found inheritance: #{potential_child[:profile_name]} -> #{potential_parent[:profile_name]}"
      break
    end
  end

  # Identify leaf profiles (profiles with no children in the matching set)
  leaf_profiles = []
  non_leaf_profiles = []

  matching_profiles.each do |profile|
    base_name = profile[:profile_name].sub(/^#{profile_type}:\s*/, "")
    if parent_profiles_in_selection.include?(base_name)
      non_leaf_profiles << profile
      puts "Non-leaf profile (will be moved to bundle): #{profile[:profile_name]}"
    else
      leaf_profiles << profile
      puts "Leaf profile (will stay in original location): #{profile[:profile_name]}"
    end
  end

  if non_leaf_profiles.empty?
    puts "No parent profiles found in selection - nothing to move to bundle"
    return nil
  end

  # Check if bundle already exists and load existing profiles
  existing_bundle_profiles = []
  if File.exist?(bundle_file_path)
    puts "Bundle file already exists: #{File.basename(bundle_file_path)}"
    parser = IniParser.new(profile_type, File.basename(bundle_file_path, ".ini"))
    existing_bundle_profiles = parser.parse(bundle_file_path)
  else
    puts "Creating new bundle file: #{File.basename(bundle_file_path)}"
  end

  # Create mapping from original names to privatized (asterisk) names
  name_mapping = {}
  non_leaf_profiles.each do |profile|
    base_name = profile[:profile_name].sub(/^#{profile_type}:\s*/, "")
    # Don't add asterisks if they're already there
    next if base_name.start_with?("*") && base_name.end_with?("*")

    asterisk_name = "*#{base_name}*"
    name_mapping[base_name] = asterisk_name
    puts "Will privatize: #{base_name} -> #{asterisk_name}"
  end

  # Prepare non-leaf profiles for the bundle with privatized names
  bundle_profiles = []
  existing_names = existing_bundle_profiles.map { |p| p[:profile_name] }

  non_leaf_profiles.each do |profile|
    base_name = profile[:profile_name].sub(/^#{profile_type}:\s*/, "")
    privatized_name = name_mapping[base_name] || base_name
    privatized_profile_name = "#{profile_type}: #{privatized_name}"

    # Skip if already exists in bundle
    if existing_names.include?(privatized_profile_name)
      puts "Skipping duplicate in bundle: #{privatized_profile_name}"
      next
    end

    bundle_profile = {
      profile_name: privatized_profile_name,
      properties: profile[:properties].dup,
      comments: profile[:comments],
      lines: profile[:lines]
    }

    # Update inherits if it references another profile being privatized
    if bundle_profile[:properties]["inherits"]
      inherits_base_name = bundle_profile[:properties]["inherits"].sub(/^#{profile_type}:\s*/, "")
      if name_mapping.key?(inherits_base_name)
        bundle_profile[:properties]["inherits"] = name_mapping[inherits_base_name]
        puts "Updated inherits in bundle profile #{privatized_name}: #{inherits_base_name} -> #{name_mapping[inherits_base_name]}"
      end
    end

    bundle_profiles << bundle_profile
  end

  # Combine with existing bundle profiles
  all_bundle_profiles = existing_bundle_profiles + bundle_profiles

  # Write the bundle file
  parser = IniParser.new(profile_type, File.basename(bundle_file_path, ".ini"))
  parser.write(bundle_file_path, all_bundle_profiles)
  puts "Bundle file updated with #{bundle_profiles.length} new profile(s)"

  # Update ALL profiles that inherit from the privatized profiles
  puts "Updating inheritance references across all #{profile_type} files..."
  files_updated = 0

  all_ini_files.each do |file_path|
    parser = IniParser.new(profile_type, File.basename(file_path, ".ini"))
    file_profiles = parser.parse(file_path)
    file_changed = false

    file_profiles.each do |profile|
      next unless profile[:properties]["inherits"]

      inherits_base_name = profile[:properties]["inherits"].sub(/^#{profile_type}:\s*/, "")
      inherits_core_name = get_base_profile_name("#{profile_type}: #{profile[:properties]['inherits']}")

      # Check if this profile inherits from one of our privatized profiles
      # Try both exact name match and core name match
      matching_privatized_name = nil
      name_mapping.each do |original_name, privatized_name|
        original_core_name = get_base_profile_name("#{profile_type}: #{original_name}")
        if inherits_base_name == original_name || inherits_core_name == original_core_name
          matching_privatized_name = privatized_name
          break
        end
      end

      next unless matching_privatized_name

      old_inherits = profile[:properties]["inherits"]
      profile[:properties]["inherits"] = matching_privatized_name
      puts "Updated #{File.basename(file_path)}: #{profile[:profile_name]} inherits: #{old_inherits} -> #{profile[:properties]['inherits']}"
      file_changed = true
    end

    # Write the file back if it was modified
    if file_changed
      parser.write(file_path, file_profiles)
      files_updated += 1
    end
  end

  # Remove the non-leaf profiles from their original files
  puts "Removing privatized profiles from original files..."
  files_to_update = {}

  non_leaf_profiles.each do |profile|
    file_path = profile[:file_path]
    files_to_update[file_path] ||= []
    files_to_update[file_path] << profile[:profile_name]
  end

  files_to_update.each do |file_path, profiles_to_remove|
    parser = IniParser.new(profile_type, File.basename(file_path, ".ini"))
    file_profiles = parser.parse(file_path)

    # Remove the profiles that were moved to the bundle
    original_count = file_profiles.length
    file_profiles.reject! { |p| profiles_to_remove.include?(p[:profile_name]) }
    removed_count = original_count - file_profiles.length

    if removed_count > 0
      parser.write(file_path, file_profiles)
      puts "Removed #{removed_count} profile(s) from #{File.basename(file_path)}"
    end
  end

  puts "\n✓ Bundle operation completed:"
  puts "  - Moved #{non_leaf_profiles.length} non-leaf profile(s) to bundle (privatized)"
  puts "  - Left #{leaf_profiles.length} leaf profile(s) in original locations"
  puts "  - Updated inheritance in #{files_updated} file(s)"
  puts "  - Bundle file: #{File.basename(bundle_file_path)}"

  bundle_file_path
rescue StandardError => e
  location = caller_locations(1, 1).first
  puts "Error in #{File.basename(__FILE__)} at #{location.label} (line ~#{location.lineno}): #{e.message}"
  nil
end

# Parse command line arguments
def parse_command_line_args
  options = {
    mode: nil,
    profile_type: nil,
    tag: nil,
    nozzle: nil,
    layer_height: nil,
    sub_profile: nil,
    type: nil,
    vendor: nil,
    into: nil,
    updates: [],
    profile_dir: nil,
    bundle_dir: nil
  }

  parser = OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} <command> <profile_type> [options] [update_expressions...]"
    opts.separator ""
    opts.separator "Commands:"
    opts.separator "  combine    Combine matching profiles into a new parent profile"
    opts.separator "  bundle     Bundle matching profiles into a single file in vendor folder"
    opts.separator "  update     Update properties in matching profiles"
    opts.separator ""
    opts.separator "Profile Types:"
    opts.separator "  print      Print profiles"
    opts.separator "  filament   Filament profiles"
    opts.separator ""
    opts.separator "Options:"

    opts.on("--tag TAG", "Filter by tag") do |tag|
      options[:tag] = tag
    end

    opts.on("--nozzle DIAMETER", "Filter by nozzle diameter (e.g., 0.4 or 0.4mm)") do |nozzle|
      options[:nozzle] = nozzle
    end

    opts.on("--layer-height HEIGHT", "Filter by layer height (e.g., 0.3 or 0.3mm)") do |height|
      options[:layer_height] = height
    end

    opts.on("--sub-profile PROFILE", "Filter by sub-profile") do |profile|
      options[:sub_profile] = profile
    end

    opts.on("--type TYPE", "Filter by filament type (e.g., ASA)") do |type|
      options[:type] = type
    end

    opts.on("--vendor VENDOR", "Filter by vendor (e.g., Prusa)") do |vendor|
      options[:vendor] = vendor
    end

    opts.on("--into NAME", "Name for combined/bundle profile") do |name|
      options[:into] = name
    end

    opts.on("--profile-dir DIR", "Custom profile directory (default: print or filament)") do |dir|
      options[:profile_dir] = dir
    end

    opts.on("--bundle-dir DIR", "Custom bundle directory (default: vendor)") do |dir|
      options[:bundle_dir] = dir
    end

    opts.on("-h", "--help", "Show this help message") do
      puts opts
      exit
    end
  end

  # Parse the command line
  begin
    remaining_args = parser.parse!(ARGV)
  rescue OptionParser::InvalidOption => e
    puts "Error: #{e.message}"
    puts parser
    exit 1
  end

  # First argument should be the command
  if remaining_args.empty?
    puts "Error: No command specified"
    puts parser
    exit 1
  end

  options[:mode] = remaining_args.shift
  unless %w[combine bundle update].include?(options[:mode])
    puts "Error: Invalid command '#{options[:mode]}'. Use 'combine', 'bundle', or 'update'"
    puts parser
    exit 1
  end

  # Second argument should be the profile type
  if remaining_args.empty?
    puts "Error: No profile type specified"
    puts parser
    exit 1
  end

  options[:profile_type] = remaining_args.shift
  unless %w[print filament].include?(options[:profile_type])
    puts "Error: Invalid profile type '#{options[:profile_type]}'. Use 'print' or 'filament'"
    puts parser
    exit 1
  end

  # For combine and bundle modes, --into is required
  if %w[combine bundle].include?(options[:mode]) && options[:into].nil?
    puts "Error: --into option is required for #{options[:mode]} mode"
    puts parser
    exit 1
  end

  # Remaining arguments are update expressions for update mode
  if options[:mode] == "update"
    options[:updates] = remaining_args
    if options[:updates].empty?
      puts "Error: No update expressions provided for update mode"
      puts "Example: layer_height==+1 fill_overlap=40%"
      exit 1
    end
  end

  options
end

# Convert command line options to filter hash
def options_to_filters(options)
  filters = {}

  if options[:profile_type] == "filament"
    filters[:type] = options[:type] || ""
    filters[:vendor] = options[:vendor] || ""
    filters[:sub_profile] = ""
  else # print
    filters[:nozzle] = options[:nozzle] || ""
    filters[:layer] = options[:layer_height] || ""
    filters[:sub_profile] = options[:sub_profile] || ""
  end

  # Add tag filter if specified
  filters[:tag] = options[:tag] if options[:tag]

  filters
end

# Normalize a value for comparison, handling units like "mm"
def normalize_value_for_comparison(value, default_unit = "mm")
  return nil if value.nil? || value.empty?

  value = value.strip.downcase

  # If the value already has a unit, return as-is
  return value if value.end_with?("mm", "%")

  # If it's a number without unit, add the default unit
  return "#{value}#{default_unit}" if value.match?(/^\d*\.?\d+$/)

  # Return as-is for non-numeric values
  value
end

# Main execution - only run if this file is executed directly
if __FILE__ == $0
  options = parse_command_line_args

  mode = options[:mode]
  profile_type = options[:profile_type]
  dir_path = File.join(Dir.pwd, profile_type)

  # Use custom profile directory if specified
  dir_path = options[:profile_dir] if options[:profile_dir]

  unless Dir.exist?(dir_path)
    puts "Directory '#{dir_path}' does not exist."
    exit 1
  end

  ini_files = Dir.glob(File.join(dir_path, "*.ini"))
  if ini_files.empty?
    puts "No .ini files found in '#{dir_path}'."
    exit 1
  end

  # Convert options to filters and find matching profiles
  filters = options_to_filters(options)
  matching_profiles = []
  ini_files.each do |file|
    parser = IniParser.new(profile_type, File.basename(file, ".ini"))
    profiles = parser.parse(file)
    profiles.each do |profile|
      matching_profiles << profile if matches_filter(profile[:properties], filters, profile_type, profile[:profile_name])
    end
  end

  if matching_profiles.empty?
    puts "No profiles match the specified filters in '#{dir_path}'."
    exit 1
  end

  puts "Matching #{profile_type} profiles:"
  matching_profiles.each do |profile|
    profile_tags = extract_tags_from_profile_name(profile[:profile_name])
    if profile_tags.empty?
      puts "#{File.basename(profile[:file_path])}: #{profile[:profile_name]}"
    else
      puts "#{File.basename(profile[:file_path])}: #{profile[:profile_name]} (tags: #{profile_tags.join(', ')})"
    end
  end

  # Execute the requested mode
  if mode == "combine"
    if matching_profiles.empty?
      puts "No profiles to combine."
      exit 0
    end

    parent_name = options[:into]

    # Validate the parent name for filesystem safety
    if contains_unsafe_filesystem_chars?(parent_name)
      unsafe_chars = get_unsafe_filesystem_chars(parent_name)
      puts "Error: Profile name contains unsafe characters: #{unsafe_chars.join(', ')}"
      puts "Please avoid these characters: < > : \" | ? * \\ /"
      exit 1
    end

    # Parse the parent name to extract tags for display
    _, parent_tags = parse_profile_name_with_tags(parent_name)
    # Use the original format instead of reformatting
    formatted_parent_name = preserve_original_profile_name(parent_name)

    puts "\nProposed parent profile: #{formatted_parent_name}"
    puts "Filename: #{get_filename_with_tags(parent_name)}.ini"
    puts "Tags: #{parent_tags.join(', ')}" unless parent_tags.empty?

    # Check if all profiles inherit from the same parent
    inherit_values = matching_profiles.map { |profile| profile[:properties]["inherits"] }.uniq
    if inherit_values.length == 1 && inherit_values.first
      puts "Parent profile will inherit from: #{inherit_values.first}"
    elsif inherit_values.length == 1
      puts "Parent profile will not inherit from any other profile"
    else
      puts "Warning: Profiles inherit from different parents - inheritance will be flattened"
    end

    puts "\nCombining profiles..."
    parent_output_file = combine_profiles(matching_profiles, parent_name, profile_type)
    puts "Successfully created parent profile: #{File.basename(parent_output_file)}"

  elsif mode == "bundle"
    if matching_profiles.empty?
      puts "No profiles to bundle."
      exit 0
    end

    bundle_name = options[:into]

    # Validate the bundle name for filesystem safety
    if contains_unsafe_filesystem_chars?(bundle_name)
      unsafe_chars = get_unsafe_filesystem_chars(bundle_name)
      puts "Error: Bundle name contains unsafe characters: #{unsafe_chars.join(', ')}"
      puts "Please avoid these characters: < > : \" | ? * \\ /"
      exit 1
    end

    # Use custom bundle directory if specified
    bundle_dir = options[:bundle_dir] || File.join(Dir.pwd, "vendor")

    puts "\nBundling #{matching_profiles.length} profile(s) into: #{bundle_name}.ini"

    bundle_file = bundle_profiles(matching_profiles, bundle_name, profile_type, bundle_dir, dir_path)
    if bundle_file
      puts "\n✓ Bundle completed successfully!"
      puts "  - Bundle file: #{File.basename(bundle_file)}"
      puts "  - Location: vendor folder"
    end

  elsif mode == "update"
    # Parse and apply update expressions
    update_expressions = options[:updates]

    # Parse each update expression
    parsed_updates = []
    update_expressions.each do |expr|
      # Parse expressions like "layer_height==+1" or "fill_overlap=40%"
      if expr.match(/^(\w+)==([+-]\d*\.?\d*)(%?|mm)?$/)
        # Relative update
        property = Regexp.last_match(1)
        operation = Regexp.last_match(2)[0]  # + or -
        amount = Regexp.last_match(2)[1..-1] # number part
        unit = Regexp.last_match(3) || ""
        parsed_updates << { type: :relative, property: property, operation: operation, amount: amount, unit: unit }
      elsif expr.match(/^(\w+)=(.+)$/)
        # Absolute update
        property = Regexp.last_match(1)
        value = Regexp.last_match(2)
        parsed_updates << { type: :absolute, property: property, value: value }
      else
        puts "Error: Invalid update expression: #{expr}"
        puts "Valid formats: property=value or property==+/-amount"
        exit 1
      end
    rescue StandardError => e
      puts "Error parsing update expression '#{expr}': #{e.message}"
      exit 1
    end

    puts "\nApplying updates to #{matching_profiles.length} profile(s):"

    # Apply updates to each matching profile
    files_to_update = {}

    matching_profiles.each do |profile|
      file_path = profile[:file_path]
      files_to_update[file_path] ||= []

      updated_properties = profile[:properties].dup
      changes_made = false

      parsed_updates.each do |update|
        property = update[:property]
        old_value = updated_properties[property]

        case update[:type]
        when :relative
          if old_value.nil?
            puts "Warning: Property '#{property}' not found in #{profile[:profile_name]}, skipping relative update"
            next
          end

          begin
            current_value, current_unit, is_integer = parse_value(old_value)
            amount = BigDecimal(update[:amount])

            new_value = case update[:operation]
                        when "+"
                          current_value + amount
                        when "-"
                          current_value - amount
                        end

            # Format the new value
            new_value_str = if is_integer && new_value == new_value.to_i
                              "#{new_value.to_i}#{current_unit}"
                            else
                              "#{new_value.to_f}#{current_unit}"
                            end

            updated_properties[property] = new_value_str
            puts "  #{profile[:profile_name]}: #{property} = #{old_value} -> #{new_value_str}"
            changes_made = true
          rescue StandardError => e
            puts "Warning: Could not apply relative update to #{property} in #{profile[:profile_name]}: #{e.message}"
          end

        when :absolute
          updated_properties[property] = update[:value]
          puts "  #{profile[:profile_name]}: #{property} = #{old_value || '(not set)'} -> #{update[:value]}"
          changes_made = true
        end
      end

      next unless changes_made

      files_to_update[file_path] << {
        profile_name: profile[:profile_name],
        properties: updated_properties.sort.to_h,
        comments: profile[:comments],
        lines: profile[:lines]
      }
    end

    # Write updated files
    files_to_update.each do |file_path, updated_profiles_for_file|
      # Load all profiles from the file
      parser = IniParser.new(profile_type, File.basename(file_path, ".ini"))
      all_profiles = parser.parse(file_path)

      # Update the modified profiles
      all_profiles.map! do |existing_profile|
        updated_profile = updated_profiles_for_file.find { |up| up[:profile_name] == existing_profile[:profile_name] }
        updated_profile || existing_profile
      end

      # Write the file back
      parser.write(file_path, all_profiles)
      puts "\nUpdated file: #{File.basename(file_path)}"
    end

    puts "\nUpdate completed."
  end
end
