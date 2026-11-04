import Foundation

struct DetectedCommand: Equatable, Hashable, Identifiable, Sendable {
  enum Source: String, CaseIterable, Sendable {
    case packageJSON, makefile, dockerCompose, procfile, taskfile, gradle, maven, cargo, go, python

    var displayName: String {
      switch self {
      case .packageJSON: "package.json"
      case .makefile: "Makefile"
      case .dockerCompose: "Docker Compose"
      case .procfile: "Procfile"
      case .taskfile: "Taskfile"
      case .gradle: "Gradle"
      case .maven: "Maven"
      case .cargo: "Cargo"
      case .go: "Go"
      case .python: "Python"
      }
    }

    fileprivate var shortLabel: String {
      switch self {
      case .packageJSON: "npm"
      case .makefile: "make"
      case .dockerCompose: "compose"
      case .procfile: "procfile"
      case .taskfile: "task"
      case .gradle: "gradle"
      case .maven: "maven"
      case .cargo: "cargo"
      case .go: "go"
      case .python: "python"
      }
    }
  }

  var name: String
  var command: String
  var stopCommand: String?
  var source: Source
  var isLikelyService: Bool

  var id: String { name }

  init(name: String, command: String, stopCommand: String? = nil, source: Source, isLikelyService: Bool) {
    self.name = name
    self.command = command
    self.stopCommand = stopCommand
    self.source = source
    self.isLikelyService = isLikelyService
  }
}

/// Scans the root of a project folder for well-known manifests and proposes launch commands.
enum CommandDetector {
  static func detect(in directory: URL, fileManager: FileManager = .default) -> [DetectedCommand] {
    let root = Root(directory: directory, fileManager: fileManager)
    let detected = packageScripts(root)
      + makeTargets(root)
      + compose(root)
      + procfile(root)
      + taskfile(root)
      + gradle(root)
      + maven(root)
      + cargo(root)
      + go(root)
      + python(root)
    return disambiguated(detected)
  }

  // MARK: - Sources

  private static let likelyNames: Set<String> = ["run", "dev", "start", "serve", "up", "watch", "preview"]
  private static let teardownWords: Set<String> = ["down", "stop", "kill", "clean", "reset", "build", "test", "lint"]

  /// `dev`, `start:mock`, `dev:up` look like long-running services; `dev:down` or `prod:up` do not.
  static func looksLikeService(_ name: String) -> Bool {
    let parts = name.lowercased().split(whereSeparator: { ":-_/".contains($0) }).map(String.init)
    guard let base = parts.first, likelyNames.contains(base) else { return false }
    return !parts.dropFirst().contains { teardownWords.contains($0) }
  }

  private static func packageScripts(_ root: Root) -> [DetectedCommand] {
    guard
      let text = root.read("package.json"),
      let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
      let scripts = json["scripts"] as? [String: Any]
    else { return [] }

    let runner = if root.exists("pnpm-lock.yaml") {
      "pnpm"
    } else if root.exists("yarn.lock") {
      "yarn"
    } else if root.exists("bun.lockb") || root.exists("bun.lock") {
      "bun run"
    } else {
      "npm run"
    }

    // JSONSerialization does not keep key order; restore the file order.
    let names = scripts.keys.sorted { lhs, rhs in
      position(of: lhs, in: text) < position(of: rhs, in: text)
    }
    return names.compactMap { name in
      guard
        name.contains(where: { $0.isLetter || $0.isNumber }),
        let body = (scripts[name] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
        !body.isEmpty,
        !body.contains("no test specified")
      else { return nil }
      return DetectedCommand(
        name: name,
        command: "\(runner) \(name)",
        source: .packageJSON,
        isLikelyService: looksLikeService(name)
      )
    }
  }

  private static func makeTargets(_ root: Root) -> [DetectedCommand] {
    guard let text = root.read("Makefile") ?? root.read("makefile") ?? root.read("GNUmakefile") else { return [] }
    let pattern = /^([A-Za-z0-9_][A-Za-z0-9_\-\/]*)\s*:(?!=)/
    var seen = Set<String>()
    return text.split(whereSeparator: \.isNewline).compactMap { line in
      guard let match = String(line).firstMatch(of: pattern) else { return nil }
      let target = String(match.1)
      guard seen.insert(target).inserted else { return nil }
      return DetectedCommand(
        name: target,
        command: "make \(target)",
        source: .makefile,
        isLikelyService: looksLikeService(target)
      )
    }
  }

  private static func compose(_ root: Root) -> [DetectedCommand] {
    let files = ["compose.yaml", "compose.yml", "docker-compose.yaml", "docker-compose.yml"]
    guard files.contains(where: root.exists) else { return [] }
    return [DetectedCommand(
      name: "compose",
      command: "docker compose up",
      stopCommand: "docker compose down",
      source: .dockerCompose,
      isLikelyService: true
    )]
  }

  private static func procfile(_ root: Root) -> [DetectedCommand] {
    guard let text = root.read("Procfile") else { return [] }
    return text.split(whereSeparator: \.isNewline).compactMap { line in
      let line = line.trimmingCharacters(in: .whitespaces)
      guard !line.hasPrefix("#"), let colon = line.firstIndex(of: ":") else { return nil }
      let name = line[..<colon].trimmingCharacters(in: .whitespaces)
      let command = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
      guard !name.isEmpty, !command.isEmpty else { return nil }
      return DetectedCommand(name: name, command: command, source: .procfile, isLikelyService: true)
    }
  }

  private static func taskfile(_ root: Root) -> [DetectedCommand] {
    let names = [
      "Taskfile.yml", "Taskfile.yaml", "taskfile.yml", "taskfile.yaml",
      "Taskfile.dist.yml", "Taskfile.dist.yaml", "taskfile.dist.yml", "taskfile.dist.yaml",
    ]
    guard let text = names.lazy.compactMap(root.read).first else { return [] }
    var inTasks = false
    var taskIndent: Int?
    var commands: [DetectedCommand] = []
    for rawLine in text.split(whereSeparator: \.isNewline) {
      let line = String(rawLine)
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
      let indent = line.prefix { $0 == " " }.count
      if indent == 0 {
        inTasks = trimmed == "tasks:"
        taskIndent = nil
        continue
      }
      guard inTasks else { continue }
      if taskIndent == nil { taskIndent = indent }
      guard indent == taskIndent, trimmed.hasSuffix(":") else { continue }
      let name = String(trimmed.dropLast()).trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
      guard !name.isEmpty else { continue }
      commands.append(DetectedCommand(
        name: name,
        command: "task \(name)",
        source: .taskfile,
        isLikelyService: looksLikeService(name)
      ))
    }
    return commands
  }

  private static func gradle(_ root: Root) -> [DetectedCommand] {
    guard let text = root.read("build.gradle.kts") ?? root.read("build.gradle") else { return [] }
    let tool = root.exists("gradlew") ? "./gradlew" : "gradle"
    var commands: [DetectedCommand] = []
    if text.contains("org.springframework.boot") {
      commands.append(DetectedCommand(name: "bootRun", command: "\(tool) bootRun", source: .gradle, isLikelyService: true))
    }
    if text.contains("application") {
      commands.append(DetectedCommand(name: "run", command: "\(tool) run", source: .gradle, isLikelyService: true))
    }
    commands.append(DetectedCommand(name: "build", command: "\(tool) build", source: .gradle, isLikelyService: false))
    commands.append(DetectedCommand(name: "test", command: "\(tool) test", source: .gradle, isLikelyService: false))
    return commands
  }

  private static func maven(_ root: Root) -> [DetectedCommand] {
    guard let text = root.read("pom.xml") else { return [] }
    let tool = root.exists("mvnw") ? "./mvnw" : "mvn"
    var commands: [DetectedCommand] = []
    if text.contains("spring-boot") {
      commands.append(DetectedCommand(
        name: "spring-boot:run", command: "\(tool) spring-boot:run", source: .maven, isLikelyService: true
      ))
    }
    commands.append(DetectedCommand(name: "package", command: "\(tool) package", source: .maven, isLikelyService: false))
    commands.append(DetectedCommand(name: "test", command: "\(tool) test", source: .maven, isLikelyService: false))
    return commands
  }

  private static func cargo(_ root: Root) -> [DetectedCommand] {
    guard root.exists("Cargo.toml") else { return [] }
    return [
      DetectedCommand(name: "run", command: "cargo run", source: .cargo, isLikelyService: true),
      DetectedCommand(name: "test", command: "cargo test", source: .cargo, isLikelyService: false),
      DetectedCommand(name: "build", command: "cargo build", source: .cargo, isLikelyService: false),
    ]
  }

  private static func go(_ root: Root) -> [DetectedCommand] {
    guard root.exists("go.mod") else { return [] }
    return [
      DetectedCommand(name: "run", command: "go run .", source: .go, isLikelyService: true),
      DetectedCommand(name: "test", command: "go test ./...", source: .go, isLikelyService: false),
    ]
  }

  private static func python(_ root: Root) -> [DetectedCommand] {
    let prefix = if root.exists("uv.lock") {
      "uv run "
    } else if root.exists("poetry.lock") {
      "poetry run "
    } else {
      ""
    }
    var commands: [DetectedCommand] = []
    if root.exists("manage.py") {
      commands.append(DetectedCommand(
        name: "runserver", command: "\(prefix)python manage.py runserver", source: .python, isLikelyService: true
      ))
    }
    let fastAPIModules = [("main.py", "main"), ("app/main.py", "app.main")]
    if let module = fastAPIModules.first(where: { root.read($0.0)?.contains("FastAPI(") == true })?.1 {
      commands.append(DetectedCommand(
        name: "uvicorn", command: "\(prefix)uvicorn \(module):app --reload", source: .python, isLikelyService: true
      ))
    }
    return commands
  }

  // MARK: - Helpers

  private static func disambiguated(_ commands: [DetectedCommand]) -> [DetectedCommand] {
    var used = Set<String>()
    return commands.map { command in
      var command = command
      if used.contains(command.name) {
        let base = "\(command.name) (\(command.source.shortLabel))"
        var candidate = base
        var index = 2
        while used.contains(candidate) {
          candidate = "\(base) \(index)"
          index += 1
        }
        command.name = candidate
      }
      used.insert(command.name)
      return command
    }
  }

  private static func position(of key: String, in text: String) -> String.Index {
    text.range(of: "\"\(key)\"")?.lowerBound ?? text.endIndex
  }

  private struct Root {
    let directory: URL
    let fileManager: FileManager

    func exists(_ name: String) -> Bool {
      fileManager.fileExists(atPath: directory.appendingPathComponent(name).path)
    }

    func read(_ name: String) -> String? {
      let url = directory.appendingPathComponent(name)
      guard let data = fileManager.contents(atPath: url.path), data.count < 1_000_000 else { return nil }
      return String(data: data, encoding: .utf8)
    }
  }
}
