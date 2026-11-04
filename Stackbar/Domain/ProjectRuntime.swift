import Foundation

enum ProjectExit: Equatable, Sendable {
  case normal
  case error(String)
}

enum ProjectRuntimeStatus: Equatable, Sendable {
  case stopped
  case starting
  case running(processIdentifier: Int32)
  case stopping
  case exited(ProjectExit)

  var isActive: Bool {
    switch self {
    case .starting, .running, .stopping:
      true
    case .stopped, .exited:
      false
    }
  }
}

struct ProjectRuntime: Equatable, Sendable {
  var status: ProjectRuntimeStatus = .stopped
  var detectedURL: URL?
  var hasLogs = false
  var lastError: String?
}

/// Aggregated view of a project's service runtimes.
struct ProjectStatusSummary: Equatable, Sendable {
  enum Status: Equatable, Sendable {
    case stopped
    case starting
    case running
    case partial
    case stopping
    case failed
  }

  var status: Status
  var runningCount: Int
  var totalCount: Int
  var errorMessage: String?

  var isActive: Bool {
    switch status {
    case .starting, .running, .partial, .stopping: true
    case .stopped, .failed: false
    }
  }

  init(_ runtimes: [ProjectRuntime]) {
    totalCount = runtimes.count
    runningCount = runtimes.filter {
      if case .running = $0.status { return true }
      return false
    }.count
    errorMessage = runtimes.lazy.compactMap { runtime -> String? in
      if let error = runtime.lastError { return error }
      if case let .exited(.error(message)) = runtime.status { return message }
      return nil
    }.first

    if runtimes.contains(where: { $0.status == .stopping }) {
      status = .stopping
    } else if runtimes.contains(where: { $0.status == .starting }) {
      status = .starting
    } else if runningCount > 0 {
      status = runningCount == totalCount ? .running : .partial
    } else if errorMessage != nil {
      status = .failed
    } else {
      status = .stopped
    }
  }
}
