#!/usr/bin/env ruby

# Test runner for PrusaSlicer profile updater
# This script runs the test suite with proper setup and reporting

require "minitest/autorun"

# Try to use minitest-reporters if available, otherwise use default
begin
  require "minitest/reporters"
  Minitest::Reporters.use! [
    Minitest::Reporters::SpecReporter.new(color: true, slow_threshold: 5.0)
  ]
rescue LoadError
  # Use default minitest output if reporters gem is not available
  puts "Note: Install 'minitest-reporters' gem for prettier output: gem install minitest-reporters"
end

# Load the test file
require_relative "test_bundle_functionality"

puts "\n" + "="*60
puts "PrusaSlicer Profile Bundle Functionality Test Suite"
puts "="*60
puts "Testing the enhanced bundle command functionality including:"
puts "- Profile inheritance detection and management"
puts "- Parent profile privatization with asterisks"
puts "- Leaf vs non-leaf profile identification"
puts "- Cross-file inheritance reference updates"
puts "- Bundle file creation and management"
puts "- Error handling and edge cases"
puts "="*60
puts ""

# The tests will run automatically due to minitest/autorun
