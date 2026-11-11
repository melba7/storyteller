# LOFI-FORK: generated alongside Package.swift so the Storyteller app can build this
# Swift package target with CocoaPods (see FORK.md). Keep the dependencies and the Swift
# language mode in step with Package.swift.
Pod::Spec.new do |s|
  s.name           = 'LofiMood'
  s.version        = '0.1.0'
  s.summary        = 'Mood engines: the Fast classifier, Apple models where available, Claude mood tracks.'
  s.author         = 'Storyteller Lofi fork'
  s.homepage       = 'https://github.com/melba7/storyteller'
  s.license        = { type: 'MIT' }
  s.platform       = :ios, '16.4'
  s.source         = { git: '' }
  s.static_framework = true
  s.swift_version  = '6.0'

  s.dependency 'LofiScoreCore'
  s.dependency 'LofiText'

  # Only on iOS 26 and later; the code checks availability at runtime.
  s.weak_frameworks = 'FoundationModels'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.source_files = 'Sources/LofiMood/**/*.swift'
end
