#!/usr/bin/env ruby

# Demonstration script for custom directory functionality
# Shows how to use --profile-dir and --bundle-dir options

require "tmpdir"
require "fileutils"

puts "PrusaSlicer Profile Bundler - Custom Directory Demo"
puts "=" * 50

# Create a temporary directory structure for demo
demo_dir = Dir.mktmpdir("prusa_demo")
puts "Created demo directory: #{demo_dir}"

custom_print_dir = File.join(demo_dir, "custom_profiles")
custom_bundle_dir = File.join(demo_dir, "custom_bundles")

FileUtils.mkdir_p(custom_print_dir)
FileUtils.mkdir_p(custom_bundle_dir)

# Create demo profiles
parent_content = <<~INI
  [print: DemoParent]
  layer_height = 0.2
  fill_density = 20%
  compatible_printers_condition = printer_model=~/.*Demo.*/
INI

child_content = <<~INI
  [print: DemoChild]
  inherits = DemoParent
  first_layer_height = 0.24
  fill_density = 30%
INI

File.write(File.join(custom_print_dir, "demo_parent.ini"), parent_content)
File.write(File.join(custom_print_dir, "demo_child.ini"), child_content)

puts "\nCreated demo profiles:"
puts "  - #{File.join(custom_print_dir, 'demo_parent.ini')}"
puts "  - #{File.join(custom_print_dir, 'demo_child.ini')}"

puts "\nDemo profiles created in: #{custom_print_dir}"
puts "Custom bundle directory: #{custom_bundle_dir}"

puts "\nTo test the custom directory functionality, run:"
puts "cd '#{File.dirname(File.dirname(__FILE__))}'"
puts "ruby update_prusa_profiles.rb bundle print --into DemoBundle --layer-height 0.2 \\"
puts "  --profile-dir '#{custom_print_dir}' \\"
puts "  --bundle-dir '#{custom_bundle_dir}'"

puts "\nThis will:"
puts "1. Look for profiles in #{custom_print_dir}"
puts "2. Create bundle in #{custom_bundle_dir}"
puts "3. Move DemoParent to bundle as *DemoParent*"
puts "4. Update DemoChild to inherit from *DemoParent*"

puts "\nAfter running, check:"
puts "- Bundle file: #{File.join(custom_bundle_dir, 'DemoBundle.ini')}"
puts "- Updated child: #{File.join(custom_print_dir, 'demo_child.ini')}"

puts "\nCleanup command:"
puts "rm -rf '#{demo_dir}'"

puts "\n" + "=" * 50
puts "Demo setup complete!"
