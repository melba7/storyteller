import Foundation
import LofiDirector
import LofiScoreCore

// lofi-replay: run mood readings through the director and see what the music would do.
//
//   lofi-replay script.json [more.json ...]       replay scripts, print each decision, check "expect" marks
//   lofi-replay --synthetic [--hours 10] [--seeds 1-20]
//                                                 generate made-up books and print how the director copes
//   lofi-replay --write-synthetic out.json [--seed 1] [--hours 2]
//                                                 save a made-up book as a script
//   --set key=value                               override a DirectorConfig value, e.g. --set minimumDwell=60
//   --quiet                                       summaries only
//
// Made-up books read by default like an engine on the 20-second cadence. These change that:
//   --every-sentence                              read every sentence (about every 5 s)
//   --noise-episode S                             wrong readings come in runs of about S seconds
//   --track                                       read the book's mood track, every sentence
//   --track-unmarked                              ...but send its readings as live ones
//   --track-pin N                                 the track marks turns up to N sentences late (default 3)
//   --cadence S                                   read every S seconds (after the flags above)

struct Options {
    var scripts: [String] = []
    var synthetic = false
    var writeSynthetic: String?
    var hours = 10.0
    var seeds: ClosedRange<UInt64> = 1...20
    var overrides: [String: Double] = [:]
    var quiet = false
    var book = SyntheticBook.Options()
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

func parse(_ arguments: [String]) -> Options {
    var options = Options()
    var iterator = arguments.makeIterator()
    while let argument = iterator.next() {
        switch argument {
        case "--synthetic":
            options.synthetic = true
        case "--write-synthetic":
            guard let path = iterator.next() else { fail("--write-synthetic needs a path") }
            options.writeSynthetic = path
        case "--hours":
            guard let value = iterator.next().flatMap(Double.init) else { fail("--hours needs a number") }
            options.hours = value
        case "--seed", "--seeds":
            guard let value = iterator.next() else { fail("\(argument) needs a value") }
            let parts = value.split(separator: "-").compactMap { UInt64($0) }
            guard let first = parts.first else { fail("bad seed range \(value)") }
            options.seeds = first...(parts.count > 1 ? parts[1] : first)
        case "--set":
            guard let pair = iterator.next(), let equals = pair.firstIndex(of: "="),
                  let value = Double(pair[pair.index(after: equals)...])
            else { fail("--set needs key=value") }
            options.overrides[String(pair[..<equals])] = value
        case "--quiet":
            options.quiet = true
        case "--every-sentence":
            options.book.readingInterval = options.book.sentenceLength
        case "--noise-episode":
            guard let value = iterator.next().flatMap(Double.init), value >= 0 else { fail("--noise-episode needs seconds") }
            options.book.noiseEpisode = value
        case "--track", "--track-unmarked":
            options.book.source = .track
            options.book.readingInterval = options.book.sentenceLength
            options.book.markTrackReadings = argument == "--track"
        case "--track-pin":
            guard let value = iterator.next().flatMap(Int.init), value >= 0 else { fail("--track-pin needs a sentence count") }
            options.book.trackPinSentences = value
        case "--cadence":
            guard let value = iterator.next().flatMap(Double.init), value > 0 else { fail("--cadence needs seconds") }
            options.book.readingInterval = value
        case "-h", "--help":
            print("""
            usage: lofi-replay [--set key=value] [--quiet] (script.json ... | --synthetic [--hours H] [--seeds A-B]
                               | --write-synthetic out.json [--seed N] [--hours H])
                   made-up books: [--every-sentence] [--noise-episode S] [--track | --track-unmarked]
                                  [--track-pin N] [--cadence S]
            """)
            exit(0)
        default:
            options.scripts.append(argument)
        }
    }
    return options
}

func config(applying overrides: [String: Double], to base: DirectorConfig = DirectorConfig()) -> DirectorConfig {
    guard !overrides.isEmpty else { return base }
    do {
        var merged = try JSONSerialization.jsonObject(with: JSONEncoder().encode(base)) as? [String: Any] ?? [:]
        for (key, value) in overrides {
            guard merged[key] != nil else { fail("unknown config key \(key)") }
            merged[key] = value
        }
        return try JSONDecoder().decode(DirectorConfig.self, from: JSONSerialization.data(withJSONObject: merged))
    } catch {
        fail("could not apply overrides: \(error)")
    }
}

func describe(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded())
    return String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
}

let options = parse(Array(CommandLine.arguments.dropFirst()))

if let path = options.writeSynthetic {
    var bookOptions = options.book
    bookOptions.hours = options.hours
    let book = SyntheticBook.generate(seed: options.seeds.lowerBound, options: bookOptions)
    do {
        try book.script.jsonData().write(to: URL(fileURLWithPath: path))
        print("wrote \(book.script.events.count) events to \(path)")
    } catch {
        fail("could not write \(path): \(error)")
    }
    exit(0)
}

if options.synthetic {
    let directorConfig = config(applying: options.overrides)
    var bookOptions = options.book
    bookOptions.hours = options.hours
    var changeRates: [Double] = []
    var agreements: [Double] = []
    var lagged: [Double] = []
    var delays: [Double] = []
    var missedShares: [Double] = []
    var violations = 0
    for seed in options.seeds {
        let book = SyntheticBook.generate(seed: seed, options: bookOptions)
        let result = ReplayRunner.run(book.script, config: directorConfig)
        let follow = result.followDelay(in: book)
        changeRates.append(result.changesPerHour)
        agreements.append(result.agreement(with: book))
        lagged.append(result.agreement(with: book, lag: 120))
        if let median = follow.median { delays.append(median) }
        missedShares.append(follow.missed)
        violations += result.dwellViolations(
            minimumDwell: directorConfig.minimumDwell,
            trackMinimumDwell: directorConfig.trackMinimumDwell
        ).count
        if !options.quiet {
            print(String(
                format: "seed %3llu: %5.1f changes/h, agreement %4.0f%% (%4.0f%% allowing 2 min lag), median follow %5.0fs, missed %3.0f%%",
                seed, result.changesPerHour, 100 * agreements.last!, 100 * lagged.last!, follow.median ?? -1, 100 * follow.missed
            ))
        }
    }
    func mean(_ values: [Double]) -> Double { values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count) }
    print(String(
        format: "mean over %d books of %.0f h: %.1f changes/h (max %.1f), agreement %.0f%%, %.0f%% allowing 2 min lag, median follow %.0fs, missed %.0f%%, dwell violations %d",
        changeRates.count, options.hours, mean(changeRates), changeRates.max() ?? 0, 100 * mean(agreements), 100 * mean(lagged),
        mean(delays), 100 * mean(missedShares), violations
    ))
    exit(0)
}

guard !options.scripts.isEmpty else { fail("nothing to replay; see --help") }
var allPassed = true
for path in options.scripts {
    let script: ReplayScript
    do {
        script = try ReplayScript.load(from: URL(fileURLWithPath: path))
    } catch {
        fail("could not read \(path): \(error)")
    }
    let directorConfig = config(applying: options.overrides, to: script.config ?? DirectorConfig())
    let result = ReplayRunner.run(script, config: directorConfig)
    print("\(script.title ?? path)")
    if !options.quiet {
        for decision in result.decisions {
            print("  \(describe(decision.time))  \(decision.previous) -> \(decision.bucket)  [\(decision.reason.rawValue), \(decision.transition.rawValue)]" + (decision.provisional ? " provisional" : ""))
        }
    }
    let ignored = result.ignoredCounts.map { "\($0.key.rawValue) \($0.value)" }.sorted().joined(separator: ", ")
    print("  \(result.decisions.count) changes in \(describe(result.duration)), ends on \(result.finalBucket)" + (ignored.isEmpty ? "" : "; ignored: \(ignored)"))
    for failure in result.failures {
        print("  FAIL \(failure)")
    }
    allPassed = allPassed && result.passed
}
exit(allPassed ? 0 : 1)
