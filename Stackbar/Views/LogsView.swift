import ComposableArchitecture
import SwiftUI

struct LogWindowDestination: Codable, Hashable, Sendable {
  static let windowGroupID = "project-logs"

  var serviceID: UUID
  var title: String

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.serviceID == rhs.serviceID
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(serviceID)
  }

  /// Posted on the main thread to ask the app to open a log window; `object` is the destination.
  static let openRequest = Notification.Name("io.github.pmartin-dev.stackbar.openLogWindow")

  var notificationUserInfo: [String: String] {
    ["serviceID": serviceID.uuidString, "title": title]
  }

  init(serviceID: UUID, title: String) {
    self.serviceID = serviceID
    self.title = title
  }

  init?(notificationUserInfo userInfo: [AnyHashable: Any]) {
    guard
      let serviceID = (userInfo["serviceID"] as? String).flatMap(UUID.init(uuidString:)),
      let title = userInfo["title"] as? String
    else {
      return nil
    }
    self.init(serviceID: serviceID, title: title)
  }
}

struct ProjectLogsWindow: View {
  @Environment(\.dismiss) private var dismiss
  @State private var store: StoreOf<LogsFeature>

  init(destination: LogWindowDestination) {
    _store = State(
      initialValue: Store(
        initialState: LogsFeature.State(
          serviceID: destination.serviceID,
          title: destination.title
        )
      ) {
        LogsFeature()
      }
    )
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        if store.snapshot.wasTruncated {
          Label("Older log output was removed to limit memory use.", systemImage: "exclamationmark.triangle")
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(.yellow.opacity(0.15))
        }
        ScrollViewReader { proxy in
          ScrollView {
            Text(store.snapshot.text.isEmpty ? "No output yet." : store.snapshot.text)
              .font(.system(.body, design: .monospaced))
              .frame(maxWidth: .infinity, alignment: .leading)
              .textSelection(.enabled)
              .padding()
              .id("log-output")
          }
          .onChange(of: store.snapshot.text) { _, _ in
            proxy.scrollTo("log-output", anchor: .bottom)
          }
        }
      }
      .navigationTitle("\(store.title) Logs")
    }
    .frame(minWidth: 620, minHeight: 420)
    .task {
      await store.send(.task).finish()
    }
    .onChange(of: store.isDeleted) { _, isDeleted in
      if isDeleted {
        dismiss()
      }
    }
  }
}
