import Foundation

enum ProjectRepositoryError: LocalizedError, Equatable, Sendable {
  case unsupportedSchemaVersion(Int)

  var errorDescription: String? {
    switch self {
    case let .unsupportedSchemaVersion(version):
      "Project configuration schema version \(version) is not supported."
    }
  }
}

actor ProjectRepository {
  private let fileURL: URL
  private let fileManager: FileManager

  init(fileURL: URL? = nil, fileManager: FileManager = .default) {
    self.fileURL = fileURL ?? fileManager.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/Stackbar", isDirectory: true)
      .appendingPathComponent("projects.json")
    self.fileManager = fileManager
  }

  func load() throws -> [Project] {
    guard fileManager.fileExists(atPath: fileURL.path) else { return [] }

    let data = try Data(contentsOf: fileURL)
    let document = try JSONDecoder().decode(ProjectsDocument.self, from: data)
    guard ProjectsDocument.supportedSchemaVersions.contains(document.schemaVersion) else {
      throw ProjectRepositoryError.unsupportedSchemaVersion(document.schemaVersion)
    }
    try ProjectValidator.validateAll(
      document.projects,
      fileManager: fileManager,
      requireExistingDirectory: false
    )
    return document.projects
  }

  func save(_ projects: [Project]) throws {
    try ProjectValidator.validateAll(projects, fileManager: fileManager)

    let directoryURL = fileURL.deletingLastPathComponent()
    try fileManager.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    try fileManager.setAttributes(
      [.posixPermissions: 0o700],
      ofItemAtPath: directoryURL.path
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(ProjectsDocument(projects: projects))
    try data.write(to: fileURL, options: .atomic)
    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
  }
}

