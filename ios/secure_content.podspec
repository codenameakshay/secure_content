Pod::Spec.new do |s|
  s.name             = 'secure_content'
  s.version          = '2.0.0'
  s.summary          = 'Protect Flutter screens on Android and iOS.'
  s.description      = <<-DESC
Secure content protection primitives for Flutter with screenshot/recording awareness and app switcher obscuring support.
                       DESC
  s.homepage         = 'https://github.com/codenameakshay/secure_content'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'codenameakshay' => 'dev@hashstudios.dev' }
  s.source           = { :path => '.' }
  s.source_files     = 'secure_content/Sources/secure_content/**/*'
  s.dependency       'Flutter'
  s.platform         = :ios, '13.0'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
  s.swift_version = '5.9'
end
