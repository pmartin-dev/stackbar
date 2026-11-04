import ComposableArchitecture
import Darwin
import Foundation

struct ListeningProcess: Equatable, Sendable {
  var processIdentifier: Int32
  var processGroup: Int32
  var name: String
}

struct PortClient: Sendable {
  /// Processes listening on the TCP port, empty when the port is free.
  var listeners: @Sendable (Int) async -> [ListeningProcess]
  var lastDetectedPort: @Sendable (UUID) -> Int?
  var rememberDetectedPort: @Sendable (UUID, Int) -> Void
  /// Sends SIGTERM to the processes, then waits up to 5 seconds for the port to be released.
  var freePort: @Sendable (Int, [Int32]) async -> Bool
}

extension PortClient: DependencyKey {
  static let liveValue = PortClient(
    listeners: { port in await Task.detached { PortInspector.listeners(on: port) }.value },
    lastDetectedPort: { serviceID in
      let port = UserDefaults.standard.integer(forKey: PortInspector.defaultsKey(serviceID))
      return port > 0 ? port : nil
    },
    rememberDetectedPort: { serviceID, port in
      UserDefaults.standard.set(port, forKey: PortInspector.defaultsKey(serviceID))
    },
    freePort: { port, processIdentifiers in
      for processIdentifier in processIdentifiers {
        kill(processIdentifier, SIGTERM)
      }
      let deadline = ContinuousClock.now.advanced(by: .seconds(5))
      while ContinuousClock.now < deadline {
        if await Task.detached(operation: { PortInspector.listeners(on: port) }).value.isEmpty {
          return true
        }
        try? await Task.sleep(for: .milliseconds(200))
      }
      return false
    }
  )

  static let testValue = PortClient(
    listeners: { _ in [] },
    lastDetectedPort: { _ in nil },
    rememberDetectedPort: { _, _ in },
    freePort: { _, _ in true }
  )
}

extension DependencyValues {
  var portClient: PortClient {
    get { self[PortClient.self] }
    set { self[PortClient.self] = newValue }
  }
}

enum PortInspector {
  static func defaultsKey(_ serviceID: UUID) -> String {
    "lastDetectedPort.\(serviceID.uuidString)"
  }

  static func listeners(on port: Int) -> [ListeningProcess] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
    process.arguments = ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-Fpc"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice
    do {
      try process.run()
    } catch {
      return []
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return parse(String(decoding: data, as: UTF8.self))
  }

  /// Parses `lsof -F pc` output: `p<pid>` lines each followed by a `c<command>` line.
  static func parse(_ output: String) -> [ListeningProcess] {
    var result: [ListeningProcess] = []
    for line in output.split(whereSeparator: \.isNewline) {
      if line.hasPrefix("p"), let processIdentifier = Int32(line.dropFirst()) {
        guard !result.contains(where: { $0.processIdentifier == processIdentifier }) else { continue }
        result.append(ListeningProcess(
          processIdentifier: processIdentifier,
          processGroup: getpgid(processIdentifier),
          name: ""
        ))
      } else if line.hasPrefix("c"), !result.isEmpty, result[result.count - 1].name.isEmpty {
        result[result.count - 1].name = String(line.dropFirst())
      }
    }
    return result
  }
}
