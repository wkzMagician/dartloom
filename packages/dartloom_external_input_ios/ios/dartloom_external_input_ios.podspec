Pod::Spec.new do |s|
  s.name             = 'dartloom_external_input_ios'
  s.version          = '0.1.0'
  s.summary          = 'iOS adapter for Dartloom external input.'
  s.description      = <<-DESC
iOS adapter and App Group inbox for Dartloom external input.
                       DESC
  s.homepage         = 'https://github.com/wkzMagician/dartloom'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Dartloom' => 'opensource@dartloom.dev' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.5'
  s.swift_version = '5.0'
end
