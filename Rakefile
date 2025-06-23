#!/usr/bin/env ruby
# frozen_string_literal: true

require 'rake/testtask'
require 'bundler/setup'

# Default task
desc "Run all tests"
task default: :test

# Main test task - runs all tests in both locations
desc "Run all test files"
task :test do
  puts "🧪 Running PrusaSlicer Profile Bundle Test Suite"
  puts "=" * 60
  
  # Find all test files in both root and test directory
  test_files = []
  test_files += Dir.glob("test_*.rb")           # Root directory test files
  test_files += Dir.glob("test/test_*.rb")      # Test directory files
  
  if test_files.empty?
    puts "❌ No test files found!"
    exit 1
  end
  
  puts "📁 Found test files:"
  test_files.each { |file| puts "   - #{file}" }
  puts
  
  # Run each test file
  success = true
  test_files.each do |test_file|
    puts "🔄 Running #{test_file}..."
    result = system("ruby #{test_file}")
    unless result
      puts "❌ #{test_file} failed!"
      success = false
    else
      puts "✅ #{test_file} passed!"
    end
    puts
  end
  
  if success
    puts "🎉 All tests passed!"
  else
    puts "💥 Some tests failed!"
    exit 1
  end
end

# Test task specifically for test directory
desc "Run tests in the test/ directory"
task :test_dir do
  puts "🧪 Running tests from test/ directory"
  puts "=" * 40
  
  if File.exist?("test/run_tests.rb")
    system("cd test && ruby run_tests.rb")
  else
    test_files = Dir.glob("test/test_*.rb")
    if test_files.empty?
      puts "❌ No test files found in test/ directory!"
      exit 1
    end
    
    test_files.each do |test_file|
      puts "🔄 Running #{test_file}..."
      system("ruby #{test_file}")
    end
  end
end

# Test task for root directory test files
desc "Run tests in the root directory"
task :test_root do
  puts "🧪 Running tests from root directory"
  puts "=" * 40
  
  test_files = Dir.glob("test_*.rb")
  if test_files.empty?
    puts "❌ No test files found in root directory!"
    exit 1
  end
  
  test_files.each do |test_file|
    puts "🔄 Running #{test_file}..."
    system("ruby #{test_file}")
  end
end

# Run a specific test file
desc "Run a specific test file (rake test:file FILE=test_bundle_functionality.rb)"
task "test:file" do
  file = ENV['FILE']
  unless file
    puts "❌ Please specify a file: rake test:file FILE=test_name.rb"
    exit 1
  end
  
  # Look for the file in current directory first, then test directory
  test_file = nil
  if File.exist?(file)
    test_file = file
  elsif File.exist?("test/#{file}")
    test_file = "test/#{file}"
  else
    puts "❌ Test file '#{file}' not found in root or test/ directory!"
    exit 1
  end
  
  puts "🔄 Running #{test_file}..."
  system("ruby #{test_file}")
end

# Run a specific test method
desc "Run a specific test method (rake test:method FILE=test_file.rb METHOD=test_method_name)"
task "test:method" do
  file = ENV['FILE']
  method = ENV['METHOD']
  
  unless file && method
    puts "❌ Please specify both file and method:"
    puts "   rake test:method FILE=test_bundle_functionality.rb METHOD=test_bundle_parent_child"
    exit 1
  end
  
  # Look for the file in current directory first, then test directory
  test_file = nil
  if File.exist?(file)
    test_file = file
  elsif File.exist?("test/#{file}")
    test_file = "test/#{file}"
  else
    puts "❌ Test file '#{file}' not found!"
    exit 1
  end
  
  puts "🔄 Running #{method} from #{test_file}..."
  system("ruby #{test_file} -n #{method}")
end

# List all available test files and methods
desc "List all available test files and methods"
task "test:list" do
  puts "📋 Available Test Files:"
  puts "=" * 30
  
  # Root directory tests
  root_tests = Dir.glob("test_*.rb")
  unless root_tests.empty?
    puts "\n📁 Root Directory:"
    root_tests.each { |file| puts "   - #{file}" }
  end
  
  # Test directory tests
  test_dir_tests = Dir.glob("test/test_*.rb")
  unless test_dir_tests.empty?
    puts "\n📁 Test Directory:"
    test_dir_tests.each { |file| puts "   - #{file}" }
  end
  
  puts "\n🔍 Test Methods:"
  puts "=" * 20
  
  all_tests = root_tests + test_dir_tests
  all_tests.each do |test_file|
    puts "\n📄 #{test_file}:"
    content = File.read(test_file)
    methods = content.scan(/def (test_\w+)/).flatten
    if methods.any?
      methods.each { |method| puts "   - #{method}" }
    else
      puts "   (no test methods found)"
    end
  end
end

# Clean up temporary test files
desc "Clean up temporary test files and directories"
task :clean do
  puts "🧹 Cleaning up temporary test files..."
  
  # Remove any temporary directories created by tests
  temp_dirs = Dir.glob("prusa_profile_test*")
  temp_dirs.each do |dir|
    if File.directory?(dir)
      puts "   Removing #{dir}"
      FileUtils.rm_rf(dir)
    end
  end
  
  # Remove any .tmp files
  tmp_files = Dir.glob("*.tmp")
  tmp_files.each do |file|
    puts "   Removing #{file}"
    File.delete(file)
  end
  
  puts "✨ Cleanup complete!"
end

# Demo task to run the custom directories demo
desc "Run the custom directories demo"
task :demo do
  demo_file = nil
  if File.exist?("demo_custom_dirs.rb")
    demo_file = "demo_custom_dirs.rb"
  elsif File.exist?("test/demo_custom_dirs.rb")
    demo_file = "test/demo_custom_dirs.rb"
  end
  
  if demo_file
    puts "🎬 Running custom directories demo..."
    system("ruby #{demo_file}")
  else
    puts "❌ Demo file not found!"
    exit 1
  end
end

# Bundle command demo
desc "Run a sample bundle command"
task :bundle_demo do
  puts "📦 Running sample bundle command..."
  puts "This will create a test bundle from existing profiles"
  
  # Use existing profiles for demo
  if Dir.glob("print/*.ini").any?
    system("ruby update_prusa_profiles.rb bundle print --into DemoBundle --layer-height 0.2")
  else
    puts "❌ No print profiles found for demo. Please ensure print/*.ini files exist."
  end
end

# Help task
desc "Show available rake tasks with descriptions"
task :help do
  puts "📚 Available Rake Tasks:"
  puts "=" * 30
  puts
  puts "🧪 Testing Tasks:"
  puts "   rake test              - Run all tests (default)"
  puts "   rake test_dir          - Run tests in test/ directory only"
  puts "   rake test_root         - Run tests in root directory only"
  puts "   rake test:file FILE=x  - Run specific test file"
  puts "   rake test:method FILE=x METHOD=y - Run specific test method"
  puts "   rake test:list         - List all test files and methods"
  puts
  puts "🛠️  Utility Tasks:"
  puts "   rake clean             - Clean up temporary files"
  puts "   rake demo              - Run custom directories demo"
  puts "   rake bundle_demo       - Run sample bundle command"
  puts "   rake help              - Show this help"
  puts
  puts "💡 Examples:"
  puts "   rake test:file FILE=test_bundle_functionality.rb"
  puts "   rake test:method FILE=test_bundle_functionality.rb METHOD=test_bundle_parent_child"
end
