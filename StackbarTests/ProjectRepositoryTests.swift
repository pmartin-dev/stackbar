import Foundation
import Testing
@testable import Stackbar

struct ProjectRepositoryTests {
  @Test
  func savesAndLoadsProjectsWithRestrictedPermissions() async throws {
    let root = try makeRepositoryTestDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let projectFolder = root.appendingPathComponent("Example", isDirectory: true)
    try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: false)
    let fileURL = root.appendingPathComponent("Stackbar/projects.json")
    let repository = ProjectRepository(fileURL: fileURL)
    let project = Project(name: "Example", directoryURL: projectFolder, launchCommand: "run")

    try await repository.save([project])
    let loaded = try await repository.load()
    let fileAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    let directoryAttributes = try FileManager.default.attributesOfItem(
      atPath: fileURL.deletingLastPathComponent().path
    )

    #expect(loaded == [project])
    #expect((fileAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    #expect((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
  }

  @Test
  func preservesUnsupportedConfiguration() async throws {
    let root = try makeRepositoryTestDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let fileURL = root.appendingPathComponent("projects.json")
    let originalData = Data(#"{"schemaVersion":99,"projects":[]}"#.utf8)
    try originalData.write(to: fileURL)
    let repository = ProjectRepository(fileURL: fileURL)

    await #expect(throws: ProjectRepositoryError.self) {
      try await repository.load()
    }
    #expect(try Data(contentsOf: fileURL) == originalData)
  }

  @Test
  func givenV1FileWhenLoadingThenProjectsAreMigrated() async throws {
    let root = try makeRepositoryTestDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let fileURL = root.appendingPathComponent("projects.json")
    let id = UUID()
    try Data(#"{"schemaVersion":1,"projects":[{"id":"\#(id.uuidString)","name":"Web","directoryPath":"/tmp/web","launchCommand":"run"}]}"#.utf8)
      .write(to: fileURL)

    let loaded = try await ProjectRepository(fileURL: fileURL).load()

    #expect(loaded.map(\.id) == [id])
    #expect(loaded.first?.services.map(\.launchCommand) == ["run"])
  }

  @Test
  func doesNotSaveInvalidConfiguration() async throws {
    let root = try makeRepositoryTestDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let fileURL = root.appendingPathComponent("Stackbar/projects.json")
    let repository = ProjectRepository(fileURL: fileURL)
    let missingFolder = root.appendingPathComponent("Missing", isDirectory: true)
    let project = Project(name: "Missing", directoryURL: missingFolder, launchCommand: "run")

    await #expect(throws: ProjectValidationError.self) {
      try await repository.save([project])
    }
    #expect(!FileManager.default.fileExists(atPath: fileURL.path))
  }
}

private func makeRepositoryTestDirectory() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("StackbarRepositoryTests-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
  return directory
}
