# LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md). It reads podcast
# feeds for the Podcasts section. The PodcastFeed pod is the Swift package in
# libraries/PodcastKit, added to the Podfile by fork.config.ts.
Pod::Spec.new do |s|
  s.name           = 'Podcasts'
  s.version        = '0.1.0'
  s.summary        = 'Podcast feeds for the Podcasts section'
  s.description    = 'Fetches a podcast RSS feed and reads it into a show and its episodes.'
  s.author         = ''
  s.homepage       = 'https://github.com/melba7/storyteller'
  s.platform       = :ios, '16.4'
  s.source         = { git: '' }
  s.static_framework = true
  s.swift_version  = '5.9'

  s.dependency 'ExpoModulesCore'
  s.dependency 'PodcastFeed'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES'
  }

  s.source_files = "**/*.swift"
end
