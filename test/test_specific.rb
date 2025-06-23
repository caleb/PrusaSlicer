#!/usr/bin/env ruby

# Individual test runner for PrusaSlicer profile updater
# Usage: 
#   ruby test_specific.rb                           # Run all tests
#   ruby test_specific.rb test_bundle_parent_child  # Run specific test
#   ruby test_specific.rb --list                    # List all test methods

require "minitest/autorun"
require "minitest/reporters"
require_relative "test_bundle_functionality"

# Use a nice reporter
Minitest::Reporters.use! [
  Minitest::Reporters::SpecReporter.new(color: true, slow_threshold: 5.0)
]

if ARGV.include?("--list")
  puts "Available test methods:"
  TestPrusaProfileUpdater.instance_methods.grep(/^test_/).each do |method|
    puts "  #{method}"
  end
  exit
end

# If a specific test is requested, run only that test
if ARGV.length > 0 && !ARGV.first.start_with?("--")
  test_method = ARGV.first
  test_method = "test_#{test_method}" unless test_method.start_with?("test_")
  
  if TestPrusaProfileUpdater.instance_methods.include?(test_method.to_sym)
    puts "Running specific test: #{test_method}"
    puts "="*50
    
    # Create a test suite with just the requested method
    suite = Minitest::Test.new(test_method)
    suite.run
  else
    puts "Test method '#{test_method}' not found."
    puts "Use --list to see available tests."
    exit 1
  end
end

# Otherwise, all tests run automatically via minitest/autorun
