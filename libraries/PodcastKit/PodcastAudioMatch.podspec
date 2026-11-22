# LOFI-FORK: generated alongside Package.swift so the Storyteller app can build this
# Swift package target with CocoaPods (see FORK.md). Keep the dependencies and the Swift
# language mode in step with Package.swift.
Pod::Spec.new do |s|
  s.name           = 'PodcastAudioMatch'
  s.version        = '0.1.0'
  s.summary        = 'Podcast audio matching: MP3 frames, shared runs and the taught ad sounds.'
  s.author         = 'Storyteller Lofi fork'
  s.homepage       = 'https://github.com/melba7/storyteller'
  s.license        = { type: 'MIT' }
  s.platform       = :ios, '16.4'
  s.source         = { git: '' }
  s.static_framework = true
  s.swift_version  = '6.0'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.source_files = 'Sources/PodcastAudioMatch/**/*.swift'
end
