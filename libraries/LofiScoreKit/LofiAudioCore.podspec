# LOFI-FORK: generated alongside Package.swift so the Storyteller app can build this
# Swift package target with CocoaPods (see FORK.md). Keep the dependencies and the Swift
# language mode in step with Package.swift.
Pod::Spec.new do |s|
  s.name           = 'LofiAudioCore'
  s.version        = '0.1.0'
  s.summary        = 'The clock, scheduler, gain maths and audio file helpers the sound players share.'
  s.author         = 'Storyteller Lofi fork'
  s.homepage       = 'https://github.com/melba7/storyteller'
  s.license        = { type: 'MIT' }
  s.platform       = :ios, '16.4'
  s.source         = { git: '' }
  s.static_framework = true
  s.swift_version  = '5.0'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.source_files = 'Sources/LofiAudioCore/**/*.swift'
end
