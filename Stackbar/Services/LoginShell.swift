import Darwin
import Foundation

enum LoginShellError: LocalizedError, Equatable, Sendable {
  case unavailable
  case unsupported(String)
  case notExecutable(String)

  var errorDescription: String? {
    switch self {
    case .unavailable:
      "The login shell for this macOS account could not be determined."
    case let .unsupported(path):
      "Stackbar supports zsh and bash login shells, not \(path)."
    case let .notExecutable(path):
      "The configured login shell is not executable: \(path)"
    }
  }
}

struct LoginShell: Equatable, Sendable {
  private enum Family: Sendable {
    case zsh
    case bash
  }

  let path: String
  private let family: Family

  init(path: String) throws {
    let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
    guard normalizedPath.hasPrefix("/") else {
      throw LoginShellError.unsupported(path)
    }
    switch URL(fileURLWithPath: normalizedPath).lastPathComponent {
    case "zsh":
      family = .zsh
    case "bash":
      family = .bash
    default:
      throw LoginShellError.unsupported(normalizedPath)
    }
    self.path = normalizedPath
  }

  func arguments(for command: String) -> [String] {
    // Keep background jobs in the process group Stackbar signals when stopping a service.
    let commandWithJobControlDisabled = "set +m; \(command)"
    switch family {
    case .zsh:
      return ["-ilc", commandWithJobControlDisabled]
    case .bash:
      return ["--login", "-i", "-c", commandWithJobControlDisabled]
    }
  }

  static func current(fileManager: FileManager = .default) throws -> LoginShell {
    guard
      let account = getpwuid(getuid()),
      let shellPath = account.pointee.pw_shell
    else {
      throw LoginShellError.unavailable
    }
    let shell = try LoginShell(path: String(cString: shellPath))
    guard fileManager.isExecutableFile(atPath: shell.path) else {
      throw LoginShellError.notExecutable(shell.path)
    }
    return shell
  }
}
