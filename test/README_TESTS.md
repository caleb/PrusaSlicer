# PrusaSlicer Profile Bundle Test Suite

This directory contains a comprehensive test suite for the enhanced PrusaSlicer profile bundle functionality.

## Files in this Test Directory

### Main Test Suite
- **`test_bundle_functionality.rb`** - Main test suite with 12 comprehensive tests
- **`run_tests.rb`** - Test runner with formatted output
- **`test_specific.rb`** - Individual test runner for debugging

### Demo and Utilities  
- **`demo_custom_dirs.rb`** - Demonstrates custom directory functionality

## Running Tests

### From Main Directory
```bash
# Run all tests (recommended)
ruby run_tests_from_main.rb

# Or change to test directory
cd test
ruby run_tests.rb
```

### From Test Directory
```bash
# Run all tests with formatted output
ruby run_tests.rb

# Run specific test
ruby test_specific.rb test_bundle_parent_child_inheritance

# List all available tests
ruby test_specific.rb --list
```

## Test Coverage

The test suite covers all major functionality:

### 1. Basic INI Parsing (`test_ini_parser_basic_functionality`)
- Tests fundamental INI file parsing and profile extraction

### 2. Single Profile Bundling (`test_bundle_single_profile_no_inheritance`)
- Verifies that profiles with no inheritance relationships stay in original locations

### 3. Parent-Child Inheritance (`test_bundle_parent_child_inheritance`)
- Tests basic inheritance with one parent and one child
- Verifies parent gets moved to bundle and privatized
- Verifies child stays in original location with updated inheritance

### 4. Multi-Level Inheritance (`test_bundle_multi_level_inheritance`)
- Tests inheritance chains (GrandParent -> Parent -> Child)
- Verifies all non-leaf profiles get bundled and privatized
- Verifies inheritance chain is maintained with proper asterisk references

### 5. Tagged Profile Support (`test_bundle_with_tags`)
- Tests profiles with tags (e.g., "Parent @test")
- Verifies inheritance detection works with tagged profiles
- Verifies privatized names include full tag information

### 6. External Inheritance (`test_bundle_external_inheritance_unchanged`)
- Tests that profiles inheriting from external parents are left unchanged
- Verifies external parents are not affected

### 7. Bundle Appending (`test_bundle_append_to_existing`)
- Tests adding new profiles to existing bundle files
- Verifies no conflicts or duplicates

### 8. Duplicate Prevention (`test_bundle_no_duplicate_profiles`)
- Tests that duplicate profiles are not added to bundles
- Verifies proper handling of repeated bundle operations

### 9. Error Handling (`test_error_handling_invalid_bundle_name`)
- Tests filesystem-safe name validation
- Verifies proper rejection of invalid characters

### 10. Filament Profile Support (`test_filament_profile_bundling`)
- Tests that filament profiles work the same as print profiles
- Verifies inheritance handling across profile types

### 11. Name Parsing (`test_profile_name_parsing_with_tags`)
- Tests profile name parsing utilities
- Verifies tag extraction functionality

### 12. Core Name Inheritance (`test_inheritance_detection_with_core_names`)
- Tests inheritance detection with core names (without tags)
- Verifies a child can inherit from "Parent" even if the actual profile is "Parent @tag"

## Key Features Tested

### Enhanced Bundle Command
- **Leaf vs Non-Leaf Detection**: Correctly identifies which profiles have children
- **Selective Moving**: Only moves parent profiles to bundle, leaves leaf profiles in place
- **Privatization**: Adds asterisks around parent profile names
- **Global Inheritance Updates**: Updates all files that reference moved profiles
- **Profile Removal**: Removes bundled profiles from original files

### Custom Directory Support
- **`--profile-dir`**: Specify custom source directory for profiles
- **`--bundle-dir`**: Specify custom destination directory for bundles
- **Testing Isolation**: Allows tests to run in temporary directories

### Inheritance Intelligence
- **Tag-Aware**: Handles profiles with tags correctly
- **Core Name Matching**: Matches inheritance by base name regardless of tags
- **Chain Preservation**: Maintains complex inheritance chains in bundles
- **External Respect**: Doesn't modify references to external profiles

## Running Tests

### All Tests
```bash
bundle exec ruby run_tests.rb
```

### Specific Test
```bash
bundle exec ruby test_specific.rb test_bundle_parent_child_inheritance
```

### List Available Tests
```bash
bundle exec ruby test_specific.rb --list
```

### Demo Custom Directories
```bash
ruby demo_custom_dirs.rb
```

## Test Results

All 12 tests pass, covering:
- 48 total assertions
- 0 failures
- 0 errors  
- 0 skips

## Benefits

1. **Confidence**: Comprehensive test coverage ensures the bundle functionality works correctly
2. **Regression Prevention**: Tests catch breaking changes during development
3. **Documentation**: Tests serve as executable documentation of expected behavior
4. **Development Speed**: Easy to test changes quickly with specific test methods
5. **Custom Directory Support**: Enables testing and development workflows with isolated environments

The test suite validates that the enhanced bundle command correctly implements the sophisticated inheritance management and profile privatization functionality as specified.
