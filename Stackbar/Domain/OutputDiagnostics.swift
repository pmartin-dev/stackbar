import Foundation

/// Recognizes well-known failure causes in a service output to explain why it exited.
enum OutputDiagnostics {
  static func failureHint(in output: String) -> String? {
    for line in output.split(whereSeparator: \.isNewline) {
      let lowercased = line.lowercased()
      let isPortInUse = lowercased.contains("address already in use")
        || lowercased.contains("eaddrinuse")
        || lowercased.contains("port is already allocated")
        || (lowercased.contains("port") && lowercased.contains("already in use"))
      guard isPortInUse else { continue }
      if let port = port(in: lowercased) {
        return "Port \(port) is already in use by another process."
      }
      return "The port is already in use by another process."
    }
    return nil
  }

  private static func port(in line: String) -> String? {
    let expression = try! NSRegularExpression(pattern: #"(?:port\s+|:)(\d{2,5})(?!\d)"#)
    let range = NSRange(line.startIndex..<line.endIndex, in: line)
    guard
      let match = expression.matches(in: line, range: range).last,
      let portRange = Range(match.range(at: 1), in: line)
    else {
      return nil
    }
    return String(line[portRange])
  }
}
