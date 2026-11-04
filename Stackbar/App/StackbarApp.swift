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
      MenuBarLabel(store: store)
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

/// Always-alive menu bar label: running service count, red icon on error.
/// It also opens log windows requested from outside SwiftUI (notification clicks).
private struct MenuBarLabel: View {
  let store: StoreOf<AppFeature>
  @Environment(\.openWindow) private var openWindow

  private var runningCount: Int {
    store.projects.runtimes.values.filter {
      if case .running = $0.status { return true }
      return false
    }.count
  }

  private var hasError: Bool {
    store.projects.runtimes.values.contains {
      if $0.lastError != nil { return true }
      if case .exited(.error) = $0.status { return true }
      return false
    }
  }

  var body: some View {
    HStack(spacing: 2) {
      icon
      if runningCount > 0 {
        Text("\(runningCount)")
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: LogWindowDestination.openRequest)) { notification in
      guard let destination = notification.object as? LogWindowDestination else { return }
      openWindow(value: destination)
    }
  }

  @ViewBuilder
  private var icon: some View {
    if hasError, let image = Self.errorImage {
      Image(nsImage: image)
    } else {
      Image(systemName: "square.stack.3d.up")
    }
  }

  /// Non-template image so the menu bar keeps the red tint.
  private static let errorImage: NSImage? = {
    let configuration = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
    let image = NSImage(systemSymbolName: "square.stack.3d.up.fill", accessibilityDescription: "Stackbar error")?
      .withSymbolConfiguration(configuration)
    image?.isTemplate = false
    return image
  }()
}
