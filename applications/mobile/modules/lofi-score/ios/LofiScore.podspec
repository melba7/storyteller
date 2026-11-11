# LOFI-FORK: the Storyteller Lofi fork's native module (see FORK.md). It plays the quiet
# sounds of each scene under the narration. The LofiScore* pods it depends on are the Swift
# package in libraries/LofiScoreKit, added to the Podfile by fork.config.ts.
Pod::Spec.new do |s|
  s.name           = 'LofiScore'
  s.version        = '0.2.0'
  s.summary        = 'Atmosphere sounds under the narration'
  s.description    = 'Follows the readaloud narration and plays the sounds of the scene being read, never ahead of it.'
  s.author         = ''
  s.homepage       = 'https://github.com/melba7/storyteller'
  s.platform       = :ios, '16.4'
  s.source         = { git: '' }
  s.static_framework = true
  s.swift_version  = '5.9'

  s.dependency 'ExpoModulesCore'
  s.dependency 'Readium'
  s.dependency 'LofiScoreHost'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES'
  }

  s.source_files = "**/*.swift"
end
