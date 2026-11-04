import ComposableArchitecture
import Foundation

@Reducer
struct LogsFeature {
  @ObservableState
  struct State: Equatable {
    var serviceID: UUID
    var title: String
    var snapshot = LogSnapshot()
    var isDeleted = false
  }

  enum Action: Equatable {
    case task
    case snapshotLoaded(LogSnapshot)
    case refresh
    case logsRemoved
  }

  @Dependency(\.logClient) private var logClient
  @Dependency(\.projectProcessClient) private var processClient

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .task:
        let serviceID = state.serviceID
        return .merge(
          .run { [logClient] send in
            await send(.snapshotLoaded(await logClient.snapshot(serviceID)))
            while !Task.isCancelled {
              do {
                try await Task.sleep(for: .milliseconds(250))
              } catch {
                return
              }
              await send(.refresh)
            }
          },
          .run { [processClient] send in
            let events = await processClient.events()
            for await event in events {
              if case let .logsRemoved(eventServiceID) = event, eventServiceID == serviceID {
                await send(.logsRemoved)
              }
            }
          }
        )

      case let .snapshotLoaded(snapshot):
        state.snapshot = snapshot
        return .none

      case .refresh:
        let serviceID = state.serviceID
        return .run { [logClient] send in
          await send(.snapshotLoaded(await logClient.snapshot(serviceID)))
        }

      case .logsRemoved:
        state.isDeleted = true
        return .none
      }
    }
  }
}
