require 'xcodeproj'

output_dir, repo_root, flutter_framework = ARGV
abort 'Usage: ios-runtime-project.rb OUTPUT_DIR REPO_ROOT FLUTTER_XCFRAMEWORK' unless ARGV.length == 3

project_path = File.join(output_dir, 'SecureContentRuntimeTests.xcodeproj')
project = Xcodeproj::Project.new(project_path)
framework = project.new_target(:framework, 'secure_content', :ios, '15.0')
host = project.new_target(:application, 'SecureContentRuntimeTestHost', :ios, '15.0')
tests = project.new_target(:unit_test_bundle, 'SecureContentRuntimeTests', :ios, '15.0')

project.targets.each do |target|
  target.build_configurations.each do |config|
    config.build_settings.merge!(
      'CLANG_ENABLE_MODULES' => 'YES',
      'CODE_SIGNING_ALLOWED' => 'NO',
      'SWIFT_VERSION' => '5.0',
      'SWIFT_STRICT_CONCURRENCY' => 'complete',
      'TARGETED_DEVICE_FAMILY' => '1,2',
      'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks', '@loader_path/Frameworks']
    )
  end
end

framework.build_configurations.each do |config|
  config.build_settings.merge!(
    'DEFINES_MODULE' => 'YES',
    'GENERATE_INFOPLIST_FILE' => 'YES',
    'PRODUCT_BUNDLE_IDENTIFIER' => 'dev.securecontent.runtime-framework',
    'SKIP_INSTALL' => 'YES'
  )
  config.build_settings['ENABLE_TESTABILITY'] = 'YES' if config.name == 'Debug'
end

host.build_configurations.each do |config|
  config.build_settings.merge!(
    'INFOPLIST_FILE' => File.join(repo_root, 'ios/Tests/RuntimeHost/Info.plist'),
    'PRODUCT_BUNDLE_IDENTIFIER' => 'dev.securecontent.runtime-host'
  )
end

tests.build_configurations.each do |config|
  config.build_settings.merge!(
    'BUNDLE_LOADER' => '$(TEST_HOST)',
    'GENERATE_INFOPLIST_FILE' => 'YES',
    'PRODUCT_BUNDLE_IDENTIFIER' => 'dev.securecontent.runtime-tests',
    'TEST_HOST' => '$(BUILT_PRODUCTS_DIR)/SecureContentRuntimeTestHost.app/SecureContentRuntimeTestHost'
  )
end

{
  framework => 'ios/secure_content/Sources/secure_content',
  host => 'ios/Tests/RuntimeHost',
  tests => 'ios/Tests/Runtime'
}.each do |target, path|
  source_paths = Dir[File.join(repo_root, path, '*.swift')].sort
  abort "No Swift sources found for #{target.name}" if source_paths.empty?
  group = project.main_group.new_group(target.name)
  source_paths.each do |source_path|
    target.source_build_phase.add_file_reference(group.new_file(source_path))
  end
end

flutter = project.frameworks_group.new_file(flutter_framework)
flutter.last_known_file_type = 'wrapper.xcframework'
framework.frameworks_build_phase.add_file_reference(flutter)
host.frameworks_build_phase.add_file_reference(framework.product_reference)
tests.frameworks_build_phase.add_file_reference(framework.product_reference)
tests.frameworks_build_phase.add_file_reference(flutter)
host.add_dependency(framework)
tests.add_dependency(framework)
tests.add_dependency(host)
project.root_object.attributes['TargetAttributes'] = {
  tests.uuid => { 'TestTargetID' => host.uuid }
}

project.files.each do |reference|
  next unless reference.source_tree == 'DEVELOPER_DIR' && reference.path.start_with?('Platforms/')
  reference.path = File.join('System/Library/Frameworks', File.basename(reference.path))
  reference.source_tree = 'SDKROOT'
end

embedding = host.new_copy_files_build_phase('Embed Frameworks')
embedding.dst_subfolder_spec = '10'
[framework.product_reference, flutter].each do |reference|
  embedding.add_file_reference(reference).settings = {
    'ATTRIBUTES' => ['CodeSignOnCopy', 'RemoveHeadersOnCopy']
  }
end

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(host)
scheme.add_build_target(tests, false)
scheme.add_test_target(tests)
scheme.set_launch_target(host)
scheme.test_action.build_configuration = 'Debug'
scheme.test_action.should_use_launch_scheme_args_env = true
scheme.save_as(project_path, 'SecureContentRuntimeTests', true)
project.save
