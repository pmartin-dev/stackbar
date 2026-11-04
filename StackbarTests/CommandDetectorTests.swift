import Foundation
import Testing
@testable import Stackbar

struct CommandDetectorTests {
  @Test
  func detectsPackageScriptsWithLockfileRunner() throws {
    let directory = try makeDirectory([
      "package.json": #"{"scripts": {"dev": "vite", "build": "vite build", "start:api": "node api.js"}}"#,
      "pnpm-lock.yaml": "",
    ])
    defer { try? FileManager.default.removeItem(at: directory) }

    let commands = CommandDetector.detect(in: directory)

    #expect(commands.map(\.command) == ["pnpm dev", "pnpm build", "pnpm start:api"])
    #expect(commands.map(\.isLikelyService) == [true, false, true])
    #expect(commands.allSatisfy { $0.source == .packageJSON })
  }

  @Test
  func defaultsToNpmRunAndHandlesYarnAndBun() throws {
    for (lockfile, expected) in [(nil, "npm run dev"), ("yarn.lock", "yarn dev"), ("bun.lockb", "bun run dev")] {
      var files = ["package.json": #"{"scripts": {"dev": "x"}}"#]
      if let lockfile { files[lockfile] = "" }
      let directory = try makeDirectory(files)
      defer { try? FileManager.default.removeItem(at: directory) }

      #expect(CommandDetector.detect(in: directory).map(\.command) == [expected])
    }
  }

  @Test
  func detectsMakefileTargetsIgnoringSpecialLines() throws {
    let directory = try makeDirectory([
      "Makefile": """
      .PHONY: run test
      VERSION := 1.0
      CC = gcc
      run: build
      \tgo run .
      test:
      \tgo test
      %.o: %.c
      \tcc
      .hidden:
      """,
    ])
    defer { try? FileManager.default.removeItem(at: directory) }

    let commands = CommandDetector.detect(in: directory)

    #expect(commands.map(\.command) == ["make run", "make test"])
    #expect(commands.map(\.isLikelyService) == [true, false])
  }

  @Test
  func detectsComposeWithStopCommand() throws {
    let directory = try makeDirectory(["compose.yaml": "services: {}"])
    defer { try? FileManager.default.removeItem(at: directory) }

    let command = try #require(CommandDetector.detect(in: directory).first)

    #expect(command.command == "docker compose up")
    #expect(command.stopCommand == "docker compose down")
    #expect(command.isLikelyService)
  }

  @Test
  func detectsProcfileEntries() throws {
    let directory = try makeDirectory(["Procfile": "web: bundle exec puma\n# comment\nworker: sidekiq\n"])
    defer { try? FileManager.default.removeItem(at: directory) }

    let commands = CommandDetector.detect(in: directory)

    #expect(commands.map(\.name) == ["web", "worker"])
    #expect(commands.map(\.command) == ["bundle exec puma", "sidekiq"])
    #expect(commands.allSatisfy { $0.isLikelyService })
  }

  @Test
  func detectsTaskfileTasks() throws {
    let directory = try makeDirectory([
      "Taskfile.yml": """
      version: '3'
      vars:
        NAME: x
      tasks:
        dev:
          cmds:
            - go run .
        lint:
          cmds: [golangci-lint run]
      """,
    ])
    defer { try? FileManager.default.removeItem(at: directory) }

    let commands = CommandDetector.detect(in: directory)

    #expect(commands.map(\.command) == ["task dev", "task lint"])
    #expect(commands.map(\.isLikelyService) == [true, false])
  }

  @Test
  func detectsGradleSpringBootWithWrapper() throws {
    let directory = try makeDirectory([
      "build.gradle.kts": #"plugins { id("org.springframework.boot") version "3.0.0" }"#,
      "gradlew": "",
    ])
    defer { try? FileManager.default.removeItem(at: directory) }

    let commands = CommandDetector.detect(in: directory)

    #expect(commands.first?.command == "./gradlew bootRun")
    #expect(commands.first?.isLikelyService == true)
    #expect(commands.map(\.command).contains("./gradlew test"))
  }

  @Test
  func detectsMavenSpringBoot() throws {
    let directory = try makeDirectory(["pom.xml": "<artifactId>spring-boot-starter-web</artifactId>"])
    defer { try? FileManager.default.removeItem(at: directory) }

    let commands = CommandDetector.detect(in: directory)

    #expect(commands.first?.command == "mvn spring-boot:run")
    #expect(commands.map(\.command).contains("mvn test"))
  }

  @Test
  func detectsCargoAndGo() throws {
    let directory = try makeDirectory(["Cargo.toml": "", "go.mod": ""])
    defer { try? FileManager.default.removeItem(at: directory) }

    let likely = CommandDetector.detect(in: directory).filter(\.isLikelyService).map(\.command)

    #expect(likely == ["cargo run", "go run ."])
  }

  @Test
  func detectsDjangoAndFastAPIWithRunnerPrefix() throws {
    let directory = try makeDirectory([
      "manage.py": "",
      "main.py": "from fastapi import FastAPI\napp = FastAPI()",
      "uv.lock": "",
    ])
    defer { try? FileManager.default.removeItem(at: directory) }

    let commands = CommandDetector.detect(in: directory).map(\.command)

    #expect(commands == ["uv run python manage.py runserver", "uv run uvicorn main:app --reload"])
  }

  @Test
  func disambiguatesDuplicateNames() throws {
    let directory = try makeDirectory([
      "package.json": #"{"scripts": {"dev": "x"}}"#,
      "Makefile": "dev:\n\tx\n",
    ])
    defer { try? FileManager.default.removeItem(at: directory) }

    #expect(CommandDetector.detect(in: directory).map(\.name) == ["dev", "dev (make)"])
  }

  @Test
  func ignoresInvalidFilesAndEmptyFolders() throws {
    let directory = try makeDirectory(["package.json": "{ not json"])
    defer { try? FileManager.default.removeItem(at: directory) }

    #expect(CommandDetector.detect(in: directory).isEmpty)
  }
}

struct ProjectDraftDetectionTests {
  private let dev = DetectedCommand(name: "dev", command: "npm run dev", source: .packageJSON, isLikelyService: true)
  private let api = DetectedCommand(name: "api", command: "make api", source: .makefile, isLikelyService: true)

  @Test
  func replacesTheSingleEmptyService() {
    var draft = ProjectDraft(directoryURL: URL(fileURLWithPath: "/tmp"))

    draft.applyDetected([dev, api])

    #expect(draft.services.map(\.name) == ["dev", "api"])
    #expect(draft.services.map(\.launchCommand) == ["npm run dev", "make api"])
    #expect(draft.services[0].id == draft.id)
  }

  @Test
  func appendsAndSkipsExistingCommandsAndKeepsNamesUnique() {
    var draft = ProjectDraft(directoryURL: URL(fileURLWithPath: "/tmp"), launchCommand: "npm run dev")
    draft.services[0].name = "api"

    draft.applyDetected([dev, api])

    #expect(draft.services.map(\.launchCommand) == ["npm run dev", "make api"])
    #expect(draft.services.map(\.name) == ["api", "api 2"])
  }

  @Test
  func copiesStopCommand() {
    var draft = ProjectDraft(directoryURL: URL(fileURLWithPath: "/tmp"))
    let compose = DetectedCommand(
      name: "compose", command: "docker compose up", stopCommand: "docker compose down",
      source: .dockerCompose, isLikelyService: true
    )

    draft.applyDetected([compose])

    #expect(draft.services[0].stopCommand == "docker compose down")
  }
}

private func makeDirectory(_ files: [String: String]) throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("StackbarDetect-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
  for (name, contents) in files {
    try contents.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
  }
  return directory
}
