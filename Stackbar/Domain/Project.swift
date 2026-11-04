import Foundation

struct Service: Codable, Equatable, Identifiable, Sendable {
  static let defaultName = "main"

  let id: UUID
  var name: String
  var relativeDirectory: String
  var launchCommand: String
  var stopCommand: String?

  init(
    id: UUID = UUID(),
    name: String,
    relativeDirectory: String = "",
    launchCommand: String,
    stopCommand: String? = nil
  ) {
    self.id = id
    self.name = name
    self.relativeDirectory = relativeDirectory
    self.launchCommand = launchCommand
    self.stopCommand = stopCommand
  }
}

/// What the process manager needs to run one service.
struct ServiceLaunch: Equatable, Sendable {
  var id: UUID
  var directoryPath: String
  var launchCommand: String
  var stopCommand: String?

  var directoryURL: URL {
    URL(fileURLWithPath: directoryPath, isDirectory: true)
  }
}

struct Project: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  var name: String
  var directoryPath: String
  var services: [Service]
  /// Runs once after every service of the project has been stopped.
  var stopCommand: String?

  init(
    id: UUID = UUID(),
    name: String,
    directoryPath: String,
    services: [Service],
    stopCommand: String? = nil
  ) {
    self.id = id
    self.name = name
    self.directoryPath = URL(fileURLWithPath: directoryPath).standardizedFileURL.path
    self.services = services
    self.stopCommand = stopCommand
  }

  /// Single-service project; the service shares the project identifier.
  init(
    id: UUID = UUID(),
    name: String,
    directoryPath: String,
    launchCommand: String,
    stopCommand: String? = nil
  ) {
    self.init(
      id: id,
      name: name,
      directoryPath: directoryPath,
      services: [Service(id: id, name: Service.defaultName, launchCommand: launchCommand, stopCommand: stopCommand)]
    )
  }

  init(
    id: UUID = UUID(),
    name: String,
    directoryURL: URL,
    launchCommand: String,
    stopCommand: String? = nil
  ) {
    self.init(
      id: id,
      name: name,
      directoryPath: directoryURL.standardizedFileURL.path,
      launchCommand: launchCommand,
      stopCommand: stopCommand
    )
  }

  private enum CodingKeys: String, CodingKey {
    case id, name, directoryPath, services, stopCommand
  }

  private enum LegacyCodingKeys: String, CodingKey {
    case launchCommand
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let id = try container.decode(UUID.self, forKey: .id)
    let name = try container.decode(String.self, forKey: .name)
    let directoryPath = try container.decode(String.self, forKey: .directoryPath)
    let stopCommand = try container.decodeIfPresent(String.self, forKey: .stopCommand)
    if let services = try container.decodeIfPresent([Service].self, forKey: .services) {
      self.init(id: id, name: name, directoryPath: directoryPath, services: services, stopCommand: stopCommand)
    } else {
      let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
      self.init(
        id: id,
        name: name,
        directoryPath: directoryPath,
        launchCommand: try legacy.decode(String.self, forKey: .launchCommand),
        stopCommand: stopCommand
      )
    }
  }

  var directoryURL: URL {
    URL(fileURLWithPath: directoryPath, isDirectory: true)
  }

  var canonicalDirectoryPath: String {
    directoryURL.standardizedFileURL.resolvingSymlinksInPath().path
  }

  var hasMultipleServices: Bool {
    services.count > 1
  }

  func directoryURL(for service: Service) -> URL {
    let relative = service.relativeDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !relative.isEmpty else { return directoryURL }
    return directoryURL.appendingPathComponent(relative, isDirectory: true).standardizedFileURL
  }

  func launch(for serviceID: UUID) -> ServiceLaunch? {
    guard let service = services.first(where: { $0.id == serviceID }) else { return nil }
    return ServiceLaunch(
      id: service.id,
      directoryPath: directoryURL(for: service).path,
      launchCommand: service.launchCommand,
      stopCommand: service.stopCommand
    )
  }

  static func suggestedName(for directoryURL: URL) -> String {
    let name = directoryURL.lastPathComponent
    return name.isEmpty ? directoryURL.path : name
  }
}

enum ProjectValidationError: LocalizedError, Equatable, Sendable {
  case emptyName
  case noDirectorySelected
  case invalidDirectory(String)
  case noServices
  case emptyServiceName
  case duplicateServiceName(String)
  case emptyLaunchCommand(String)
  case duplicateDirectory(String)
  case duplicateIdentifier(UUID)

  var errorDescription: String? {
    switch self {
    case .emptyName:
      "Project name cannot be empty."
    case .noDirectorySelected:
      "Choose a project folder."
    case let .invalidDirectory(path):
      "The folder does not exist or is not a directory: \(path)"
    case .noServices:
      "Add at least one service."
    case .emptyServiceName:
      "Service name cannot be empty."
    case let .duplicateServiceName(name):
      "Another service is already named \(name)."
    case let .emptyLaunchCommand(service):
      service == Service.defaultName
        ? "Launch command cannot be empty."
        : "Launch command of \(service) cannot be empty."
    case let .duplicateDirectory(path):
      "Another project already uses this folder: \(path)"
    case let .duplicateIdentifier(id):
      "More than one project or service uses identifier \(id)."
    }
  }
}

enum ProjectValidator {
  static func validateAll(
    _ projects: [Project],
    fileManager: FileManager = .default,
    requireExistingDirectory: Bool = true
  ) throws {
    var identifiers = Set<UUID>()
    for project in projects {
      guard identifiers.insert(project.id).inserted else {
        throw ProjectValidationError.duplicateIdentifier(project.id)
      }
      for service in project.services where service.id != project.id {
        guard identifiers.insert(service.id).inserted else {
          throw ProjectValidationError.duplicateIdentifier(service.id)
        }
      }
      try validate(
        project,
        alongside: projects.filter { $0.id != project.id },
        fileManager: fileManager,
        requireExistingDirectory: requireExistingDirectory
      )
    }
  }

  static func validate(
    _ project: Project,
    alongside projects: [Project],
    fileManager: FileManager = .default,
    requireExistingDirectory: Bool = true
  ) throws {
    guard !project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ProjectValidationError.emptyName
    }
    guard !project.services.isEmpty else {
      throw ProjectValidationError.noServices
    }
    var serviceNames = Set<String>()
    var serviceIDs = Set<UUID>()
    for service in project.services {
      let name = service.name.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !name.isEmpty else { throw ProjectValidationError.emptyServiceName }
      guard serviceNames.insert(name).inserted else {
        throw ProjectValidationError.duplicateServiceName(name)
      }
      guard serviceIDs.insert(service.id).inserted else {
        throw ProjectValidationError.duplicateIdentifier(service.id)
      }
      guard !service.launchCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw ProjectValidationError.emptyLaunchCommand(name)
      }
    }
    if requireExistingDirectory {
      try requireDirectory(project.directoryPath, fileManager: fileManager)
      for service in project.services {
        try requireDirectory(project.directoryURL(for: service).path, fileManager: fileManager)
      }
    }
    guard !projects.contains(where: {
      $0.id != project.id && $0.canonicalDirectoryPath == project.canonicalDirectoryPath
    }) else {
      throw ProjectValidationError.duplicateDirectory(project.canonicalDirectoryPath)
    }
  }

  private static func requireDirectory(_ path: String, fileManager: FileManager) throws {
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
      throw ProjectValidationError.invalidDirectory(path)
    }
  }
}
