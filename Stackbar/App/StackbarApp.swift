import AppKit
import ComposableArchitecture
import SwiftUI

@main
struct StackbarApp: App {
  @NSApplicationDelegateAdaptor(AppTerminationCoordinator.self) private var terminationCoordinator
  @State private var store: StoreOf<AppFeature>

  init() {
    let store = Store(initialState: AppFeature.State()) {
      AppFeature()
    }
    _store = State(initialValue: store)
    Task {
      await store.send(.task).finish()
    }
  }

  var body: some Scene {
    MenuBarExtra {
      MenuContent(store: store)
    } label: {
      Label("Stackbar", systemImage: "square.stack.3d.up")
    }
    .menuBarExtraStyle(.window)

    Settings {
      PreferencesView(store: store)
    }

    WindowGroup(
      "Project Logs",
      id: LogWindowDestination.windowGroupID,
      for: LogWindowDestination.self
    ) { $destination in
      if let destination {
        ProjectLogsWindow(destination: destination)
      } else {
        Text("No project selected.")
      }
    }
  }
}
