#!/usr/bin/env ruby

require 'bigdecimal'
require 'fileutils'

# Parse a value and its unit, returning [BigDecimal value, unit, is_integer]
def parse_value(value_str)
  # Match number with optional unit (e.g., "40%", "0.2mm", "100")
  match = value_str.match(/^(\d*\.?\d*)(%?|mm)?$/)
  raise "Invalid value format: #{value_str}" unless match

  num_str = match[1]
  unit = match[2] || ""
  is_integer = num_str !~ /\./
  value = BigDecimal(num_str)
  [value, unit, is_integer]
end

# Parse a relative adjustment (e.g., "= + 10%", "= - 0.1mm"), returning [operation, BigDecimal amount, unit]
def parse_relative_value(value_str)
  # Match "= [+|-] number [%|mm]" or "= [+|-] number"
  match = value_str.match(/^=\s*([+-])\s*(\d*\.?\d*)(%?|mm)?$/)
  raise "Invalid relative value format: #{value_str}" unless match

  op = match[1]
  amount = BigDecimal(match[2])
  unit = match[3] || ""
  [op, amount, unit]
end

# Format a BigDecimal value based on original integer status
def format_value(value, unit, original_is_integer)
  if value.frac == 0 && original_is_integer
    "#{value.to_i}#{unit}"
  else
    # Format with up to 4 decimal places, removing trailing zeros
    formatted = value.round(4).to_s('F').sub(/\.?0+$/, '')
    "#{formatted}#{unit}"
  end
end

# Preview changes for a single file, returning [old_value, new_value, line_index, new_line] or nil if unchanged
def preview_change(file_path, property, value)
  begin
    content = File.read(file_path)
    lines = content.lines
    found = false
    old_value = nil
    new_value = nil
    new_line = nil
    insert_index = nil

    # Check if property exists and get its current value
    lines.each_with_index do |line, index|
      if line.match?(/^\s*#{Regexp.escape(property)}\s*=/)
        found = true
        old_value = line.split('=', 2)[1].strip
        if value.start_with?('=')
          # Relative adjustment
          op, amount, rel_unit = parse_relative_value(value)
          current_value, current_unit, current_is_integer = parse_value(old_value)
          raise "Unit mismatch: expected #{rel_unit}, got #{current_unit}" unless rel_unit == current_unit

          new_value = op == '+' ? current_value + amount : current_value - amount
          new_value = [new_value, BigDecimal('0')].max if current_unit.empty? && new_value < 0 # Prevent negative for unitless
          new_value_str = format_value(new_value, current_unit, current_is_integer)
        else
          # Absolute value
          new_value_str = value
        end
        new_line = "#{property} = #{new_value_str}\n"
        return [old_value, new_value_str, index, new_line]
      end
    end

    # If property not found, determine insertion point for alphabetical order
    unless found
      old_value = "(not set)"
      new_value = value.start_with?('=') ? "(cannot apply relative change)" : value
      return nil if value.start_with?('=')
      new_line = "#{property} = #{new_value}\n"

      # Find all property lines and their keys
      property_lines = []
      lines.each_with_index do |line, index|
        if line.match?(/^\s*(\w+)\s*=/)
          key = line.split('=', 2)[0].strip
          property_lines << [key, index]
        end
      end

      # Find insertion point
      insert_index = lines.length
      property_lines.each do |key, index|
        if key > property
          insert_index = index
          break
        end
      end

      return [old_value, new_value, insert_index, new_line]
    end

    nil
  rescue StandardError => e
    puts "Error previewing #{file_path}: #{e.message}"
    nil
  end
end

# Apply changes to a single file using the preview data
def apply_change(file_path, preview_data)
  return unless preview_data
  _old_value, _new_value, line_index, new_line = preview_data

  begin
    lines = File.read(file_path).lines
    if line_index < lines.length
      if lines[line_index].match?(/^\s*#{Regexp.escape(_new_value.split('=')[0].strip)}\s*=/)
        lines[line_index] = new_line
      else
        lines.insert(line_index, new_line)
      end
    else
      lines << new_line
    end
    File.write(file_path, lines.join)
  rescue StandardError => e
    puts "Error applying changes to #{file_path}: #{e.message}"
  end
end

# Main loop
loop do
  begin
    print "Enter property name (or Ctrl+C/Ctrl+D to exit): "
    property = gets&.chomp
    break if property.nil? # Ctrl+D

    next if property.empty?
    print "Enter value (e.g., '40%', '0.2mm', '= + 10%'): "
    value = gets&.chomp
    break if value.nil? # Ctrl+D

    next if value.empty?

    # Find all .ini files in current directory
    ini_files = Dir.glob("*.ini")
    if ini_files.empty?
      puts "No .ini files found in current directory."
      next
    end

    # Preview changes
    previews = []
    ini_files.each do |file|
      preview = preview_change(file, property, value)
      previews << [file, preview] if preview
    end

    # Display preview
    if previews.empty?
      puts "No changes to apply."
      next
    end

    puts "\nProposed changes:"
    previews.each do |file, preview|
      old_value, new_value, _index, _new_line = preview
      puts "#{file}: #{old_value} -> #{new_value}"
    end

    # Ask for confirmation
    print "\nAre these changes acceptable? (y/n): "
    confirmation = gets&.chomp&.downcase
    break if confirmation.nil? # Ctrl+D

    if confirmation == 'y'
      # Apply changes
      changed_files = []
      previews.each do |file, preview|
        apply_change(file, preview)
        old_value, new_value, _index, _new_line = preview
        changed_files << [file, old_value, new_value]
      end

      # Display applied changes
      puts "\nChanges applied:"
      changed_files.each do |file, old_value, new_value|
        puts "#{file}: #{old_value} -> #{new_value}"
      end
    else
      puts "\nChanges discarded."
    end
    puts ""
  rescue Interrupt # Ctrl+C
    puts "\nExiting..."
    break
  rescue StandardError => e
    puts "Error: #{e.message}"
    next
  end
end