import ComposableArchitecture
import Foundation
import Testing
@testable import Stackbar

@MainActor
struct ProjectsFeatureTests {
  @Test
  func confirmsDeletionOfRunningProjectAndStopsItBeforeSaving() async throws {
    let project = makeProject()
    let repository = ProjectsRepositoryStub(projects: [project])
    let process = ProjectsProcessStub()
    let store = makeStore(project: project, repository: repository, process: process)

    await store.send(.deleteTapped(project.id)) {
      $0.pendingDeleteID = project.id
    }
    await store.send(.confirmDelete) {
      $0.pendingDeleteID = nil
    }
    await store.receive(.deleteSucceeded(project.id, [])) {
      $0.projects = []
      $0.runtimes[project.id] = nil
      $0.errorMessage = nil
    }
    await store.receive(.delegate(.projectDeleted(project.id)))

    #expect(await process.stopCount == 1)
    #expect(await repository.savedProjects == [])
  }

  @Test
  func keepsProjectWhenStoppingBeforeDeletionFails() async throws {
    let project = makeProject()
    let repository = ProjectsRepositoryStub(projects: [project])
    let process = ProjectsProcessStub(shouldFailStop: true)
    let store = makeStore(project: project, repository: repository, process: process)
    let message = ProjectProcessManagerError.processDidNotStop.localizedDescription

    await store.send(.deleteTapped(project.id)) {
      $0.pendingDeleteID = project.id
    }
    await store.send(.confirmDelete) {
      $0.pendingDeleteID = nil
    }
    await store.receive(.deleteFailed(project.id, message)) {
      $0.errorMessage = message
    }

    #expect(store.state.projects == [project])
    #expect(await repository.saveCount == 0)
  }

  @Test
  func revalidatesProjectFolderWhenLaunching() async throws {
    let path = "/tmp/Stackbar-ProjectFeatureTests-\(UUID().uuidString)"
    let project = Project(name: "Missing", directoryPath: path, launchCommand: "run")
    let store = makeStore(
      project: project,
      repository: ProjectsRepositoryStub(projects: [project]),
      process: ProjectsProcessStub(),
      runtime: ProjectRuntime()
    )
    let message = ProjectValidationError.invalidDirectory(path).localizedDescription

    await store.send(.launchTapped(project.id)) {
      $0.errorMessage = message
    }

    #expect(store.state.runtimes[project.id]?.status == .stopped)
  }
}

@MainActor
struct ProjectsFeatureServicesTests {
  @Test
  func givenProjectWithServicesWhenLaunchingThenEveryServiceStarts() async {
    let project = makeMultiServiceProject()
    let recorder = CommandRecorder()
    let store = makeServicesStore(project: project, recorder: recorder)
    store.exhaustivity = .off

    await store.send(.launchTapped(project.id))
    await store.skipReceivedActions()

    #expect(Set(await recorder.started) == Set(project.services.map(\.id)))
    #expect(project.services.allSatisfy { store.state.runtimes[$0.id]?.status == .running(processIdentifier: 42) })
  }

  @Test
  func givenRunningProjectWhenStoppingThenServicesStopBeforeProjectStopCommand() async {
    let project = makeMultiServiceProject()
    let recorder = CommandRecorder()
    let store = makeServicesStore(project: project, recorder: recorder, running: true)
    store.exhaustivity = .off

    await store.send(.stopTapped(project.id)) {
      for service in project.services {
        $0.runtimes[service.id]?.status = .stopping
      }
    }
    await store.finish()

    let log = await recorder.log
    #expect(Set(log.prefix(2)) == Set(project.services.map { "stop \($0.id)" }))
    #expect(log.last == "run docker compose down in \(project.directoryPath)")
  }

  @Test
  func givenRunningProjectWhenStoppingOneServiceThenOnlyItStops() async {
    let project = makeMultiServiceProject()
    let recorder = CommandRecorder()
    let store = makeServicesStore(project: project, recorder: recorder, running: true)
    store.exhaustivity = .off
    let api = project.services[0]

    await store.send(.stopServiceTapped(api.id)) {
      $0.runtimes[api.id]?.status = .stopping
    }
    await store.finish()

    await store.send(.processEvent(.finished(serviceID: api.id, exit: .normal)))

    #expect(await recorder.log == ["stop \(api.id)"])
    #expect(store.state.summary(for: project).status == .partial)
  }
}

@MainActor
private func makeServicesStore(
  project: Project,
  recorder: CommandRecorder,
  running: Bool = false
) -> TestStore<ProjectsFeature.State, ProjectsFeature.Action> {
  let runtime = running ? ProjectRuntime(status: .running(processIdentifier: 1)) : ProjectRuntime()
  return TestStore(
    initialState: ProjectsFeature.State(
      projects: [project],
      runtimes: Dictionary(uniqueKeysWithValues: project.services.map { ($0.id, runtime) })
    )
  ) {
    ProjectsFeature()
  } withDependencies: {
    $0.projectRepositoryClient = ProjectRepositoryClient(load: { [project] }, save: { _ in })
    $0.projectProcessClient = ProjectProcessClient(
      events: { AsyncStream { $0.finish() } },
      start: { await recorder.start($0.id) },
      stop: { await recorder.record("stop \($0)") },
      restart: { _ in 43 },
      runCommand: { await recorder.record("run \($0) in \($1)") },
      activeServiceIDs: { [] },
      stopAll: { [] },
      removeLogs: { _ in }
    )
    $0.workspaceClient = WorkspaceClient(open: { _ in true })
  }
}

private func makeMultiServiceProject() -> Project {
  let directory = FileManager.default.temporaryDirectory.path
  return Project(
    name: "Shop",
    directoryPath: directory,
    services: [
      Service(name: "api", launchCommand: "make run"),
      Service(name: "web", launchCommand: "npm run dev"),
    ],
    stopCommand: "docker compose down"
  )
}

private actor CommandRecorder {
  private(set) var log: [String] = []
  private(set) var started: [UUID] = []

  func record(_ entry: String) {
    log.append(entry)
  }

  func start(_ serviceID: UUID) -> Int32 {
    started.append(serviceID)
    return 42
  }
}

@MainActor
private func makeStore(
  project: Project,
  repository: ProjectsRepositoryStub,
  process: ProjectsProcessStub,
  runtime: ProjectRuntime = ProjectRuntime(status: .running(processIdentifier: 123))
) -> TestStore<ProjectsFeature.State, ProjectsFeature.Action> {
  TestStore(
    initialState: ProjectsFeature.State(
      projects: [project],
      runtimes: [project.id: runtime]
    )
  ) {
    ProjectsFeature()
  } withDependencies: {
    $0.projectRepositoryClient = ProjectRepositoryClient(
      load: { await repository.load() },
      save: { await repository.save($0) }
    )
    $0.projectProcessClient = ProjectProcessClient(
      events: { AsyncStream { $0.finish() } },
      start: { _ in 123 },
      stop: { try await process.stop($0) },
      restart: { _ in 124 },
      runCommand: { _, _ in },
      activeServiceIDs: { [] },
      stopAll: { [] },
      removeLogs: { _ in }
    )
    $0.workspaceClient = WorkspaceClient(open: { _ in true })
  }
}

private func makeProject() -> Project {
  Project(
    name: "Example",
    directoryPath: "/tmp/Stackbar-ProjectFeatureTests",
    launchCommand: "run"
  )
}

private actor ProjectsRepositoryStub {
  private(set) var savedProjects: [Project]
  private(set) var saveCount = 0

  init(projects: [Project]) {
    savedProjects = projects
  }

  func load() -> [Project] {
    savedProjects
  }

  func save(_ projects: [Project]) {
    savedProjects = projects
    saveCount += 1
  }
}

private actor ProjectsProcessStub {
  private(set) var stopCount = 0
  private let shouldFailStop: Bool

  init(shouldFailStop: Bool = false) {
    self.shouldFailStop = shouldFailStop
  }

  func stop(_ projectID: UUID) throws {
    stopCount += 1
    if shouldFailStop {
      throw ProjectProcessManagerError.processDidNotStop
    }
  }
}
