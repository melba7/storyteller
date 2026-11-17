# LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md). It reads podcast
# feeds and plays episodes for the Podcasts section. The PodcastFeed, PodcastPlayback and PodcastDownloads pods
# are the Swift package in libraries/PodcastKit, added to the Podfile by fork.config.ts. It
# depends on the Readium pod to pause and watch the book player.
Pod::Spec.new do |s|
  s.name           = 'Podcasts'
  s.version        = '0.1.0'
  s.summary        = 'Podcast feeds for the Podcasts section'
  s.description    = 'Fetches a podcast RSS feed, reads it into a show and its episodes, and plays the episodes.'
  s.author         = ''
  s.homepage       = 'https://github.com/melba7/storyteller'
  s.platform       = :ios, '16.4'
  s.source         = { git: '' }
  s.static_framework = true
  s.swift_version  = '5.9'

  s.dependency 'ExpoModulesCore'
  s.dependency 'PodcastFeed'
  s.dependency 'PodcastPlayback'
  s.dependency 'PodcastDownloads'
  s.dependency 'Readium'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES'
  }

  s.source_files = "**/*.swift"
end
