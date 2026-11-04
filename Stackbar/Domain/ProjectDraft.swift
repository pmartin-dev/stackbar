import Foundation

struct ServiceDraft: Equatable, Identifiable, Sendable {
  let id: UUID
  var name: String
  var relativeDirectory: String
  var launchCommand: String
  var stopCommand: String
  var port: String

  init(
    id: UUID = UUID(),
    name: String = "",
    relativeDirectory: String = "",
    launchCommand: String = "",
    stopCommand: String = "",
    port: String = ""
  ) {
    self.id = id
    self.name = name
    self.relativeDirectory = relativeDirectory
    self.launchCommand = launchCommand
    self.stopCommand = stopCommand
    self.port = port
  }

  init(service: Service) {
    self.init(
      id: service.id,
      name: service.name,
      relativeDirectory: service.relativeDirectory,
      launchCommand: service.launchCommand,
      stopCommand: service.stopCommand ?? "",
      port: service.port.map(String.init) ?? ""
    )
  }
}

struct ProjectDraft: Equatable, Identifiable, Sendable {
  let id: UUID
  var name: String
  var directoryURL: URL?
  var services: [ServiceDraft]
  var stopCommand: String

  /// Creates a draft with a single service using `launchCommand`.
  init(
    id: UUID = UUID(),
    name: String = "",
    directoryURL: URL? = nil,
    launchCommand: String = "",
    stopCommand: String = ""
  ) {
    self.id = id
    self.name = name
    self.directoryURL = directoryURL
    self.services = [ServiceDraft(id: id, name: Service.defaultName, launchCommand: launchCommand, stopCommand: stopCommand)]
    self.stopCommand = ""
  }

  init(project: Project) {
    id = project.id
    name = project.name
    directoryURL = project.directoryURL
    services = project.services.map(ServiceDraft.init(service:))
    stopCommand = project.stopCommand ?? ""
  }

  mutating func chooseDirectory(_ url: URL) {
    directoryURL = url
    if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      name = Project.suggestedName(for: url)
    }
  }

  mutating func addService() {
    services.append(ServiceDraft())
  }

  mutating func removeService(_ serviceID: UUID) {
    guard services.count > 1 else { return }
    services.removeAll { $0.id == serviceID }
  }

  /// Turns detected commands into services, replacing a lone empty service and skipping known commands.
  mutating func applyDetected(_ commands: [DetectedCommand]) {
    let replacesEmpty = services.count == 1 && services[0].launchCommand.trimmed.isEmpty
    var result = replacesEmpty ? [] : services
    var reusableID = replacesEmpty ? services.first?.id : nil
    for command in commands where !result.contains(where: { $0.launchCommand.trimmed == command.command }) {
      var name = command.name
      var index = 2
      while result.contains(where: { $0.name.trimmed == name }) {
        name = "\(command.name) \(index)"
        index += 1
      }
      result.append(ServiceDraft(
        id: reusableID ?? UUID(),
        name: name,
        launchCommand: command.command,
        stopCommand: command.stopCommand ?? ""
      ))
      reusableID = nil
    }
    guard !result.isEmpty else { return }
    services = result
  }

  func validated(alongside projects: [Project], fileManager: FileManager = .default) throws -> Project {
    guard let directoryURL else { throw ProjectValidationError.noDirectorySelected }
    let builtServices = try services.map { draft in
      let trimmedName = draft.name.trimmed
      let name = trimmedName.isEmpty && services.count == 1 ? Service.defaultName : trimmedName
      var port: Int?
      if !draft.port.trimmed.isEmpty {
        guard let value = Int(draft.port.trimmed), (1...65_535).contains(value) else {
          throw ProjectValidationError.invalidPort(name)
        }
        port = value
      }
      return Service(
        id: draft.id,
        name: name,
        relativeDirectory: draft.relativeDirectory.trimmed,
        launchCommand: draft.launchCommand.trimmed,
        stopCommand: draft.stopCommand.trimmed.nilIfEmpty,
        port: port
      )
    }
    let project = Project(
      id: id,
      name: name.trimmed,
      directoryPath: directoryURL.standardizedFileURL.path,
      services: builtServices,
      stopCommand: stopCommand.trimmed.nilIfEmpty
    )
    try ProjectValidator.validate(project, alongside: projects, fileManager: fileManager)
    return project
  }
}

private extension String {
  var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
  var nilIfEmpty: String? { isEmpty ? nil : self }
}
