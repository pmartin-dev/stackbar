import Foundation
import Testing
@testable import Stackbar

struct ProjectTests {
  @Test
  func defaultsNameToFolderName() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    #expect(Project.suggestedName(for: directory) == directory.lastPathComponent)
  }

  @Test
  func rejectsEmptyNameAndCommand() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let project = Project(name: " ", directoryURL: directory, launchCommand: "\n")

    #expect(throws: ProjectValidationError.self) {
      try ProjectValidator.validate(project, alongside: [])
    }
  }

  @Test
  func rejectsMissingDirectory() {
    let missingDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let project = Project(name: "Missing", directoryURL: missingDirectory, launchCommand: "run")

    #expect(throws: ProjectValidationError.self) {
      try ProjectValidator.validate(project, alongside: [])
    }
  }

  @Test
  func rejectsDuplicateCanonicalDirectory() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let alias = directory.deletingLastPathComponent()
      .appendingPathComponent("StackbarTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: directory)
    defer { try? FileManager.default.removeItem(at: alias) }

    let existing = Project(name: "First", directoryURL: directory, launchCommand: "run")
    let duplicate = Project(name: "Second", directoryURL: alias, launchCommand: "run")

    #expect(throws: ProjectValidationError.self) {
      try ProjectValidator.validate(duplicate, alongside: [existing])
    }
  }

  @Test
  func encodesDocumentWithCurrentSchema() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let project = Project(name: "Example", directoryURL: directory, launchCommand: "run")
    let data = try JSONEncoder().encode(ProjectsDocument(projects: [project]))
    let decoded = try JSONDecoder().decode(ProjectsDocument.self, from: data)

    #expect(decoded.schemaVersion == ProjectsDocument.currentSchemaVersion)
    #expect(decoded.projects == [project])
  }
}

struct ProjectDraftTests {
  @Test
  func givenNoFolderWhenValidatingThenItIsRejected() {
    let draft = ProjectDraft(name: "Web", launchCommand: "npm run dev")

    #expect(throws: ProjectValidationError.noDirectorySelected) {
      try draft.validated(alongside: [])
    }
  }

  @Test
  func givenCompleteDraftWhenValidatingThenItBuildsTrimmedProject() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let id = UUID()
    let draft = ProjectDraft(
      id: id,
      name: "  Web ",
      directoryURL: directory,
      launchCommand: "npm run dev",
      stopCommand: "  \n"
    )

    let project = try draft.validated(alongside: [])

    #expect(project == Project(id: id, name: "Web", directoryURL: directory, launchCommand: "npm run dev"))
  }

  @Test
  func givenFolderUsedByAnotherProjectWhenValidatingThenItIsRejected() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let existing = Project(name: "First", directoryURL: directory, launchCommand: "run")
    let draft = ProjectDraft(name: "Second", directoryURL: directory, launchCommand: "run")

    #expect(throws: ProjectValidationError.self) {
      try draft.validated(alongside: [existing])
    }
  }

  @Test
  func givenSavedProjectWhenDraftingThenRoundTripsUnchanged() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let project = Project(name: "Web", directoryURL: directory, launchCommand: "run", stopCommand: "stop")

    #expect(try ProjectDraft(project: project).validated(alongside: [project]) == project)
  }

  @Test
  func givenFolderWhenChoosingItOnUnnamedDraftThenNameIsSuggested() {
    var draft = ProjectDraft()
    draft.chooseDirectory(URL(fileURLWithPath: "/tmp/my-app"))

    #expect(draft.name == "my-app")

    draft.name = "Custom"
    draft.chooseDirectory(URL(fileURLWithPath: "/tmp/other"))
    #expect(draft.name == "Custom")
  }
}

struct ProjectServicesTests {
  @Test
  func givenLegacyV1ProjectWhenDecodingThenItBecomesSingleServiceWithSameIdentifier() throws {
    let id = UUID()
    let json = """
    {"schemaVersion":1,"projects":[{"id":"\(id.uuidString)","name":"Web","directoryPath":"/tmp/web","launchCommand":"npm run dev","stopCommand":"docker compose down"}]}
    """

    let document = try JSONDecoder().decode(ProjectsDocument.self, from: Data(json.utf8))
    let project = try #require(document.projects.first)

    #expect(project.services == [Service(id: id, name: "main", launchCommand: "npm run dev", stopCommand: "docker compose down")])
    #expect(project.stopCommand == nil)
  }

  @Test
  func givenMultiServiceProjectWhenEncodingThenItRoundTripsAsCurrentSchema() throws {
    let project = Project(
      name: "Shop",
      directoryPath: "/tmp/shop",
      services: [
        Service(name: "api", relativeDirectory: "api", launchCommand: "make run"),
        Service(name: "web", relativeDirectory: "web", launchCommand: "npm run dev", stopCommand: "pkill node"),
      ],
      stopCommand: "docker compose down"
    )

    let data = try JSONEncoder().encode(ProjectsDocument(projects: [project]))
    let decoded = try JSONDecoder().decode(ProjectsDocument.self, from: data)

    #expect(decoded.schemaVersion == 2)
    #expect(decoded.projects == [project])
  }

  @Test
  func givenServiceSubdirectoryWhenResolvingLaunchThenItUsesProjectRelativeFolder() throws {
    let api = Service(name: "api", relativeDirectory: "backend/api", launchCommand: "make run", stopCommand: "make stop")
    let project = Project(name: "Shop", directoryPath: "/tmp/shop", services: [api])

    let launch = try #require(project.launch(for: api.id))

    #expect(launch == ServiceLaunch(id: api.id, directoryPath: "/tmp/shop/backend/api", launchCommand: "make run", stopCommand: "make stop"))
  }

  @Test
  func givenNoServicesWhenValidatingThenItIsRejected() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let project = Project(name: "Empty", directoryPath: directory.path, services: [])

    #expect(throws: ProjectValidationError.noServices) {
      try ProjectValidator.validate(project, alongside: [])
    }
  }

  @Test
  func givenDuplicateServiceNamesWhenValidatingThenItIsRejected() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let project = Project(name: "Shop", directoryPath: directory.path, services: [
      Service(name: "web", launchCommand: "a"),
      Service(name: " web ", launchCommand: "b"),
    ])

    #expect(throws: ProjectValidationError.duplicateServiceName("web")) {
      try ProjectValidator.validate(project, alongside: [])
    }
  }

  @Test
  func givenServiceWithoutNameOrCommandWhenValidatingThenItIsRejected() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let unnamed = Project(name: "Shop", directoryPath: directory.path, services: [
      Service(name: "web", launchCommand: "a"), Service(name: " ", launchCommand: "b"),
    ])
    let noCommand = Project(name: "Shop", directoryPath: directory.path, services: [
      Service(name: "web", launchCommand: "a"), Service(name: "api", launchCommand: " "),
    ])

    #expect(throws: ProjectValidationError.emptyServiceName) {
      try ProjectValidator.validate(unnamed, alongside: [])
    }
    #expect(throws: ProjectValidationError.emptyLaunchCommand("api")) {
      try ProjectValidator.validate(noCommand, alongside: [])
    }
  }

  @Test
  func givenMissingServiceSubdirectoryWhenValidatingThenItIsRejected() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let project = Project(name: "Shop", directoryPath: directory.path, services: [
      Service(name: "api", relativeDirectory: "missing", launchCommand: "run"),
    ])

    #expect(throws: ProjectValidationError.invalidDirectory(directory.appendingPathComponent("missing").path)) {
      try ProjectValidator.validate(project, alongside: [])
    }
  }

  @Test
  func givenServiceIdentifierSharedAcrossProjectsWhenValidatingAllThenItIsRejected() throws {
    let shared = Service(name: "web", launchCommand: "run")
    let first = Project(name: "A", directoryPath: "/tmp/a", services: [shared])
    let second = Project(name: "B", directoryPath: "/tmp/b", services: [shared])

    #expect(throws: ProjectValidationError.duplicateIdentifier(shared.id)) {
      try ProjectValidator.validateAll([first, second], requireExistingDirectory: false)
    }
  }
}

struct ProjectStatusSummaryTests {
  @Test
  func givenAllServicesRunningThenProjectIsRunning() {
    let summary = ProjectStatusSummary([running(), running()])

    #expect(summary.status == .running)
    #expect(summary.isActive)
    #expect(summary.runningCount == 2)
  }

  @Test
  func givenSomeServicesRunningThenProjectIsPartial() {
    let summary = ProjectStatusSummary([running(), ProjectRuntime()])

    #expect(summary.status == .partial)
    #expect(summary.isActive)
  }

  @Test
  func givenAnyTransitionThenTransitionWins() {
    #expect(ProjectStatusSummary([running(), ProjectRuntime(status: .starting)]).status == .starting)
    #expect(ProjectStatusSummary([running(), ProjectRuntime(status: .stopping)]).status == .stopping)
  }

  @Test
  func givenAFailedServiceThenErrorIsReportedEvenWhileOthersRun() {
    let summary = ProjectStatusSummary([running(), ProjectRuntime(status: .exited(.error("boom")), lastError: "boom")])

    #expect(summary.status == .partial)
    #expect(summary.errorMessage == "boom")
  }

  @Test
  func givenNothingActiveThenProjectIsStoppedOrFailed() {
    #expect(ProjectStatusSummary([ProjectRuntime(), ProjectRuntime(status: .exited(.normal))]).status == .stopped)
    #expect(ProjectStatusSummary([ProjectRuntime(status: .exited(.error("x")))]).status == .failed)
  }

  private func running() -> ProjectRuntime {
    ProjectRuntime(status: .running(processIdentifier: 1))
  }
}

struct ProjectDraftServicesTests {
  @Test
  func givenNewDraftThenItHasOneService() {
    #expect(ProjectDraft().services.count == 1)
  }

  @Test
  func givenSingleServiceWhenRemovingThenLastServiceIsKept() {
    var draft = ProjectDraft()
    draft.removeService(draft.services[0].id)

    #expect(draft.services.count == 1)
  }

  @Test
  func givenSeveralServicesWhenValidatingThenItBuildsTrimmedServicesAndProjectStop() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory.appendingPathComponent("web"), withIntermediateDirectories: false)
    var draft = ProjectDraft(name: "Shop", directoryURL: directory, launchCommand: "make run")
    draft.services[0].name = " api "
    draft.addService()
    draft.services[1].name = "web"
    draft.services[1].relativeDirectory = " web "
    draft.services[1].launchCommand = "npm run dev"
    draft.services[1].stopCommand = " "
    draft.stopCommand = " docker compose down "

    let project = try draft.validated(alongside: [])

    #expect(project.services.map(\.name) == ["api", "web"])
    #expect(project.services[1].relativeDirectory == "web")
    #expect(project.services[1].stopCommand == nil)
    #expect(project.stopCommand == "docker compose down")
  }

  @Test
  func givenSingleUnnamedServiceWhenValidatingThenItIsNamedMain() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    var draft = ProjectDraft(name: "Web", directoryURL: directory, launchCommand: "run")
    draft.services[0].name = ""

    #expect(try draft.validated(alongside: []).services[0].name == "main")
  }
}

private func makeTemporaryDirectory() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("StackbarTests-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
  return directory
}
