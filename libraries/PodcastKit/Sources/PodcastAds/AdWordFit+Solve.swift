// LOFI-FORK: the solver of `podcast-teach fit`: L-BFGS on the penalised softmax loss. Foundation only.
import Foundation

extension AdWordFit {
  /// The examples with the rare buckets left out and the rest numbered from 0, ready to be
  /// summed over fast. The parameters are five biases, then five numbers for each kept bucket.
  private final class Problem: @unchecked Sendable {
    let labels: [UInt8]
    let starts: [Int]
    let items: [Int32]
    let classWeight: [Double]
    let c: Double
    let size: Int  // the number of parameters
    let chunks = 8  // always the same, so the sums come out the same on any machine
    private var scratch: [UnsafeMutablePointer<Double>] = []

    init(labels: [UInt8], starts: [Int], items: [Int32], kept: Int, classWeight: [Double], c: Double) {
      self.labels = labels
      self.starts = starts
      self.items = items
      self.classWeight = classWeight
      self.c = c
      size = 5 * (kept + 1)
      for _ in 0..<chunks {
        let buffer = UnsafeMutablePointer<Double>.allocate(capacity: size)
        buffer.initialize(repeating: 0, count: size)
        scratch.append(buffer)
      }
    }

    deinit { for buffer in scratch { buffer.deallocate() } }

    /// Pointers handed to the threads of one evaluation. Each thread writes only its own chunk.
    private struct Shared: @unchecked Sendable {
      let theta: UnsafePointer<Double>
      let buffers: [UnsafeMutablePointer<Double>]
      let losses: UnsafeMutablePointer<Double>
    }

    /// The objective at `theta`, with its gradient in `gradient`.
    func evaluate(_ theta: [Double], _ gradient: inout [Double]) -> Double {
      let total = labels.count
      var losses = [Double](repeating: 0, count: chunks)
      let buffers = scratch
      theta.withUnsafeBufferPointer { thetaPointer in
        losses.withUnsafeMutableBufferPointer { lossPointer in
          let shared = Shared(theta: thetaPointer.baseAddress!, buffers: buffers, losses: lossPointer.baseAddress!)
          DispatchQueue.concurrentPerform(iterations: chunks) { chunk in
            let t = shared.theta
            let g = shared.buffers[chunk]
            g.update(repeating: 0, count: size)
            let from = total * chunk / chunks
            let to = total * (chunk + 1) / chunks
            var loss = 0.0
            for e in from..<to {
              var z = (t[0], t[1], t[2], t[3], t[4])
              for at in starts[e]..<starts[e + 1] {
                let k = 5 + 5 * Int(items[at])
                z.0 += t[k]; z.1 += t[k + 1]; z.2 += t[k + 2]; z.3 += t[k + 3]; z.4 += t[k + 4]
              }
              let top = max(max(max(z.0, z.1), max(z.2, z.3)), z.4)
              let e0 = exp(z.0 - top), e1 = exp(z.1 - top), e2 = exp(z.2 - top)
              let e3 = exp(z.3 - top), e4 = exp(z.4 - top)
              let norm = e0 + e1 + e2 + e3 + e4
              let y = Int(labels[e])
              let weight = classWeight[y]
              let zy: Double
              switch y {
              case 0: zy = z.0
              case 1: zy = z.1
              case 2: zy = z.2
              case 3: zy = z.3
              default: zy = z.4
              }
              loss += weight * (log(norm) - (zy - top))
              var slope = (weight * e0 / norm, weight * e1 / norm, weight * e2 / norm, weight * e3 / norm, weight * e4 / norm)
              switch y {
              case 0: slope.0 -= weight
              case 1: slope.1 -= weight
              case 2: slope.2 -= weight
              case 3: slope.3 -= weight
              default: slope.4 -= weight
              }
              g[0] += slope.0; g[1] += slope.1; g[2] += slope.2; g[3] += slope.3; g[4] += slope.4
              for at in starts[e]..<starts[e + 1] {
                let k = 5 + 5 * Int(items[at])
                g[k] += slope.0; g[k + 1] += slope.1; g[k + 2] += slope.2; g[k + 3] += slope.3; g[k + 4] += slope.4
              }
            }
            shared.losses[chunk] = loss
          }
        }
      }
      var objective = 0.0
      for loss in losses { objective += loss }
      for i in 0..<size {
        var sum = 0.0
        for buffer in buffers { sum += buffer[i] }
        gradient[i] = sum
      }
      var squares = 0.0
      for i in 5..<size {
        squares += theta[i] * theta[i]
        gradient[i] += theta[i] / c
      }
      return objective + squares / (2 * c)
    }
  }

  /// Fits the examples. `progress` is told about every 25th pass.
  public static func fit(
    _ examples: Examples, settings: Settings, progress: (String) -> Void = { _ in }
  ) -> Result {
    // Which buckets occur in enough lines.
    var occurs = [Int32](repeating: 0, count: examples.buckets)
    for item in examples.items { occurs[Int(item)] += 1 }
    var dense = [Int32](repeating: -1, count: examples.buckets)
    var kept: [Int32] = []
    for b in 0..<examples.buckets where Int(occurs[b]) >= settings.minCount {
      dense[b] = Int32(kept.count)
      kept.append(Int32(b))
    }
    occurs = []
    var items: [Int32] = []
    items.reserveCapacity(examples.items.count)
    var starts = [0]
    starts.reserveCapacity(examples.starts.count)
    for e in 0..<examples.count {
      for at in examples.starts[e]..<examples.starts[e + 1] where dense[Int(examples.items[at])] >= 0 {
        items.append(dense[Int(examples.items[at])])
      }
      starts.append(items.count)
    }
    let problem = Problem(
      labels: examples.labels, starts: starts, items: items, kept: kept.count,
      classWeight: classWeights(examples.labels, cap: settings.classCap), c: settings.c)
    let n = problem.size

    var x = [Double](repeating: 0, count: n)
    var g = [Double](repeating: 0, count: n)
    var f = problem.evaluate(x, &g)
    var pairs: [(s: [Double], y: [Double], rho: Double)] = []
    var done = 0
    var xNew = x
    var gNew = g
    var d = g
    func dot(_ a: [Double], _ b: [Double]) -> Double {
      var sum = 0.0
      for i in 0..<a.count { sum += a[i] * b[i] }
      return sum
    }
    for pass in 1...settings.iterations {
      let gradientNorm = dot(g, g).squareRoot()
      if gradientNorm <= 1e-6 * max(1, abs(f)) { break }
      // The L-BFGS direction by the two-loop recursion.
      d = g
      var alphas = [Double](repeating: 0, count: pairs.count)
      for k in stride(from: pairs.count - 1, through: 0, by: -1) {
        alphas[k] = pairs[k].rho * dot(pairs[k].s, d)
        for i in 0..<n { d[i] -= alphas[k] * pairs[k].y[i] }
      }
      if let last = pairs.last {
        let scale = dot(last.s, last.y) / dot(last.y, last.y)
        for i in 0..<n { d[i] *= scale }
      }
      for k in 0..<pairs.count {
        let beta = pairs[k].rho * dot(pairs[k].y, d)
        for i in 0..<n { d[i] += (alphas[k] - beta) * pairs[k].s[i] }
      }
      for i in 0..<n { d[i] = -d[i] }
      var slope = dot(g, d)
      if !(slope < 0) {
        pairs.removeAll()
        for i in 0..<n { d[i] = -g[i] }
        slope = -dot(g, g)
      }
      var step = pairs.isEmpty ? min(1, 1 / gradientNorm) : 1
      var accepted = false
      var fNew = f
      for _ in 0..<40 {
        for i in 0..<n { xNew[i] = x[i] + step * d[i] }
        fNew = problem.evaluate(xNew, &gNew)
        if fNew.isFinite, fNew <= f + 1e-4 * step * slope {
          accepted = true
          break
        }
        step *= 0.5
      }
      if !accepted {
        if pairs.isEmpty { break }
        pairs.removeAll()  // try again along the steepest descent
        continue
      }
      var s = [Double](repeating: 0, count: n)
      var y = [Double](repeating: 0, count: n)
      for i in 0..<n {
        s[i] = xNew[i] - x[i]
        y[i] = gNew[i] - g[i]
      }
      let sy = dot(s, y)
      if sy > 1e-10 * dot(y, y) {
        if pairs.count == 10 { pairs.removeFirst() }
        pairs.append((s, y, 1 / sy))
      }
      swap(&x, &xNew)
      swap(&g, &gNew)
      f = fNew
      done = pass
      if pass % 25 == 0 { progress("Pass \(pass): objective \(f).") }
    }
    var weights: [Double] = []
    weights.reserveCapacity(kept.count * 5)
    weights.append(contentsOf: x[5...])
    return Result(bias: Array(x[0..<5]), buckets: kept, weights: weights, iterations: done, objective: f)
  }

  /// The result as the JSON the trainer reads.
  public static func json(_ result: Result) -> String {
    func list(_ values: ArraySlice<Double>) -> String { "[" + values.map { "\($0)" }.joined(separator: ",") + "]" }
    var text = "{\"bias\":" + list(result.bias[...]) + ",\"weights\":{"
    for (k, bucket) in result.buckets.enumerated() {
      if k > 0 { text += "," }
      text += "\"\(bucket)\":" + list(result.weights[(5 * k)..<(5 * k + 5)])
    }
    return text + "},\"iterations\":\(result.iterations),\"objective\":\(result.objective)}\n"
  }
}
