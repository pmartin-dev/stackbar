import Foundation

struct ProjectsDocument: Codable, Equatable, Sendable {
  static let currentSchemaVersion = 2
  /// Versions that can still be decoded; older projects are migrated by `Project.init(from:)`.
  static let supportedSchemaVersions: ClosedRange<Int> = 1...currentSchemaVersion

  var schemaVersion: Int
  var projects: [Project]

  init(projects: [Project]) {
    self.schemaVersion = Self.currentSchemaVersion
    self.projects = projects
  }
}
