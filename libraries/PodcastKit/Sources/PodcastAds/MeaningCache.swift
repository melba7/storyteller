// LOFI-FORK: the Mac's kept vectors and its check for repeated episodes, for the meaning
// model's training (see FORK.md). Foundation only.
import Foundation

/// The vectors of an episode's lines, kept in `meaning-cache/` of the teaching folder, so a second
/// run does not embed every line again. A cache file is named by the episode, a fingerprint of
/// its lines' text, and the embedding's revision and size, so changed text or another embedding
/// is never read from an old file. It holds one row of Float32 numbers for each line (length 1),
/// and a row of zeros for a line with no vector. A file of the wrong length is embedded again.
/// The cache is only a speed-up: when it cannot be written, nothing is lost.
struct MeaningCache {
  let folder: URL
  let revision: Int
  let dimension: Int

  /// The vector (length 1) of each line, nil for a line with none.
  func vectors(id: String, texts: [String], embedder: LineEmbedder) -> [[Float]?] {
    let name = "\(id).\(Self.fingerprint(texts)).r\(revision).d\(dimension).f32"
    let file = folder.appendingPathComponent(name)
    if let data = try? Data(contentsOf: file), let numbers = Float32Bytes.decode(data),
      numbers.count == texts.count * dimension
    {
      return texts.indices.map { line in
        let row = Array(numbers[(line * dimension)..<((line + 1) * dimension)])
        return row.contains { $0 != 0 } ? row : nil
      }
    }
    var found: [[Float]?] = []
    var flat: [Float] = []
    flat.reserveCapacity(texts.count * dimension)
    for text in texts {
      if let raw = embedder.vector(for: text), raw.count == dimension,
        let unit = MeaningVectors.unit(raw)
      {
        let row = unit.map { Float($0) }
        found.append(row)
        flat.append(contentsOf: row)
      } else {
        found.append(nil)
        flat.append(contentsOf: [Float](repeating: 0, count: dimension))
      }
    }
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    if (try? Float32Bytes.encode(flat).write(to: file, options: .atomic)) != nil {
      // One file for each episode: an older one for other text or another embedding goes. A
      // name is "<id>.<fingerprint>.r<revision>.d<dimension>.f32"; an id that itself holds a
      // dot never matches the one that is a part of it.
      for other in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
      where other != name && other.hasPrefix(id + ".") {
        let rest = other.dropFirst(id.count + 1).split(separator: ".", omittingEmptySubsequences: false)
        if rest.count == 4, rest[3] == "f32" {
          try? FileManager.default.removeItem(at: folder.appendingPathComponent(other))
        }
      }
    }
    return found
  }

  /// A 64-bit FNV-1a fingerprint of the lines' text, in hexadecimal.
  static func fingerprint(_ texts: [String]) -> String {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for text in texts {
      for byte in text.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 1_099_511_628_211
      }
      hash ^= 10
      hash = hash &* 1_099_511_628_211
    }
    return String(hash, radix: 16)
  }
}

/// Which training episodes are really an episode of the held-out shelf again, so the shelf stays a
/// fair test: more than half of the 5-word runs of the transcript are also in a shelf episode's
/// (the rule of `teach_overlap.py`, without its feed key and audio checks: the same episode has
/// nearly the same words wherever it came from).
enum MeaningOverlap {
  static let runLength = 5

  /// The set of runs of 5 words, each word in lower case with everything but letters and digits removed.
  static func runs(_ episode: TeachingEpisode) -> Set<[String]> {
    var words: [String] = []
    for line in episode.transcript.lines {
      for piece in line.text.split(whereSeparator: \.isWhitespace) {
        let word = piece.lowercased().filter { $0.isLetter || $0.isNumber }
        if !word.isEmpty { words.append(word) }
      }
    }
    guard words.count >= runLength else { return [] }
    return Set((0...(words.count - runLength)).map { Array(words[$0..<($0 + runLength)]) })
  }

  /// The ids among `candidates` that repeat a shelf episode.
  static func repeating(_ candidates: [TeachingEpisode], shelf: [TeachingEpisode]) -> Set<String> {
    var shelfRuns: Set<[String]> = []
    for episode in shelf { shelfRuns.formUnion(runs(episode)) }
    var found: Set<String> = []
    for episode in candidates {
      let mine = runs(episode)
      if !mine.isEmpty, mine.intersection(shelfRuns).count * 2 > mine.count { found.insert(episode.id) }
    }
    return found
  }
}
