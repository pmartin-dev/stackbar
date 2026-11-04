import ComposableArchitecture

@Reducer
struct PreferencesFeature {
  @ObservableState
  struct State: Equatable {
    var notificationPreferences = NotificationPreferences()
    var notificationAuthorization: NotificationAuthorization = .unknown
    var loginItemStatus: LoginItemStatus = .unknown
    var errorMessage: String?
    var isRequestingAuthorization = false
  }

  enum Action: Equatable {
    case task
    case notificationPreferencesChanged(NotificationPreferences)
    case loginItemChanged(Bool)
    case loginItemStatusChanged(LoginItemStatus)
    case loginItemFailed(String)
    case notificationAuthorizationChanged(NotificationAuthorization)
    case requestNotificationAuthorization
    case notificationFailed(String)
  }

  @Dependency(\.preferencesClient) private var preferencesClient
  @Dependency(\.loginItemClient) private var loginItemClient
  @Dependency(\.notificationClient) private var notificationClient

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .task:
        return .merge(
          .run { [preferencesClient] send in
            await send(.notificationPreferencesChanged(await preferencesClient.load()))
          },
          .run { [loginItemClient] send in
            await send(.loginItemStatusChanged(await loginItemClient.status()))
          },
          .run { [notificationClient] send in
            await send(.notificationAuthorizationChanged(await notificationClient.authorizationStatus()))
          }
        )

      case let .notificationPreferencesChanged(preferences):
        state.notificationPreferences = preferences
        return .run { [preferencesClient] _ in
          await preferencesClient.save(preferences)
        }

      case let .loginItemChanged(enabled):
        state.errorMessage = nil
        return .run { [loginItemClient] send in
          do {
            await send(.loginItemStatusChanged(try await loginItemClient.setEnabled(enabled)))
          } catch {
            await send(.loginItemFailed(error.localizedDescription))
          }
        }

      case let .loginItemStatusChanged(status):
        state.loginItemStatus = status
        return .none

      case let .loginItemFailed(message):
        state.errorMessage = message
        return .none

      case let .notificationAuthorizationChanged(authorization):
        state.notificationAuthorization = authorization
        state.isRequestingAuthorization = false
        return .none

      case .requestNotificationAuthorization:
        guard !state.isRequestingAuthorization else { return .none }
        state.isRequestingAuthorization = true
        return .run { [notificationClient] send in
          do {
            let currentStatus = await notificationClient.authorizationStatus()
            let authorization: NotificationAuthorization
            if currentStatus == .notDetermined {
              authorization = try await notificationClient.requestAuthorization()
            } else {
              authorization = currentStatus
            }
            await send(.notificationAuthorizationChanged(authorization))
          } catch {
            await send(.notificationFailed(error.localizedDescription))
          }
        }

      case let .notificationFailed(message):
        state.isRequestingAuthorization = false
        state.errorMessage = message
        return .none
      }
    }
  }
}
