import ComposableArchitecture
import Foundation

@Reducer
struct ProjectsFeature {
  @ObservableState
  struct State: Equatable {
    var projects: [Project] = []
    /// Runtimes keyed by service identifier.
    var runtimes: [UUID: ProjectRuntime] = [:]
    var pendingDeleteID: UUID?
    var errorMessage: String?
    var lastSavedProjectID: UUID?

    func summary(for project: Project) -> ProjectStatusSummary {
      ProjectStatusSummary(project.services.map { runtimes[$0.id] ?? ProjectRuntime() })
    }

    func project(containingService serviceID: UUID) -> Project? {
      projects.first { $0.services.contains { $0.id == serviceID } }
    }

    fileprivate func activeServiceIDs(of project: Project) -> [UUID] {
      project.services.map(\.id).filter { runtimes[$0]?.status.isActive == true }
    }
  }

  enum Action: Equatable {
    case task
    case projectsLoaded([Project])
    case loadFailed(String)
    case launchTapped(UUID)
    case stopTapped(UUID)
    case restartTapped(UUID)
    case launchServiceTapped(UUID)
    case stopServiceTapped(UUID)
    case restartServiceTapped(UUID)
    case startSucceeded(UUID, Int32)
    case startFailed(UUID, String)
    case stopFailed(UUID, String, processStopped: Bool)
    case restartFailed(UUID, String, processStopped: Bool)
    case projectStopCommandFailed(UUID, String)
    case deleteTapped(UUID)
    case confirmDelete
    case cancelDelete
    case deleteSucceeded(UUID, [Project])
    case deleteFailed(UUID, String)
    case saveProject(Project)
    case projectSaved(Project, [Project])
    case saveFailed(String)
    case openFolder(UUID)
    case openURL(UUID)
    case openFailed(String)
    case processEvent(ProjectProcessEvent)
    case delegate(Delegate)
  }

  enum Delegate: Equatable, Sendable {
    case launchRequested(UUID)
    case projectDeleted(UUID)
  }

  @Dependency(\.projectRepositoryClient) private var repository
  @Dependency(\.projectProcessClient) private var processClient
  @Dependency(\.workspaceClient) private var workspace

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .task:
        return .run { [repository] send in
          do {
            await send(.projectsLoaded(try await repository.load()))
          } catch {
            await send(.loadFailed(error.localizedDescription))
          }
        }

      case let .projectsLoaded(projects):
        state.projects = projects
        state.runtimes = Dictionary(
          uniqueKeysWithValues: projects.flatMap(\.services).map {
            ($0.id, state.runtimes[$0.id] ?? ProjectRuntime())
          }
        )
        return .none

      case let .loadFailed(message):
        state.errorMessage = message
        return .none

      case let .launchTapped(projectID):
        guard let project = state.projects.first(where: { $0.id == projectID }) else { return .none }
        return launch(project.services.map(\.id), of: project, state: &state)

      case let .launchServiceTapped(serviceID):
        guard let project = state.project(containingService: serviceID) else { return .none }
        return launch([serviceID], of: project, state: &state)

      case let .stopTapped(projectID):
        guard let project = state.projects.first(where: { $0.id == projectID }) else { return .none }
        let serviceIDs = state.activeServiceIDs(of: project)
        guard !serviceIDs.isEmpty else { return .none }
        markStopping(serviceIDs, state: &state)
        return stopEffect(serviceIDs: serviceIDs, thenRunStopCommandOf: project)

      case let .stopServiceTapped(serviceID):
        guard state.runtimes[serviceID]?.status.isActive == true else { return .none }
        markStopping([serviceID], state: &state)
        return stopEffect(serviceIDs: [serviceID], thenRunStopCommandOf: nil)

      case let .restartTapped(projectID):
        guard let project = state.projects.first(where: { $0.id == projectID }) else { return .none }
        let launches = state.activeServiceIDs(of: project).compactMap { project.launch(for: $0) }
        return .merge(launches.map(restartEffect))

      case let .restartServiceTapped(serviceID):
        guard
          state.runtimes[serviceID]?.status.isActive == true,
          let launch = state.project(containingService: serviceID)?.launch(for: serviceID)
        else {
          return .none
        }
        return restartEffect(launch)

      case let .startSucceeded(serviceID, processIdentifier):
        var runtime = state.runtimes[serviceID] ?? ProjectRuntime()
        runtime.status = .running(processIdentifier: processIdentifier)
        runtime.lastError = nil
        state.runtimes[serviceID] = runtime
        return .none

      case let .startFailed(serviceID, message):
        var runtime = state.runtimes[serviceID] ?? ProjectRuntime()
        runtime.status = .exited(.error(message))
        runtime.lastError = message
        state.runtimes[serviceID] = runtime
        state.errorMessage = message
        return .none

      case let .stopFailed(serviceID, message, processStopped),
           let .restartFailed(serviceID, message, processStopped):
        var runtime = state.runtimes[serviceID] ?? ProjectRuntime()
        if processStopped {
          runtime.status = .exited(.error(message))
        }
        runtime.lastError = message
        state.runtimes[serviceID] = runtime
        state.errorMessage = message
        return .none

      case let .projectStopCommandFailed(projectID, message):
        let name = state.projects.first(where: { $0.id == projectID })?.name ?? "Project"
        state.errorMessage = "\(name): project stop command failed. \(message)"
        return .none

      case let .deleteTapped(projectID):
        guard let project = state.projects.first(where: { $0.id == projectID }) else { return .none }
        if !state.activeServiceIDs(of: project).isEmpty {
          state.pendingDeleteID = projectID
          return .none
        }
        return deleteEffect(project: project, stopping: [], projects: state.projects)

      case .confirmDelete:
        guard
          let projectID = state.pendingDeleteID,
          let project = state.projects.first(where: { $0.id == projectID })
        else {
          state.pendingDeleteID = nil
          return .none
        }
        state.pendingDeleteID = nil
        return deleteEffect(
          project: project,
          stopping: state.activeServiceIDs(of: project),
          projects: state.projects
        )

      case .cancelDelete:
        state.pendingDeleteID = nil
        return .none

      case let .deleteSucceeded(projectID, projects):
        let removedServiceIDs = state.projects.first(where: { $0.id == projectID })?.services.map(\.id) ?? [projectID]
        state.projects = projects
        for serviceID in removedServiceIDs {
          state.runtimes[serviceID] = nil
        }
        state.errorMessage = nil
        return .send(.delegate(.projectDeleted(projectID)))

      case let .deleteFailed(_, message):
        state.errorMessage = message
        return .none

      case let .saveProject(project):
        do {
          try ProjectValidator.validate(project, alongside: state.projects)
        } catch {
          state.errorMessage = error.localizedDescription
          return .none
        }
        var projects = state.projects
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
          projects[index] = project
        } else {
          projects.append(project)
        }
        state.errorMessage = nil
        state.lastSavedProjectID = nil
        let updatedProjects = projects
        return .run { [repository] send in
          do {
            try await repository.save(updatedProjects)
            await send(.projectSaved(project, updatedProjects))
          } catch {
            await send(.saveFailed(error.localizedDescription))
          }
        }

      case let .projectSaved(project, projects):
        let previousServiceIDs = state.projects.first(where: { $0.id == project.id })?.services.map(\.id) ?? []
        let currentServiceIDs = Set(project.services.map(\.id))
        let removedServiceIDs = previousServiceIDs.filter { !currentServiceIDs.contains($0) }
        let activeRemovedIDs = removedServiceIDs.filter { state.runtimes[$0]?.status.isActive == true }
        state.projects = projects
        for serviceID in removedServiceIDs {
          state.runtimes[serviceID] = nil
        }
        for service in project.services where state.runtimes[service.id] == nil {
          state.runtimes[service.id] = ProjectRuntime()
        }
        state.lastSavedProjectID = project.id
        guard !removedServiceIDs.isEmpty else { return .none }
        return .run { [processClient] _ in
          for serviceID in activeRemovedIDs {
            try? await processClient.stop(serviceID)
          }
          for serviceID in removedServiceIDs {
            await processClient.removeLogs(serviceID)
          }
        }

      case let .saveFailed(message):
        state.errorMessage = message
        return .none

      case let .openFolder(projectID):
        guard let project = state.projects.first(where: { $0.id == projectID }) else {
          return .none
        }
        return .run { [workspace] send in
          if !(await workspace.open(project.directoryURL)) {
            await send(.openFailed("Could not open the project folder."))
          }
        }

      case let .openURL(serviceID):
        guard let url = state.runtimes[serviceID]?.detectedURL else { return .none }
        return .run { [workspace] send in
          if !(await workspace.open(url)) {
            await send(.openFailed("Could not open the detected URL."))
          }
        }

      case let .openFailed(message):
        state.errorMessage = message
        return .none

      case let .processEvent(event):
        switch event {
        case let .started(serviceID, processIdentifier):
          guard var runtime = state.runtimes[serviceID] else { return .none }
          runtime.status = .running(processIdentifier: processIdentifier)
          runtime.detectedURL = nil
          runtime.hasLogs = false
          runtime.lastError = nil
          state.runtimes[serviceID] = runtime
        case let .output(serviceID, _):
          state.runtimes[serviceID]?.hasLogs = true
        case let .detectedURL(serviceID, url):
          state.runtimes[serviceID]?.detectedURL = url
        case let .finished(serviceID, exit):
          guard var runtime = state.runtimes[serviceID] else { return .none }
          runtime.status = .exited(exit)
          if case let .error(message) = exit {
            runtime.lastError = message
          } else {
            runtime.lastError = nil
          }
          state.runtimes[serviceID] = runtime
        case let .stopFailed(serviceID, message):
          state.runtimes[serviceID]?.lastError = message
        case .logsRemoved:
          break
        }
        return .none

      case .delegate:
        return .none
      }
    }
  }

  private func launch(_ serviceIDs: [UUID], of project: Project, state: inout State) -> Effect<Action> {
    do {
      try ProjectValidator.validate(project, alongside: state.projects.filter { $0.id != project.id })
    } catch {
      state.errorMessage = error.localizedDescription
      return .none
    }
    let launches = serviceIDs
      .filter { state.runtimes[$0]?.status.isActive != true }
      .compactMap { project.launch(for: $0) }
    guard !launches.isEmpty else { return .none }
    state.errorMessage = nil
    for launch in launches {
      var runtime = state.runtimes[launch.id] ?? ProjectRuntime()
      runtime.status = .starting
      runtime.detectedURL = nil
      runtime.lastError = nil
      state.runtimes[launch.id] = runtime
    }
    let starts = launches.map { launch in
      Effect<Action>.run { [processClient] send in
        do {
          await send(.startSucceeded(launch.id, try await processClient.start(launch)))
        } catch {
          await send(.startFailed(launch.id, error.localizedDescription))
        }
      }
    }
    return .merge(starts + [.send(.delegate(.launchRequested(project.id)))])
  }

  private func markStopping(_ serviceIDs: [UUID], state: inout State) {
    for serviceID in serviceIDs {
      state.runtimes[serviceID, default: ProjectRuntime()].status = .stopping
    }
  }

  private func stopEffect(serviceIDs: [UUID], thenRunStopCommandOf project: Project?) -> Effect<Action> {
    let projectStop = project.flatMap { project in
      project.stopCommand.map { (projectID: project.id, command: $0, directoryPath: project.directoryPath) }
    }
    return .run { [processClient] send in
      await withTaskGroup(of: Void.self) { group in
        for serviceID in serviceIDs {
          group.addTask {
            do {
              try await processClient.stop(serviceID)
            } catch {
              let failure = Self.stopFailure(from: error)
              await send(.stopFailed(serviceID, failure.message, processStopped: failure.processStopped))
            }
          }
        }
      }
      guard let projectStop else { return }
      do {
        try await processClient.runCommand(projectStop.command, projectStop.directoryPath)
      } catch {
        await send(.projectStopCommandFailed(projectStop.projectID, error.localizedDescription))
      }
    }
  }

  private func restartEffect(_ launch: ServiceLaunch) -> Effect<Action> {
    .run { [processClient] send in
      do {
        await send(.startSucceeded(launch.id, try await processClient.restart(launch)))
      } catch {
        let failure = Self.stopFailure(from: error)
        await send(.restartFailed(launch.id, failure.message, processStopped: failure.processStopped))
      }
    }
  }

  private static func stopFailure(from error: any Error) -> (message: String, processStopped: Bool) {
    if case .stopCommandFailed = error as? ProjectProcessManagerError {
      return (error.localizedDescription, true)
    }
    return (error.localizedDescription, false)
  }

  private func deleteEffect(project: Project, stopping serviceIDs: [UUID], projects: [Project]) -> Effect<Action> {
    let updatedProjects = projects.filter { $0.id != project.id }
    return .run { [repository, processClient] send in
      do {
        for serviceID in serviceIDs {
          try await processClient.stop(serviceID)
        }
        if !serviceIDs.isEmpty, let command = project.stopCommand {
          try? await processClient.runCommand(command, project.directoryPath)
        }
        try await repository.save(updatedProjects)
        for service in project.services {
          await processClient.removeLogs(service.id)
        }
        await send(.deleteSucceeded(project.id, updatedProjects))
      } catch {
        await send(.deleteFailed(project.id, error.localizedDescription))
      }
    }
  }
}
