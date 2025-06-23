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
      if profile[:profile_name] != "#{@profile_type}: #{@default_stanza_name}" || !profile[:properties].empty? || !profile[:comments].empty?
        # Format stanza header: remove space after colon for bundled profiles (those with asterisks)
        header = profile[:profile_name]
        if header.include?("*")
          # For bundled profiles, format as [print:*ProfileName*] (no space after colon)
          header = header.sub(/^(#{@profile_type}):\s*(.*)$/, '\\1:\\2')
        end
        new_lines << "[#{header}]\n"
      end
      # Write only meaningful comments (not blank lines)
      profile[:lines].each do |line|
        clean_line = line.split("#").first.strip
        # Skip property lines, stanza headers, and blank lines
        next if clean_line.match?(/^\s*\w+\s*=/) || clean_line.match?(/^\s*\[.*\]\s*$/) || clean_line.empty?

        # Only include lines that have comments
        new_lines << line if line.include?("#")
      end
      # Write properties (no blank line between header and properties)
      profile[:properties].each do |key, value|
        new_lines << "#{key} = #{value}\n"
      end
      # Only add blank line after the last property if this isn't the last profile
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

# Find common properties across profiles, excluding properties that should stay in children
def find_common_properties(profiles)
  return {} if profiles.empty?

  common = profiles.first[:properties].dup
  profiles[1..-1].each do |profile|
    common.keep_if { |k, v| profile[:properties][k] == v }
  end

  # Remove child-only properties from common properties
  get_child_only_properties.each { |prop| common.delete(prop) }

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

  # No longer searching for or updating descendant profiles
  # We will only update the selected profiles' inherits property
  puts "\nNote: Only updating selected profiles' inheritance, not descendants"

  # Check if all profiles inherit from the same parent
  inherit_values = matching_profiles.map { |profile| profile[:properties]["inherits"] }.uniq
  common_parent = nil
  if inherit_values.length == 1
    # All profiles have the same inherits value (could be nil)
    common_parent = inherit_values.first
    # Remove 'inherits' from parent_properties since we'll handle it specially
    parent_properties.delete("inherits")
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

        # Alphabetize
        updated_properties = updated_properties.sort.to_h

        {
          profile_name: file_profile[:profile_name],
          properties: updated_properties,
          comments: file_profile[:comments],
          lines: file_profile[:lines]
        }
      else
        # Keep other profiles unchanged
        {
          profile_name: file_profile[:profile_name],
          properties: file_profile[:properties],
          comments: file_profile[:comments],
          lines: file_profile[:lines]
        }
      end
    end

    # Write updated file
    parser.write(file_path, updated_profiles)
    puts "Updated profiles in: #{File.basename(file_path)}"
  end

  # Store info for reporting
  @deleted_files = [] # No files deleted in this new approach
  @included_descendants_count = 0 # No longer processing descendants
  @files_processed = files_processed

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

  # Find common properties among profiles being bundled
  common_properties = find_common_properties(non_leaf_profiles)
  puts "Found #{common_properties.length} common properties to extract to parent"

  # Check if all profiles inherit from the same parent
  inherit_values = non_leaf_profiles.map { |profile| profile[:properties]["inherits"] }.uniq
  common_parent = nil
  if inherit_values.length == 1
    # All profiles have the same inherits value (could be nil)
    common_parent = inherit_values.first
    # Remove 'inherits' from common_properties since we'll handle it specially
    common_properties.delete("inherits")
  end

  # Create bundle parent profile name
  bundle_parent_name = "#{profile_type}: *#{bundle_name}*"

  # Create bundle parent profile
  bundle_parent_profile = {
    profile_name: bundle_parent_name,
    properties: common_properties.dup,
    comments: [],
    lines: []
  }

  # Add inherits to parent if all child profiles inherited from the same profile
  if common_parent
    bundle_parent_profile[:properties]["inherits"] = common_parent
    bundle_parent_profile[:properties] = bundle_parent_profile[:properties].sort.to_h
  end

  # Prepare non-leaf profiles for the bundle with privatized names
  bundle_profiles = [bundle_parent_profile] # Start with parent
  existing_names = existing_bundle_profiles.map { |p| p[:profile_name] }

  # Skip adding parent if it already exists
  if existing_names.include?(bundle_parent_name)
    puts "Bundle parent already exists: #{bundle_parent_name}"
    bundle_profiles = []
  else
    puts "Created bundle parent: #{bundle_parent_name}"
  end

  non_leaf_profiles.each do |profile|
    base_name = profile[:profile_name].sub(/^#{profile_type}:\s*/, "")
    privatized_name = name_mapping[base_name] || base_name
    privatized_profile_name = "#{profile_type}: #{privatized_name}"

    # Skip if already exists in bundle
    if existing_names.include?(privatized_profile_name)
      puts "Skipping duplicate in bundle: #{privatized_profile_name}"
      next
    end

    # Create cleaned properties by removing common ones
    cleaned_properties = profile[:properties].dup

    # Remove common properties (they're now in the parent)
    common_properties.each_key { |k| cleaned_properties.delete(k) }

    # Remove the original inherits property and add inherits to bundle parent
    cleaned_properties.delete("inherits")
    cleaned_properties["inherits"] = "*#{bundle_name}*"

    # Alphabetize
    cleaned_properties = cleaned_properties.sort.to_h

    bundle_profile = {
      profile_name: privatized_profile_name,
      properties: cleaned_properties,
      comments: profile[:comments],
      lines: profile[:lines]
    }

    bundle_profiles << bundle_profile
    puts "Bundled profile: #{privatized_name} (inherits from *#{bundle_name}*)"
  end

  # Combine with existing bundle profiles
  all_bundle_profiles = existing_bundle_profiles + bundle_profiles

  # Write the bundle file with vendor stanza
  write_bundle_file_with_vendor_stanza(bundle_file_path, all_bundle_profiles, bundle_name, profile_type)
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
  files_to_delete = []

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
      if file_profiles.empty?
        # Delete the file if it has no profiles left
        File.delete(file_path)
        files_to_delete << file_path
        puts "Deleted empty file: #{File.basename(file_path)}"
      else
        # Update the file with remaining profiles
        parser.write(file_path, file_profiles)
        puts "Removed #{removed_count} profile(s) from #{File.basename(file_path)}"
      end
    end
  end

  puts "\n✓ Bundle operation completed:"
  puts "  - Created bundle parent: *#{bundle_name}* with #{common_properties.length} common properties"
  puts "  - Moved #{non_leaf_profiles.length} non-leaf profile(s) to bundle (privatized)"
  puts "  - Left #{leaf_profiles.length} leaf profile(s) in original locations"
  puts "  - Updated inheritance in #{files_updated} file(s)"
  puts "  - Deleted #{files_to_delete.length} empty file(s)" if files_to_delete.length > 0
  puts "  - Bundle file: #{File.basename(bundle_file_path)}"

  bundle_file_path
rescue StandardError => e
  location = caller_locations(1, 1).first
  puts "Error in #{File.basename(__FILE__)} at #{location.label} (line ~#{location.lineno}): #{e.message}"
  nil
end

# Write bundle file with vendor stanza at the top
def write_bundle_file_with_vendor_stanza(bundle_file_path, bundle_profiles, bundle_name, profile_type)
  lines = []

  # Add vendor stanza at the top
  lines << "[vendor]\n"
  lines << "repo_id = non-prusa-fff\n"
  lines << "# Vendor name will be shown by the Config Wizard.\n"
  lines << "name = #{bundle_name}\n"
  lines << "# Configuration version of this file. Config file will only be installed, if the config_version differs.\n"
  lines << "# This means, the server may force the PrusaSlicer configuration to be downgraded.\n"
  lines << "config_version = 2.1.0\n"
  lines << "\n"

  # Write profile stanzas
  bundle_profiles.each do |profile|
    # Format stanza header: remove space after colon for bundled profiles (those with asterisks)
    header = profile[:profile_name]
    if header.include?("*")
      # For bundled profiles, format as [print:*ProfileName*] (no space after colon)
      header = header.sub(/^(#{profile_type}):\s*(.*)$/, '\\1:\\2')
    end
    lines << "[#{header}]\n"

    # Write only meaningful comments (not blank lines)
    profile[:lines].each do |line|
      clean_line = line.split("#").first.strip
      # Skip property lines, stanza headers, and blank lines
      next if clean_line.match?(/^\s*\w+\s*=/) || clean_line.match?(/^\s*\[.*\]\s*$/) || clean_line.empty?

      # Only include lines that have comments
      lines << line if line.include?("#")
    end

    # Write properties (no blank line between header and properties)
    profile[:properties].each do |key, value|
      lines << "#{key} = #{value}\n"
    end
    # Only add blank line after the last property if this isn't the last profile
    lines << "\n" unless lines.last == "\n"
  end

  File.write(bundle_file_path, lines.join)
rescue StandardError => e
  location = caller_locations(1, 1).first
  puts "Error in #{File.basename(__FILE__)} at #{location.label} (line ~#{location.lineno}): #{e.message}"
end

# Get all inherited properties by following the inheritance chain
def get_inherited_properties(profile, all_profiles, visited = Set.new)
  inherited_properties = {}

  # Avoid infinite loops
  profile_key = profile[:profile_name]
  return inherited_properties if visited.include?(profile_key)

  visited.add(profile_key)

  inherits_value = profile[:properties]["inherits"]
  return inherited_properties unless inherits_value && !inherits_value.empty?

  # Find the parent profile
  parent_profile = all_profiles.find do |p|
    profile_inherits_from?(profile, p[:profile_name])
  end

  if parent_profile
    # Get properties from further up the inheritance chain first
    inherited_properties = get_inherited_properties(parent_profile, all_profiles, visited)

    # Override with parent's own properties
    parent_profile[:properties].each do |key, value|
      next if key == "inherits" # Don't inherit the inherits property itself

      inherited_properties[key] = value
    end
  end

  inherited_properties
rescue StandardError => e
  location = caller_locations(1, 1).first
  puts "Error in #{File.basename(__FILE__)} at #{location.label} (line ~#{location.lineno}): #{e.message}"
  {}
end

# Clean a profile by removing properties that match inherited values
def clean_profile_properties(profile, all_profiles)
  inherited_properties = get_inherited_properties(profile, all_profiles)
  cleaned_properties = {}

  profile[:properties].each do |key, value|
    # Always keep the inherits property
    if key == "inherits"
      cleaned_properties[key] = value
    # Keep properties that are different from inherited values or not inherited
    elsif !inherited_properties.key?(key) || inherited_properties[key] != value
      cleaned_properties[key] = value
    end
  end

  cleaned_properties.sort.to_h
rescue StandardError => e
  location = caller_locations(1, 1).first
  puts "Error in #{File.basename(__FILE__)} at #{location.label} (line ~#{location.lineno}): #{e.message}"
  profile[:properties]
end

# Clean all profiles in a directory by removing redundant inherited properties
def clean_profiles(profile_type, custom_profile_dir = nil)
  # Determine profile directory
  profile_dir = custom_profile_dir || File.join(Dir.pwd, profile_type)

  unless Dir.exist?(profile_dir)
    puts "Directory '#{profile_dir}' does not exist."
    return false
  end

  # Check vendor directory for inheritance analysis only (don't modify bundles)
  vendor_dir = File.join(Dir.pwd, "vendor")

  puts "Loading all #{profile_type} profiles..."

  # Load target files (files to be cleaned)
  target_ini_files = Dir.glob(File.join(profile_dir, "*.ini"))

  # Load ALL profiles for inheritance analysis (from both target and vendor directories)
  all_ini_files = target_ini_files.dup
  all_ini_files += Dir.glob(File.join(vendor_dir, "*.ini")) if Dir.exist?(vendor_dir)

  all_profiles = []
  all_ini_files.each do |file|
    parser = IniParser.new(profile_type, File.basename(file, ".ini"))
    profiles = parser.parse(file)
    all_profiles.concat(profiles)
  end
  puts "Loaded #{all_profiles.length} total profiles from #{all_ini_files.length} files for inheritance analysis"

  # Group target profiles by file for processing (only files in target directory)
  files_to_process = {}
  target_profiles = all_profiles.select { |profile| target_ini_files.include?(profile[:file_path]) }

  target_profiles.each do |profile|
    file_path = profile[:file_path]
    files_to_process[file_path] ||= []
    files_to_process[file_path] << profile
  end

  # Clean profiles and track changes
  files_changed = 0
  total_properties_removed = 0

  files_to_process.each do |file_path, file_profiles|
    file_changed = false
    file_properties_removed = 0

    cleaned_profiles = file_profiles.map do |profile|
      original_count = profile[:properties].length
      cleaned_properties = clean_profile_properties(profile, all_profiles)
      new_count = cleaned_properties.length

      properties_removed = original_count - new_count
      if properties_removed > 0
        puts "  #{profile[:profile_name]}: removed #{properties_removed} redundant properties"
        file_changed = true
        file_properties_removed += properties_removed
      end

      {
        profile_name: profile[:profile_name],
        properties: cleaned_properties,
        comments: profile[:comments],
        lines: profile[:lines]
      }
    end

    # Write back the cleaned profiles if changes were made
    next unless file_changed

    parser = IniParser.new(profile_type, File.basename(file_path, ".ini"))
    parser.write(file_path, cleaned_profiles)
    puts "Cleaned #{File.basename(file_path)}: removed #{file_properties_removed} properties"
    files_changed += 1
    total_properties_removed += file_properties_removed
  end

  puts "\n✓ Clean operation completed:"
  puts "  - Files processed: #{files_to_process.length}"
  puts "  - Files changed: #{files_changed}"
  puts "  - Total properties removed: #{total_properties_removed}"

  true
rescue StandardError => e
  location = caller_locations(1, 1).first
  puts "Error in #{File.basename(__FILE__)} at #{location.label} (line ~#{location.lineno}): #{e.message}"
  false
end

# Clean bundle file - removes redundant properties and creates inheritance within the bundle
def clean_bundle_file(bundle_name, bundle_dir = nil)
  bundle_dir ||= File.join(Dir.pwd, "vendor")
  bundle_file_path = File.join(bundle_dir, "#{bundle_name}.ini")

  unless File.exist?(bundle_file_path)
    puts "Error: Bundle file not found: #{File.basename(bundle_file_path)}"
    return false
  end

  puts "Cleaning bundle file: #{File.basename(bundle_file_path)}"

  # Parse the bundle file and group profiles by type
  content = File.read(bundle_file_path)
  all_bundle_profiles = []
  profile_groups = {}

  # Detect all profile types in the bundle
  profile_types = []
  profile_types << "print" if content.include?("[print:")
  profile_types << "filament" if content.include?("[filament:")
  profile_types << "printer" if content.include?("[printer:")
  profile_types << "printer_model" if content.include?("[printer_model:")

  # Default to print if no specific type detected
  if profile_types.empty?
    profile_types = ["print"]
    puts "Warning: Could not determine profile types from bundle content, assuming print profiles"
  end

  puts "Detected profile types: #{profile_types.join(', ')}"

  # Parse each profile type
  profile_types.each do |profile_type|
    parser = IniParser.new(profile_type, bundle_name)
    profiles = parser.parse(bundle_file_path)

    # Filter profiles to only include the current type
    type_profiles = profiles.select { |p| p[:profile_name].start_with?("#{profile_type}:") }

    next unless type_profiles.any?

    puts "Found #{type_profiles.length} #{profile_type} profiles in bundle"
    profile_groups[profile_type] = type_profiles
    all_bundle_profiles.concat(type_profiles)
  end

  # Load ALL profiles from directories to build complete inheritance graph
  puts "Loading external profiles for inheritance analysis..."
  all_external_profiles = []

  profile_types.each do |profile_type|
    # Add profiles from the regular profile directories
    profile_dir = File.join(Dir.pwd, profile_type)
    if Dir.exist?(profile_dir)
      all_ini_files = Dir.glob(File.join(profile_dir, "*.ini"))
      all_ini_files.each do |file|
        file_parser = IniParser.new(profile_type, File.basename(file, ".ini"))
        file_profiles = file_parser.parse(file)
        all_external_profiles.concat(file_profiles)
      end
    end

    # Add profiles from other bundle files
    vendor_dir = File.join(Dir.pwd, "vendor")
    next unless Dir.exist?(vendor_dir)

    Dir.glob(File.join(vendor_dir, "*.ini")).each do |file|
      next if file == bundle_file_path # Skip the current bundle file

      file_parser = IniParser.new(profile_type, File.basename(file, ".ini"))
      file_profiles = file_parser.parse(file)
      all_external_profiles.concat(file_profiles)
    end
  end

  puts "Loaded #{all_external_profiles.length} external profiles for inheritance analysis"

  # Process each profile type separately
  optimized_profiles = []
  total_properties_removed = 0
  total_profiles_changed = 0

  profile_groups.each do |profile_type, type_profiles|
    puts "\n--- Optimizing #{profile_type} profiles ---"

    # Skip optimization if only one profile of this type
    if type_profiles.length < 2
      puts "Only #{type_profiles.length} #{profile_type} profile, skipping optimization"
      optimized_profiles.concat(type_profiles)
      next
    end

    # Find common properties among all profiles of this type
    common_properties = find_common_properties(type_profiles)
    puts "Found #{common_properties.length} common properties among #{profile_type} profiles"

    if common_properties.length < 3 # Don't create parent for very few common properties
      puts "Too few common properties, skipping parent creation"
      # Still clean existing inheritance
      all_profiles_for_type = type_profiles + all_external_profiles.select { |p| p[:profile_name].start_with?("#{profile_type}:") }

      type_profiles.each do |profile|
        original_count = profile[:properties].size
        cleaned_properties = clean_profile_properties(profile, all_profiles_for_type)

        next unless cleaned_properties.size < original_count

        total_properties_removed += original_count - cleaned_properties.size
        total_profiles_changed += 1
        puts "  #{profile[:profile_name]}: removed #{original_count - cleaned_properties.size} redundant properties"

        profile[:properties] = cleaned_properties
      end

      optimized_profiles.concat(type_profiles)
      next
    end

    # Check if all profiles inherit from the same parent
    inherit_values = type_profiles.map { |profile| profile[:properties]["inherits"] }.uniq
    common_parent = nil
    if inherit_values.length == 1
      common_parent = inherit_values.first
      # Remove 'inherits' from common_properties since we'll handle it specially
      common_properties.delete("inherits")
    end

    # Create bundle parent profile name
    bundle_parent_name = "#{profile_type}: *#{bundle_name}*"

    # Check if parent already exists
    existing_parent = type_profiles.find { |p| p[:profile_name] == bundle_parent_name }

    if existing_parent
      puts "Bundle parent already exists: #{bundle_parent_name}"
      # Update existing parent with common properties
      existing_parent[:properties] = common_properties.dup
      existing_parent[:properties]["inherits"] = common_parent if common_parent
      existing_parent[:properties] = existing_parent[:properties].sort.to_h

      # Remove parent from the list to process children
      child_profiles = type_profiles.reject { |p| p[:profile_name] == bundle_parent_name }
    else
      puts "Creating bundle parent: #{bundle_parent_name}"

      # Create bundle parent profile
      bundle_parent_profile = {
        profile_name: bundle_parent_name,
        properties: common_properties.dup,
        comments: [],
        lines: [],
        file_path: bundle_file_path
      }

      # Add inherits to parent if all child profiles inherited from the same profile
      bundle_parent_profile[:properties]["inherits"] = common_parent if common_parent
      bundle_parent_profile[:properties] = bundle_parent_profile[:properties].sort.to_h

      optimized_profiles << bundle_parent_profile
      child_profiles = type_profiles
    end

    # Process child profiles
    child_profiles.each do |profile|
      original_count = profile[:properties].size

      # Remove common properties (they're now in the parent)
      cleaned_properties = profile[:properties].dup
      common_properties.each_key { |k| cleaned_properties.delete(k) }

      # Update inheritance
      cleaned_properties.delete("inherits")
      cleaned_properties["inherits"] = "*#{bundle_name}*"
      cleaned_properties = cleaned_properties.sort.to_h

      properties_removed = original_count - cleaned_properties.size
      if properties_removed > 0
        total_properties_removed += properties_removed
        total_profiles_changed += 1
        puts "  #{profile[:profile_name]}: removed #{properties_removed} redundant properties, now inherits from *#{bundle_name}*"
      end

      profile[:properties] = cleaned_properties
    end

    # Add the existing parent if it was already there
    optimized_profiles << existing_parent if existing_parent

    optimized_profiles.concat(child_profiles)
  end

  # Second pass: look for additional common properties among children that can be moved to parent
  puts "\n--- Second optimization pass: finding additional common properties ---"
  second_pass_properties_removed = 0
  second_pass_profiles_changed = 0

  profile_groups.each do |profile_type, _type_profiles|
    # Find the parent profile for this type
    bundle_parent_name = "#{profile_type}: *#{bundle_name}*"
    parent_profile = optimized_profiles.find { |p| p[:profile_name] == bundle_parent_name }

    next unless parent_profile

    # Get the child profiles for this type (those that inherit from the parent)
    child_profiles = optimized_profiles.select do |p|
      p[:profile_name].start_with?("#{profile_type}:") &&
        p[:profile_name] != bundle_parent_name &&
        p[:properties]["inherits"] == "*#{bundle_name}*"
    end

    next if child_profiles.length < 2

    puts "Analyzing #{child_profiles.length} #{profile_type} children for additional common properties..."

    # Find properties that are the same across all children (excluding child-only properties)
    additional_common_properties = {}
    if child_profiles.any?
      # Get list of properties that should never be moved to parent
      child_only_properties = get_child_only_properties

      # Start with properties from the first child (excluding child-only properties)
      first_child_properties = child_profiles.first[:properties].reject { |k, _v| child_only_properties.include?(k) }

      first_child_properties.each do |property, value|
        # Check if all other children have the exact same value for this property
        additional_common_properties[property] = value if child_profiles.all? { |child| child[:properties][property] == value }
      end
    end

    if additional_common_properties.any?
      puts "Found #{additional_common_properties.length} additional common properties among #{profile_type} children:"
      additional_common_properties.each { |k, v| puts "  #{k} = #{v}" }

      # Move these properties to the parent
      additional_common_properties.each do |property, value|
        parent_profile[:properties][property] = value
      end
      parent_profile[:properties] = parent_profile[:properties].sort.to_h

      # Remove these properties from all children
      child_profiles.each do |child|
        properties_removed = 0
        additional_common_properties.each_key do |property|
          properties_removed += 1 if child[:properties].delete(property)
        end

        next unless properties_removed > 0

        second_pass_properties_removed += properties_removed
        second_pass_profiles_changed += 1
        puts "  #{child[:profile_name]}: moved #{properties_removed} additional properties to parent"
      end
    else
      puts "No additional common properties found among #{profile_type} children"
    end
  end

  total_properties_removed += second_pass_properties_removed
  total_profiles_changed += second_pass_profiles_changed

  # Third phase: Clean external profiles that inherit from bundle profiles
  puts "\n--- Cleaning external profiles that inherit from bundle profiles ---"
  external_properties_removed = 0
  external_profiles_changed = 0
  external_files_changed = 0

  # Build a list of all profile names from this bundle
  bundle_profile_names = all_bundle_profiles.map { |p| p[:profile_name] }

  profile_types.each do |profile_type|
    profile_dir = File.join(Dir.pwd, profile_type)
    next unless Dir.exist?(profile_dir)

    all_ini_files = Dir.glob(File.join(profile_dir, "*.ini"))

    all_ini_files.each do |file_path|
      file_parser = IniParser.new(profile_type, File.basename(file_path, ".ini"))
      file_profiles = file_parser.parse(file_path)
      file_changed = false

      updated_profiles = file_profiles.map do |profile|
        # Check if this profile inherits from any profile in the bundle
        inherits_from_bundle = false
        if profile[:properties]["inherits"]
          bundle_profile_names.each do |bundle_profile_name|
            if profile_inherits_from?(profile, bundle_profile_name)
              inherits_from_bundle = true
              break
            end
          end
        end

        if inherits_from_bundle
          # Clean this profile using all profiles (including bundle profiles)
          all_profiles_for_cleaning = all_bundle_profiles + all_external_profiles

          original_count = profile[:properties].length
          cleaned_properties = clean_profile_properties(profile, all_profiles_for_cleaning)
          new_count = cleaned_properties.length

          properties_removed = original_count - new_count
          if properties_removed > 0
            puts "  #{profile[:profile_name]}: removed #{properties_removed} redundant properties"
            external_properties_removed += properties_removed
            external_profiles_changed += 1
            file_changed = true
          end

          {
            profile_name: profile[:profile_name],
            properties: cleaned_properties,
            comments: profile[:comments],
            lines: profile[:lines]
          }
        else
          # Keep profile unchanged
          profile
        end
      end

      next unless file_changed

      file_parser.write(file_path, updated_profiles)
      external_files_changed += 1
      puts "Cleaned external file: #{File.basename(file_path)}"
    end
  end

  total_properties_removed += external_properties_removed
  total_profiles_changed += external_profiles_changed

  if total_properties_removed > 0 || total_profiles_changed > 0
    # Write back the bundle file with vendor stanza preserved
    # We need to determine a primary profile type for the write operation
    primary_type = profile_types.first
    write_bundle_file_with_vendor_stanza(bundle_file_path, optimized_profiles, bundle_name, primary_type)
    puts "\nCleaned #{File.basename(bundle_file_path)}:"
    puts "  - Removed #{total_properties_removed} total redundant properties"
    puts "  - Modified #{total_profiles_changed} profiles"
    puts "  - Updated #{external_files_changed} external files"
    puts "  - Created/updated inheritance structure within bundle"
  else
    puts "No optimization opportunities found in #{File.basename(bundle_file_path)}"
  end

  true
rescue StandardError => e
  location = caller_locations(1, 1).first
  puts "Error cleaning bundle file: #{e.message}"
  puts "Location: #{File.basename(__FILE__)} at #{location.label} (line ~#{location.lineno})"
  false
end

# Get list of properties that should never be moved to parent profiles
def get_child_only_properties
  [
    "compatible_printers_condition", # Printer/nozzle specific conditions
    "compatible_printers", # Specific printer lists
    "filament_vendor",              # Vendor-specific for filament profiles
    "printer_model",                # Model-specific for printer profiles
    "nozzle_diameter",              # Nozzle-specific settings
    "inherits"                      # Inheritance chain should not be moved
  ]
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
    bundle_name: nil,
    updates: [],
    profile_dir: nil,
    bundle_dir: nil
  }

  parser = OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} <command> [arguments...] [options]"
    opts.separator ""
    opts.separator "Commands:"
    opts.separator "  combine <profile_type> --into <name>   Combine matching profiles into a new parent profile"
    opts.separator "  bundle <profile_type> --into <name>    Bundle matching profiles into a single file in vendor folder"
    opts.separator "  update <profile_type> [expressions]    Update properties in matching profiles"
    opts.separator "  clean [print|filament|bundle] [name]   Remove redundant properties that match inherited values"
    opts.separator ""
    opts.separator "Profile Types:"
    opts.separator "  print      Print profiles"
    opts.separator "  filament   Filament profiles"
    opts.separator ""
    opts.separator "Clean Command Usage:"
    opts.separator "  clean                    Clean both print and filament profiles"
    opts.separator "  clean print              Clean only print profiles"
    opts.separator "  clean filament           Clean only filament profiles"
    opts.separator "  clean bundle <name>      Clean specific bundle file"
    opts.separator "  clean <bundle_name>      Clean specific bundle file (shorthand)"
    opts.separator ""
    opts.separator "Options (for combine, bundle, update commands only):"

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
  unless %w[combine bundle update clean].include?(options[:mode])
    puts "Error: Invalid command '#{options[:mode]}'. Use 'combine', 'bundle', 'update', or 'clean'"
    puts parser
    exit 1
  end

  # Handle clean command which has different argument structure
  if options[:mode] == "clean"
    # For clean command: clean [type] [bundle_name]
    # If no args: clean all types
    # If one arg: clean specific type OR clean bundle with bundle_name
    # If two args: clean bundle bundle_name

    if remaining_args.empty?
      # Clean all types (both print and filament)
      options[:profile_type] = "all"
    elsif remaining_args.length == 1
      arg = remaining_args[0]
      if %w[print filament bundle].include?(arg)
        options[:profile_type] = arg
      else
        # Assume it's a bundle name
        options[:profile_type] = "bundle"
        options[:bundle_name] = arg
      end
    elsif remaining_args.length == 2 && remaining_args[0] == "bundle"
      options[:profile_type] = "bundle"
      options[:bundle_name] = remaining_args[1]
    else
      puts "Error: Invalid arguments for clean command"
      puts "Usage: clean [print|filament|bundle] [bundle_name]"
      exit 1
    end

    return options
  end

  # For other commands, second argument should be the profile type
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
    # Use --tag or --sub-profile (they're the same thing for tag filtering)
    filters[:sub_profile] = options[:tag] || options[:sub_profile] || ""
  end

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

  # Handle clean command specially since it can work with "all" or "bundle" types
  if mode == "clean"
    case profile_type
    when "all"
      puts "\nCleaning all profile types..."

      # Clean print profiles
      puts "\n--- Cleaning print profiles ---"
      print_success = clean_profiles("print", options[:profile_dir])

      # Clean filament profiles
      puts "\n--- Cleaning filament profiles ---"
      filament_success = clean_profiles("filament", options[:profile_dir])

      if print_success && filament_success
        puts "\n✓ Clean operation completed successfully for all profile types!"
      else
        puts "\n✗ Clean operation failed for one or more profile types"
        exit 1
      end

    when "print", "filament"
      puts "\nCleaning #{profile_type} profiles..."

      # Use custom profile directory if specified
      profile_dir = options[:profile_dir] if options[:profile_dir]

      success = clean_profiles(profile_type, profile_dir)
      if success
        puts "\n✓ Clean operation completed successfully!"
      else
        puts "\n✗ Clean operation failed"
        exit 1
      end

    when "bundle"
      bundle_name = options[:bundle_name]
      if bundle_name.nil?
        puts "Error: Bundle name is required for bundle cleaning"
        exit 1
      end

      puts "\nCleaning bundle: #{bundle_name}"

      # Use custom bundle directory if specified
      bundle_dir = options[:bundle_dir] if options[:bundle_dir]

      success = clean_bundle_file(bundle_name, bundle_dir)
      if success
        puts "\n✓ Bundle clean operation completed successfully!"
      else
        puts "\n✗ Bundle clean operation failed"
        exit 1
      end

    else
      puts "Error: Invalid profile type for clean command: #{profile_type}"
      exit 1
    end

    exit 0 # Exit after handling clean command
  end

  # For other commands, continue with standard processing
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
