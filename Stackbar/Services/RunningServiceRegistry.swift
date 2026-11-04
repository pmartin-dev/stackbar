import Darwin
import Foundation

/// Services running at a given time, persisted so a crashed or force-quit Stackbar can adopt them on relaunch.
struct RunningServiceRegistry: Sendable {
  struct Entry: Codable, Equatable, Sendable {
    var serviceID: UUID
    var processGroup: Int32
    /// Start time of the group leader, used to detect process identifier reuse.
    var startedAt: Double?
  }

  let fileURL: URL

  static var defaultURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/Stackbar", isDirectory: true)
      .appendingPathComponent("running.json")
  }

  func load() -> [Entry] {
    guard let data = try? Data(contentsOf: fileURL) else { return [] }
    return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
  }

  func save(_ entries: [Entry]) {
    let fileManager = FileManager.default
    if entries.isEmpty {
      try? fileManager.removeItem(at: fileURL)
      return
    }
    let directoryURL = fileURL.deletingLastPathComponent()
    try? fileManager.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(entries.sorted { $0.serviceID.uuidString < $1.serviceID.uuidString }) else {
      return
    }
    try? data.write(to: fileURL, options: .atomic)
    try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
  }

  /// Whether a recorded group still belongs to the service that was launched.
  /// A process group identifier cannot be reused while the group exists, so a vanished leader is fine;
  /// a live leader with another start time means the identifier was reused.
  static func isAlive(_ entry: Entry) -> Bool {
    guard kill(-entry.processGroup, 0) == 0 || errno == EPERM else { return false }
    guard let recorded = entry.startedAt, let current = processStartTime(entry.processGroup) else { return true }
    return abs(current - recorded) < 1
  }

  static func processStartTime(_ processIdentifier: pid_t) -> Double? {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, processIdentifier]
    guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
    let start = info.kp_proc.p_un.__p_starttime
    return Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000
  }
}
