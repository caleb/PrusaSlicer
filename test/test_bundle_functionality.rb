#!/usr/bin/env ruby

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../update_prusa_profiles"

class TestPrusaProfileUpdater < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir("prusa_profile_test")
    @print_dir = File.join(@temp_dir, "print")
    @filament_dir = File.join(@temp_dir, "filament")
    @vendor_dir = File.join(@temp_dir, "vendor")

    # Create test directories
    FileUtils.mkdir_p(@print_dir)
    FileUtils.mkdir_p(@filament_dir)
    FileUtils.mkdir_p(@vendor_dir)

    # Save original directory for cleanup
    @original_dir = Dir.pwd
    Dir.chdir(@temp_dir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@temp_dir)
  end

  def create_test_profile(dir, filename, profile_name, properties = {})
    content = "[#{profile_name}]\n"
    properties.each do |key, value|
      content += "#{key} = #{value}\n"
    end
    File.write(File.join(dir, filename), content)
  end

  def read_profile_properties(file_path, profile_name)
    return {} unless File.exist?(file_path)

    content = File.read(file_path)
    lines = content.lines
    properties = {}
    in_profile = false

    lines.each do |line|
      # Escape special regex characters in profile name, especially asterisks
      escaped_profile_name = Regexp.escape(profile_name)
      if line.match(/^\[#{escaped_profile_name}\]/)
        in_profile = true
        next
      elsif line.match(/^\[.*\]/)
        in_profile = false
        next
      elsif in_profile && line.match(/^(\w+)\s*=\s*(.*)$/)
        properties[Regexp.last_match(1)] = Regexp.last_match(2).strip
      end
    end

    properties
  end

  def test_ini_parser_basic_functionality
    # Test basic INI parsing
    parser = IniParser.new("print", "test")

    create_test_profile(@print_dir, "basic.ini", "print: Basic Profile", {
                          "layer_height" => "0.2",
                          "fill_density" => "20%"
                        })

    profiles = parser.parse(File.join(@print_dir, "basic.ini"))

    assert_equal 1, profiles.length
    profile = profiles.first
    assert_equal "print: Basic Profile", profile[:profile_name]
    assert_equal "0.2", profile[:properties]["layer_height"]
    assert_equal "20%", profile[:properties]["fill_density"]
  end

  def test_bundle_single_profile_no_inheritance
    # Test bundling a single profile with no inheritance
    create_test_profile(@print_dir, "simple.ini", "print: Simple", {
                          "layer_height" => "0.2",
                          "fill_density" => "20%"
                        })

    parser = IniParser.new("print", "simple")
    profiles = parser.parse(File.join(@print_dir, "simple.ini"))

    bundle_profiles(profiles, "test_bundle", "print", @vendor_dir, @print_dir)

    # Since there's no inheritance, profile should stay in original location
    assert File.exist?(File.join(@print_dir, "simple.ini")), "Original file should still exist"

    # Bundle should exist but be empty of new profiles (no non-leaf profiles)
    if File.exist?(File.join(@vendor_dir, "test_bundle.ini"))
      content = File.read(File.join(@vendor_dir, "test_bundle.ini"))
      assert content.empty? || !content.include?("Simple"), "Single profile with no children should not be bundled"
    end
  end

  def test_bundle_parent_child_inheritance
    # Test bundling with parent-child inheritance
    create_test_profile(@print_dir, "parent.ini", "print: Parent", {
                          "layer_height" => "0.2",
                          "fill_density" => "20%"
                        })

    create_test_profile(@print_dir, "child.ini", "print: Child", {
                          "inherits" => "Parent",
                          "first_layer_height" => "0.3"
                        })

    # Parse all profiles
    parser = IniParser.new("print", "test")
    parent_profiles = parser.parse(File.join(@print_dir, "parent.ini"))
    child_profiles = parser.parse(File.join(@print_dir, "child.ini"))
    all_profiles = parent_profiles + child_profiles

    bundle_profiles(all_profiles, "parent_child_bundle", "print", @vendor_dir, @print_dir)

    # Parent should be moved to bundle and privatized
    bundle_file = File.join(@vendor_dir, "parent_child_bundle.ini")
    assert File.exist?(bundle_file), "Bundle file should exist"

    bundle_content = File.read(bundle_file)
    assert_includes bundle_content, "[print: *Parent*]", "Parent should be privatized in bundle"

    # Child should stay in original location but inherit from privatized parent
    child_props = read_profile_properties(File.join(@print_dir, "child.ini"), "print: Child")
    assert_equal "*Parent*", child_props["inherits"], "Child should inherit from privatized parent"

    # Parent should be removed from original file
    parent_content = File.read(File.join(@print_dir, "parent.ini"))
    refute_includes parent_content, "[print: Parent]", "Parent should be removed from original file"
  end

  def test_bundle_multi_level_inheritance
    # Test bundling with multiple levels of inheritance
    create_test_profile(@print_dir, "grandparent.ini", "print: GrandParent", {
                          "layer_height" => "0.2"
                        })

    create_test_profile(@print_dir, "parent.ini", "print: Parent", {
                          "inherits" => "GrandParent",
                          "fill_density" => "20%"
                        })

    create_test_profile(@print_dir, "child.ini", "print: Child", {
                          "inherits" => "Parent",
                          "first_layer_height" => "0.3"
                        })

    # Parse all profiles
    parser = IniParser.new("print", "test")
    profiles = []
    ["grandparent.ini", "parent.ini", "child.ini"].each do |file|
      profiles.concat(parser.parse(File.join(@print_dir, file)))
    end

    bundle_profiles(profiles, "multi_level_bundle", "print", @vendor_dir, @print_dir)

    # Bundle should contain privatized GrandParent and Parent
    bundle_content = File.read(File.join(@vendor_dir, "multi_level_bundle.ini"))
    assert_includes bundle_content, "[print: *GrandParent*]", "GrandParent should be privatized"
    assert_includes bundle_content, "[print: *Parent*]", "Parent should be privatized"

    # Check inheritance chain in bundle
    parent_props = read_profile_properties(File.join(@vendor_dir, "multi_level_bundle.ini"), "print: *Parent*")
    assert_equal "*GrandParent*", parent_props["inherits"], "Parent should inherit from privatized GrandParent in bundle"

    # Child should inherit from privatized Parent
    child_props = read_profile_properties(File.join(@print_dir, "child.ini"), "print: Child")
    assert_equal "*Parent*", child_props["inherits"], "Child should inherit from privatized Parent"
  end

  def test_bundle_with_tags
    # Test bundling profiles with tags
    create_test_profile(@print_dir, "parent_tagged.ini", "print: Parent @test", {
                          "layer_height" => "0.2"
                        })

    create_test_profile(@print_dir, "child_tagged.ini", "print: Child @test", {
                          "inherits" => "Parent", # NOTE: inherits without tag
                          "fill_density" => "30%"
                        })

    parser = IniParser.new("print", "test")
    profiles = []
    ["parent_tagged.ini", "child_tagged.ini"].each do |file|
      profiles.concat(parser.parse(File.join(@print_dir, file)))
    end

    bundle_profiles(profiles, "tagged_bundle", "print", @vendor_dir, @print_dir)

    # Parent should be privatized with full tag name
    bundle_content = File.read(File.join(@vendor_dir, "tagged_bundle.ini"))
    assert_includes bundle_content, "[print: *Parent @test*]", "Tagged parent should be privatized with full name"

    # Child should inherit from privatized tagged parent
    child_props = read_profile_properties(File.join(@print_dir, "child_tagged.ini"), "print: Child @test")
    assert_equal "*Parent @test*", child_props["inherits"], "Child should inherit from privatized tagged parent"
  end

  def test_bundle_external_inheritance_unchanged
    # Test that profiles inheriting from external parents are not modified
    create_test_profile(@print_dir, "external_parent.ini", "print: ExternalParent", {
                          "layer_height" => "0.2"
                        })

    create_test_profile(@print_dir, "internal_child.ini", "print: InternalChild", {
                          "inherits" => "ExternalParent",
                          "fill_density" => "30%"
                        })

    # Only bundle the child, not the parent
    parser = IniParser.new("print", "test")
    child_profiles = parser.parse(File.join(@print_dir, "internal_child.ini"))

    bundle_profiles(child_profiles, "external_test_bundle", "print", @vendor_dir, @print_dir)

    # Child should stay in original location with unchanged inheritance
    child_props = read_profile_properties(File.join(@print_dir, "internal_child.ini"), "print: InternalChild")
    assert_equal "ExternalParent", child_props["inherits"], "External inheritance should remain unchanged"

    # External parent should remain in its original file
    assert File.exist?(File.join(@print_dir, "external_parent.ini")), "External parent should remain"
    external_content = File.read(File.join(@print_dir, "external_parent.ini"))
    assert_includes external_content, "[print: ExternalParent]", "External parent should not be modified"
  end

  def test_bundle_append_to_existing
    # Test appending to existing bundle
    create_test_profile(@print_dir, "first_parent.ini", "print: FirstParent", {
                          "layer_height" => "0.2"
                        })

    create_test_profile(@print_dir, "first_child.ini", "print: FirstChild", {
                          "inherits" => "FirstParent",
                          "fill_density" => "20%"
                        })

    # Create first bundle
    parser = IniParser.new("print", "test")
    first_profiles = parser.parse(File.join(@print_dir, "first_parent.ini")) +
                     parser.parse(File.join(@print_dir, "first_child.ini"))

    bundle_profiles(first_profiles, "append_test_bundle", "print", @vendor_dir, @print_dir)

    # Create second set of profiles
    create_test_profile(@print_dir, "second_parent.ini", "print: SecondParent", {
                          "layer_height" => "0.3"
                        })

    create_test_profile(@print_dir, "second_child.ini", "print: SecondChild", {
                          "inherits" => "SecondParent",
                          "fill_density" => "30%"
                        })

    # Append to existing bundle
    second_profiles = parser.parse(File.join(@print_dir, "second_parent.ini")) +
                      parser.parse(File.join(@print_dir, "second_child.ini"))

    bundle_profiles(second_profiles, "append_test_bundle", "print", @vendor_dir, @print_dir)

    # Bundle should contain both privatized parents
    bundle_content = File.read(File.join(@vendor_dir, "append_test_bundle.ini"))
    assert_includes bundle_content, "[print: *FirstParent*]", "First parent should be in bundle"
    assert_includes bundle_content, "[print: *SecondParent*]", "Second parent should be in bundle"
  end

  def test_bundle_no_duplicate_profiles
    # Test that duplicate profiles are not added to bundle
    create_test_profile(@print_dir, "duplicate_parent.ini", "print: DuplicateParent", {
                          "layer_height" => "0.2"
                        })

    create_test_profile(@print_dir, "duplicate_child.ini", "print: DuplicateChild", {
                          "inherits" => "DuplicateParent",
                          "fill_density" => "20%"
                        })

    parser = IniParser.new("print", "test")
    profiles = parser.parse(File.join(@print_dir, "duplicate_parent.ini")) +
               parser.parse(File.join(@print_dir, "duplicate_child.ini"))

    # Bundle once
    bundle_profiles(profiles, "duplicate_test_bundle", "print", @vendor_dir, @print_dir)

    # Try to bundle the same profiles again
    # Recreate profiles since they were removed from original files
    create_test_profile(@print_dir, "duplicate_parent2.ini", "print: DuplicateParent", {
                          "layer_height" => "0.2"
                        })

    duplicate_profiles = parser.parse(File.join(@print_dir, "duplicate_parent2.ini"))
    bundle_profiles(duplicate_profiles, "duplicate_test_bundle", "print", @vendor_dir, @print_dir)

    # Should not have duplicate entries
    bundle_content = File.read(File.join(@vendor_dir, "duplicate_test_bundle.ini"))
    parent_count = bundle_content.scan(/\[print: \*DuplicateParent\*\]/).length
    assert_equal 1, parent_count, "Should not have duplicate parent profiles in bundle"
  end

  def test_error_handling_invalid_bundle_name
    # Test error handling for invalid bundle names (validation is in main script, not bundle_profiles)
    # This test verifies the contains_unsafe_filesystem_chars? function works correctly

    # Test valid names
    refute contains_unsafe_filesystem_chars?("valid_name"), "Valid name should pass"
    refute contains_unsafe_filesystem_chars?("valid-name"), "Valid name with dash should pass"
    refute contains_unsafe_filesystem_chars?("valid_name_123"), "Valid name with numbers should pass"

    # Test invalid names
    assert contains_unsafe_filesystem_chars?("invalid:name"), "Name with colon should fail"
    assert contains_unsafe_filesystem_chars?("invalid<name"), "Name with < should fail"
    assert contains_unsafe_filesystem_chars?("invalid>name"), "Name with > should fail"
    assert contains_unsafe_filesystem_chars?('invalid"name'), "Name with quote should fail"
    assert contains_unsafe_filesystem_chars?("invalid|name"), "Name with pipe should fail"
    assert contains_unsafe_filesystem_chars?("invalid?name"), "Name with question mark should fail"
    assert contains_unsafe_filesystem_chars?("invalid*name"), "Name with asterisk should fail"
    assert contains_unsafe_filesystem_chars?("invalid\\name"), "Name with backslash should fail"
    assert contains_unsafe_filesystem_chars?("invalid/name"), "Name with forward slash should fail"
  end

  def test_filament_profile_bundling
    # Test bundling filament profiles
    create_test_profile(@filament_dir, "base_filament.ini", "filament: BaseFilament", {
                          "filament_type" => "PLA",
                          "temperature" => "210"
                        })

    create_test_profile(@filament_dir, "custom_filament.ini", "filament: CustomFilament", {
                          "inherits" => "BaseFilament",
                          "temperature" => "215"
                        })

    parser = IniParser.new("filament", "test")
    profiles = parser.parse(File.join(@filament_dir, "base_filament.ini")) +
               parser.parse(File.join(@filament_dir, "custom_filament.ini"))

    bundle_profiles(profiles, "filament_bundle", "filament", @vendor_dir, @filament_dir)

    # Base filament should be privatized in bundle
    bundle_content = File.read(File.join(@vendor_dir, "filament_bundle.ini"))
    assert_includes bundle_content, "[filament: *BaseFilament*]", "Base filament should be privatized"

    # Custom filament should inherit from privatized base
    custom_props = read_profile_properties(File.join(@filament_dir, "custom_filament.ini"), "filament: CustomFilament")
    assert_equal "*BaseFilament*", custom_props["inherits"], "Custom filament should inherit from privatized base"
  end

  def test_profile_name_parsing_with_tags
    # Test the profile name parsing functions
    profile_name = "print: Test Profile @tag1 @tag2"
    base_name = get_base_profile_name(profile_name)
    tags = extract_tags_from_profile_name(profile_name)

    assert_equal "Test Profile", base_name
    assert_equal %w[tag1 tag2], tags
  end

  def test_inheritance_detection_with_core_names
    # Test that inheritance detection works with core names (without tags)
    create_test_profile(@print_dir, "core_parent.ini", "print: CoreParent @tag", {
                          "layer_height" => "0.2"
                        })

    create_test_profile(@print_dir, "core_child.ini", "print: CoreChild @tag", {
                          "inherits" => "CoreParent", # inherits without tag
                          "fill_density" => "20%"
                        })

    parser = IniParser.new("print", "test")
    profiles = parser.parse(File.join(@print_dir, "core_parent.ini")) +
               parser.parse(File.join(@print_dir, "core_child.ini"))

    bundle_profiles(profiles, "core_bundle", "print", @vendor_dir, @print_dir)

    # Parent should be privatized
    bundle_content = File.read(File.join(@vendor_dir, "core_bundle.ini"))
    assert_includes bundle_content, "[print: *CoreParent @tag*]", "Tagged parent should be privatized"

    # Child should inherit from privatized tagged parent
    child_props = read_profile_properties(File.join(@print_dir, "core_child.ini"), "print: CoreChild @tag")
    assert_equal "*CoreParent @tag*", child_props["inherits"], "Child should inherit from privatized tagged parent"
  end

  # Helper method to capture stdout/stderr for testing error conditions
  def capture_io
    require "stringio"
    old_stdout = $stdout
    old_stderr = $stderr
    $stdout = StringIO.new
    $stderr = StringIO.new
    yield
    [$stdout.string, $stderr.string]
  ensure
    $stdout = old_stdout
    $stderr = old_stderr
  end
end
