import Foundation

struct LogSnapshot: Equatable, Sendable {
  var text = ""
  var wasTruncated = false

  var hasLogs: Bool {
    !text.isEmpty
  }
}

struct LogBuffer: Sendable {
  static let maximumBytes = 10 * 1024 * 1024

  private let maximumBytes: Int
  private var pendingUTF8: [UInt8] = []
  private var ansiStripper = ANSIControlSequenceStripper()
  private(set) var snapshot = LogSnapshot()

  init(maximumBytes: Int = Self.maximumBytes) {
    self.maximumBytes = max(1, maximumBytes)
  }

  mutating func append(_ data: Data) -> String {
    pendingUTF8.append(contentsOf: data)
    let prefixCount = completeUTF8PrefixLength(in: pendingUTF8)
    guard prefixCount > 0 else { return "" }
    let decoded = String(decoding: pendingUTF8.prefix(prefixCount), as: UTF8.self)
    pendingUTF8.removeFirst(prefixCount)
    return appendDecoded(decoded)
  }

  mutating func finish() -> String {
    guard !pendingUTF8.isEmpty else { return "" }
    let decoded = String(decoding: pendingUTF8, as: UTF8.self)
    pendingUTF8.removeAll(keepingCapacity: false)
    return appendDecoded(decoded)
  }

  private mutating func appendDecoded(_ text: String) -> String {
    let visibleText = ansiStripper.strip(text)
    snapshot.text.append(visibleText)
    trimToLimit()
    return visibleText
  }

  private mutating func trimToLimit() {
    while snapshot.text.utf8.count > maximumBytes {
      snapshot.wasTruncated = true
      if let newline = snapshot.text.firstIndex(of: "\n") {
        snapshot.text.removeSubrange(snapshot.text.startIndex...newline)
        continue
      }

      let excessBytes = snapshot.text.utf8.count - maximumBytes
      var cut = snapshot.text.utf8.index(snapshot.text.utf8.startIndex, offsetBy: excessBytes)
      while String.Index(cut, within: snapshot.text) == nil {
        cut = snapshot.text.utf8.index(after: cut)
      }
      guard let characterBoundary = String.Index(cut, within: snapshot.text) else {
        snapshot.text = ""
        return
      }
      snapshot.text.removeSubrange(snapshot.text.startIndex..<characterBoundary)
    }
  }

  private func completeUTF8PrefixLength(in bytes: [UInt8]) -> Int {
    var firstTrailingByte = bytes.count
    while firstTrailingByte > 0, bytes[firstTrailingByte - 1] & 0xC0 == 0x80 {
      firstTrailingByte -= 1
    }

    guard firstTrailingByte < bytes.count else {
      guard let lastByte = bytes.last, expectedUTF8Length(for: lastByte) > 1 else {
        return bytes.count
      }
      return bytes.count - 1
    }
    guard firstTrailingByte > 0 else { return bytes.count }

    let leadIndex = firstTrailingByte - 1
    let expectedLength = expectedUTF8Length(for: bytes[leadIndex])
    let actualLength = bytes.count - leadIndex
    return expectedLength > actualLength ? leadIndex : bytes.count
  }

  private func expectedUTF8Length(for leadByte: UInt8) -> Int {
    switch leadByte {
    case 0x00...0x7F: 1
    case 0xC2...0xDF: 2
    case 0xE0...0xEF: 3
    case 0xF0...0xF4: 4
    default: 1
    }
  }
}

private struct ANSIControlSequenceStripper: Sendable {
  private enum State: Sendable {
    case text
    case escape
    case controlSequence
    case operatingSystemCommand
    case operatingSystemCommandEscape
  }

  private var state = State.text

  mutating func strip(_ input: String) -> String {
    var output = String.UnicodeScalarView()
    for scalar in input.unicodeScalars {
      switch state {
      case .text:
        if scalar.value == 0x1B {
          state = .escape
        } else {
          output.append(scalar)
        }
      case .escape:
        switch scalar.value {
        case 0x5B:
          state = .controlSequence
        case 0x5D:
          state = .operatingSystemCommand
        default:
          state = .text
        }
      case .controlSequence:
        if (0x40...0x7E).contains(scalar.value) {
          state = .text
        }
      case .operatingSystemCommand:
        if scalar.value == 0x07 {
          state = .text
        } else if scalar.value == 0x1B {
          state = .operatingSystemCommandEscape
        }
      case .operatingSystemCommandEscape:
        state = scalar.value == 0x5C ? .text : .operatingSystemCommand
      }
    }
    return String(output)
  }
}

