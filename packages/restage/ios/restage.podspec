Pod::Spec.new do |s|
  s.name             = 'restage'
  s.version          = '2.0.0'
  s.summary          = 'Sends the Restage startup request at app launch.'
  s.description      = 'Starts the startup placement request before Dart runs and hands the answer to the Flutter client.'
  s.homepage         = 'https://restage.dev'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Restage' => 'hello@restage.dev' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.0'
end
