// LOFI-FORK: the logic of `podcast-teach fit`, here so tests can call it (see FORK.md). Foundation only.
import Foundation

extension AdWordFit {
  public static let usage =
    "Usage: podcast-teach fit <examples file> <output file> [--c 0.1] [--min-count 3] [--class-cap 5] [--iterations 300]"

  /// The two file names and the settings in the arguments, or a plain sentence about what is wrong.
  public static func parse(arguments: [String]) -> Swift.Result<(input: String, output: String, settings: Settings), AdWordFitError> {
    var settings = Settings()
    var files: [String] = []
    var index = 0
    func fail(_ text: String) -> Swift.Result<(input: String, output: String, settings: Settings), AdWordFitError> {
      .failure(AdWordFitError(message: text))
    }
    func next(_ flag: String) -> String? {
      index += 1
      return index < arguments.count ? arguments[index] : nil
    }
    while index < arguments.count {
      let argument = arguments[index]
      switch argument {
      case "--c":
        guard let text = next(argument), let value = Double(text), value.isFinite, value > 0 else {
          return fail("--c needs a number above 0.")
        }
        settings.c = value
      case "--class-cap":
        guard let text = next(argument), let value = Double(text), value.isFinite, value >= 1 else {
          return fail("--class-cap needs a number of 1 or more.")
        }
        settings.classCap = value
      case "--min-count":
        guard let text = next(argument), let value = Int(text), value >= 1 else {
          return fail("--min-count needs a whole number from 1.")
        }
        settings.minCount = value
      case "--iterations":
        guard let text = next(argument), let value = Int(text), value >= 1 else {
          return fail("--iterations needs a whole number from 1.")
        }
        settings.iterations = value
      case let flag where flag.hasPrefix("--"):
        return fail("Unknown option \(flag).")
      default:
        files.append(argument)
      }
      index += 1
    }
    guard files.count == 2 else { return fail("Name the examples file and the output file.") }
    return .success((files[0], files[1], settings))
  }

  /// Runs the command and returns the exit code: 0 it worked, 2 a set-up problem (said in `err`).
  public static func run(_ arguments: [String], out: (String) -> Void, err: (String) -> Void) -> Int32 {
    let options: (input: String, output: String, settings: Settings)
    switch parse(arguments: arguments) {
    case .failure(let problem):
      err("\(problem.message)\n\(usage)")
      return 2
    case .success(let parsed): options = parsed
    }
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: options.input), options: .mappedIfSafe) else {
      err("The examples file \(options.input) cannot be read.")
      return 2
    }
    let examples: Examples
    switch parse(data) {
    case .failure(let problem):
      err(problem.message)
      return 2
    case .success(let parsed): examples = parsed
    }
    out("Fitting \(examples.count) lines over \(examples.buckets) buckets.")
    let result = fit(examples, settings: options.settings, progress: out)
    guard result.objective.isFinite, result.bias.allSatisfy(\.isFinite), result.weights.allSatisfy(\.isFinite) else {
      err("The fit did not give usable numbers.")
      return 2
    }
    do {
      try Data(json(result).utf8).write(to: URL(fileURLWithPath: options.output), options: .atomic)
    } catch {
      err("The result cannot be written to \(options.output): \(error.localizedDescription)")
      return 2
    }
    out("Fitted \(result.buckets.count) buckets in \(result.iterations) passes, objective \(result.objective).")
    return 0
  }
}
