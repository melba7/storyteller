# Downloads sentry-cocoa's prebuilt Sentry.xcframework into the cache that
# @sentry/react-native's podspec reads, retrying when the download fails.
# Used by the iOS build in .github/workflows/fork-ci.yml. See FORK.md ("CI").
#
# Usage: ruby tools/fork/prefetch-sentry-xcframework.rb [<app dir>]
#
# pod install downloads the framework from GitHub's release downloads once,
# with no retry, and those downloads sometimes answer 504 for minutes at a
# time. This calls the podspec's own helper, so the checksum check and the
# cache layout are exactly what pod install expects; pod install then finds
# the framework already in place. Older @sentry/react-native versions that
# build Sentry from source are left alone.

app_dir = File.expand_path(ARGV[0] || 'applications/mobile')

package_json = Dir.chdir(app_dir) do
  `node --print "require.resolve('@sentry/react-native/package.json')" 2>/dev/null`.strip
end
if package_json.empty? || !File.file?(package_json)
  puts "@sentry/react-native is not installed in #{app_dir}; nothing to fetch."
  exit 0
end

package_dir = File.dirname(package_json)
podspec = File.read(File.join(package_dir, 'RNSentry.podspec'), encoding: 'UTF-8')
version = podspec[/sentry_cocoa_version\s*=\s*'([^']+)'/, 1]
helpers = File.join(package_dir, 'scripts', 'sentry_utils.rb')
unless version && File.file?(helpers)
  puts 'This @sentry/react-native has no prebuilt Sentry framework to fetch.'
  exit 0
end

require helpers
unless defined?(ensure_sentry_xcframework)
  puts 'This @sentry/react-native builds Sentry from source; nothing to fetch.'
  exit 0
end

attempts = 6
attempts.times do |attempt|
  begin
    path = ensure_sentry_xcframework(version, 'Sentry')
    puts "Sentry #{version} framework ready at #{path}"
    exit 0
  rescue StandardError => e
    raise if attempt == attempts - 1

    delay = 15 * (attempt + 1)
    puts "Attempt #{attempt + 1} of #{attempts} failed: #{e.message}"
    puts "Retrying in #{delay} seconds."
    sleep delay
  end
end
