import AppKit
import ComposableArchitecture
import Foundation
import ServiceManagement
import UserNotifications

struct ProjectRepositoryClient: Sendable {
  var load: @Sendable () async throws -> [Project]
  var save: @Sendable ([Project]) async throws -> Void
}

struct ProjectProcessClient: Sendable {
  var events: @Sendable () async -> AsyncStream<ProjectProcessEvent>
  var start: @Sendable (ServiceLaunch) async throws -> Int32
  var stop: @Sendable (UUID) async throws -> Void
  var restart: @Sendable (ServiceLaunch) async throws -> Int32
  /// Runs a one-shot command (command, directory path), used for project-level stop commands.
  var runCommand: @Sendable (String, String) async throws -> Void
  var activeServiceIDs: @Sendable () async -> Set<UUID>
  var stopAll: @Sendable () async -> [ProcessStopFailure]
  var removeLogs: @Sendable (UUID) async -> Void
}

struct LogClient: Sendable {
  var snapshot: @Sendable (UUID) async -> LogSnapshot
}

struct PreferencesClient: Sendable {
  var load: @Sendable () async -> NotificationPreferences
  var save: @Sendable (NotificationPreferences) async -> Void
}

struct LoginItemClient: Sendable {
  var status: @MainActor @Sendable () -> LoginItemStatus
  var setEnabled: @MainActor @Sendable (Bool) throws -> LoginItemStatus
}

struct NotificationClient: Sendable {
  var authorizationStatus: @MainActor @Sendable () async -> NotificationAuthorization
  var requestAuthorization: @MainActor @Sendable () async throws -> NotificationAuthorization
  var send: @MainActor @Sendable (String, String) async throws -> Void
}

struct WorkspaceClient: Sendable {
  var open: @MainActor @Sendable (URL) -> Bool
}

private actor PreferencesRepository {
  func load() -> NotificationPreferences {
    let defaults = UserDefaults.standard
    return NotificationPreferences(
      notifyOnNormalStop: defaults.object(forKey: "notifyOnNormalStop") as? Bool ?? true,
      notifyOnError: defaults.object(forKey: "notifyOnError") as? Bool ?? true
    )
  }

  func save(_ preferences: NotificationPreferences) {
    let defaults = UserDefaults.standard
    defaults.set(preferences.notifyOnNormalStop, forKey: "notifyOnNormalStop")
    defaults.set(preferences.notifyOnError, forKey: "notifyOnError")
  }
}

private enum LiveServices {
  static let projectRepository = ProjectRepository()
  static let logStore = LogStore()
  static let processManager = ProjectProcessManager(logStore: logStore)
  static let preferencesRepository = PreferencesRepository()
}

private enum ProjectRepositoryClientKey: DependencyKey {
  static let liveValue = ProjectRepositoryClient(
    load: { try await LiveServices.projectRepository.load() },
    save: { try await LiveServices.projectRepository.save($0) }
  )
}

private enum ProjectProcessClientKey: DependencyKey {
  static let liveValue = ProjectProcessClient(
    events: { await LiveServices.processManager.events() },
    start: { try await LiveServices.processManager.start($0) },
    stop: { try await LiveServices.processManager.stop(serviceID: $0) },
    restart: { try await LiveServices.processManager.restart($0) },
    runCommand: { try await LiveServices.processManager.runCommand($0, in: $1) },
    activeServiceIDs: { await LiveServices.processManager.activeServiceIDs() },
    stopAll: { await LiveServices.processManager.stopAll() },
    removeLogs: { await LiveServices.processManager.removeLogs(for: $0) }
  )
}

private enum LogClientKey: DependencyKey {
  static let liveValue = LogClient(
    snapshot: { await LiveServices.logStore.snapshot(for: $0) }
  )
}

private enum PreferencesClientKey: DependencyKey {
  static let liveValue = PreferencesClient(
    load: { await LiveServices.preferencesRepository.load() },
    save: { await LiveServices.preferencesRepository.save($0) }
  )
}

private enum LoginItemClientKey: DependencyKey {
  static let liveValue = LoginItemClient(
    status: { loginItemStatus() },
    setEnabled: { enabled in
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      return loginItemStatus()
    }
  )
}

private enum NotificationClientKey: DependencyKey {
  static let liveValue = NotificationClient(
    authorizationStatus: {
      await currentNotificationAuthorization()
    },
    requestAuthorization: {
      let center = UNUserNotificationCenter.current()
      _ = try await center.requestAuthorization(options: [.alert, .sound])
      return await currentNotificationAuthorization()
    },
    send: { title, body in
      let content = UNMutableNotificationContent()
      content.title = title
      content.body = body
      content.sound = .default
      let request = UNNotificationRequest(
        identifier: UUID().uuidString,
        content: content,
        trigger: nil
      )
      try await UNUserNotificationCenter.current().add(request)
    }
  )
}

private enum WorkspaceClientKey: DependencyKey {
  static let liveValue = WorkspaceClient(
    open: { NSWorkspace.shared.open($0) }
  )
}

extension DependencyValues {
  var projectRepositoryClient: ProjectRepositoryClient {
    get { self[ProjectRepositoryClientKey.self] }
    set { self[ProjectRepositoryClientKey.self] = newValue }
  }

  var projectProcessClient: ProjectProcessClient {
    get { self[ProjectProcessClientKey.self] }
    set { self[ProjectProcessClientKey.self] = newValue }
  }

  var logClient: LogClient {
    get { self[LogClientKey.self] }
    set { self[LogClientKey.self] = newValue }
  }

  var preferencesClient: PreferencesClient {
    get { self[PreferencesClientKey.self] }
    set { self[PreferencesClientKey.self] = newValue }
  }

  var loginItemClient: LoginItemClient {
    get { self[LoginItemClientKey.self] }
    set { self[LoginItemClientKey.self] = newValue }
  }

  var notificationClient: NotificationClient {
    get { self[NotificationClientKey.self] }
    set { self[NotificationClientKey.self] = newValue }
  }

  var workspaceClient: WorkspaceClient {
    get { self[WorkspaceClientKey.self] }
    set { self[WorkspaceClientKey.self] = newValue }
  }
}

@MainActor
private func currentNotificationAuthorization() async -> NotificationAuthorization {
  let settings = await UNUserNotificationCenter.current().notificationSettings()
  switch settings.authorizationStatus {
  case .notDetermined:
    return .notDetermined
  case .denied:
    return .denied
  case .authorized:
    return .authorized
  case .provisional:
    return .provisional
  case .ephemeral:
    return .ephemeral
  @unknown default:
    return .unknown
  }
}

@MainActor
private func loginItemStatus() -> LoginItemStatus {
  switch SMAppService.mainApp.status {
  case .notRegistered:
    return .notRegistered
  case .enabled:
    return .enabled
  case .requiresApproval:
    return .requiresApproval
  case .notFound:
    return .notFound
  @unknown default:
    return .unknown
  }
}
