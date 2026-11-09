# LOFI-FORK: generated alongside Package.swift so the Storyteller app can build this
# Swift package target with CocoaPods (see FORK.md). Keep the dependencies and the Swift
# language mode in step with Package.swift.
Pod::Spec.new do |s|
  s.name           = 'LofiScoreHost'
  s.version        = '0.1.0'
  s.summary        = 'Follows the narrator in the app and runs the music for it.'
  s.author         = 'Storyteller Lofi fork'
  s.homepage       = 'https://github.com/melba7/storyteller'
  s.license        = { type: 'MIT' }
  s.platform       = :ios, '16.4'
  s.source         = { git: '' }
  s.static_framework = true
  s.swift_version  = '5.0'

  s.dependency 'LofiScoreCore'
  s.dependency 'LofiText'
  s.dependency 'LofiMood'
  s.dependency 'LofiDirector'
  s.dependency 'LofiAudio'
  s.dependency 'LofiPlaceholders'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.source_files = 'Sources/LofiScoreHost/**/*.swift'
end
