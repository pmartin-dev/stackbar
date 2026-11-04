import ComposableArchitecture

@Reducer
struct AppFeature {
  @ObservableState
  struct State: Equatable {
    var projects = ProjectsFeature.State()
    var preferences = PreferencesFeature.State()
  }

  enum Action: Equatable {
    case task
    case projects(ProjectsFeature.Action)
    case preferences(PreferencesFeature.Action)
    case processEvent(ProjectProcessEvent)
  }

  @Dependency(\.projectProcessClient) private var processClient
  @Dependency(\.notificationClient) private var notificationClient

  var body: some ReducerOf<Self> {
    Scope(state: \.projects, action: \.projects) {
      ProjectsFeature()
    }
    Scope(state: \.preferences, action: \.preferences) {
      PreferencesFeature()
    }
    Reduce { state, action in
      switch action {
      case .task:
        return .merge(
          .send(.projects(.task)),
          .send(.preferences(.task)),
          .run { [processClient] send in
            let events = await processClient.events()
            for await event in events {
              await send(.processEvent(event))
            }
          }
        )

      case .projects(.delegate(.launchRequested(_))):
        return .send(.preferences(.requestNotificationAuthorization))

      case .projects:
        return .none

      case .preferences:
        return .none

      case let .processEvent(event):
        guard case let .finished(serviceID, exit) = event,
              let project = state.projects.project(containingService: serviceID),
              let service = project.services.first(where: { $0.id == serviceID })
        else {
          return .send(.projects(.processEvent(event)))
        }

        let displayName = project.hasMultipleServices ? "\(project.name) › \(service.name)" : project.name
        let preferences = state.preferences.notificationPreferences
        let shouldNotify: Bool
        let body: String
        switch exit {
        case .normal:
          shouldNotify = preferences.notifyOnNormalStop
          body = "\(displayName) stopped normally."
        case let .error(message):
          shouldNotify = preferences.notifyOnError
          body = "\(displayName): \(message)"
        }
        guard shouldNotify else {
          return .send(.projects(.processEvent(event)))
        }
        return .merge(
          .send(.projects(.processEvent(event))),
          .run { [notificationClient] send in
            var authorization = await notificationClient.authorizationStatus()
            if authorization == .notDetermined {
              do {
                authorization = try await notificationClient.requestAuthorization()
              } catch {
                await send(.preferences(.notificationFailed(error.localizedDescription)))
                return
              }
            }
            guard authorization.allowsNotifications else { return }
            do {
              try await notificationClient.send("Stackbar", body)
            } catch {
              await send(.preferences(.notificationFailed(error.localizedDescription)))
            }
          }
        )
      }
    }
  }
}
