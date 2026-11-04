import AppKit
import ComposableArchitecture
import SwiftUI

struct MenuContent: View {
  @Bindable var store: StoreOf<AppFeature>
  @Environment(\.openWindow) private var openWindow
  @Environment(\.openSettings) private var openSettings

  private var projects: [Project] {
    store.projects.projects.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if projects.isEmpty {
        Text("No projects configured.")
          .foregroundStyle(.secondary)
          .padding(12)
      } else {
        VStack(spacing: 2) {
          ForEach(projects) { project in
            ProjectRow(
              project: project,
              summary: store.projects.summary(for: project),
              runtimes: store.projects.runtimes,
              launchDisabledReason: launchDisabledReason(for: project),
              send: { store.send(.projects($0)) },
              openLogs: { service in
                activate()
                let title = project.hasMultipleServices ? "\(project.name) › \(service.name)" : project.name
                openWindow(value: LogWindowDestination(serviceID: service.id, title: title))
              }
            )
          }
        }
        .padding(6)
      }

      if let error = store.projects.errorMessage {
        Label(error, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.red)
          .padding(.horizontal, 12)
          .padding(.bottom, 8)
      }

      Divider()
      HStack(spacing: 4) {
        Button {
          activate()
          openSettings()
        } label: {
          Label("Preferences...", systemImage: "gear")
        }
        Spacer()
        Button {
          NSApp.terminate(nil)
        } label: {
          Label("Quit", systemImage: "power")
        }
      }
      .buttonStyle(HoverButtonStyle(padding: 6))
      .padding(6)
    }
    .frame(width: 340)
  }

  private func activate() {
    NSApp.activate()
  }

  private func launchDisabledReason(for project: Project) -> String? {
    do {
      try ProjectValidator.validate(
        project,
        alongside: store.projects.projects.filter { $0.id != project.id }
      )
      return nil
    } catch {
      return error.localizedDescription
    }
  }
}

private struct ProjectRow: View {
  let project: Project
  let summary: ProjectStatusSummary
  let runtimes: [UUID: ProjectRuntime]
  let launchDisabledReason: String?
  let send: (ProjectsFeature.Action) -> Void
  let openLogs: (Service) -> Void

  @State private var isHovered = false

  private var singleService: Service? {
    project.hasMultipleServices ? nil : project.services.first
  }

  private func runtime(_ service: Service) -> ProjectRuntime {
    runtimes[service.id] ?? ProjectRuntime()
  }

  var body: some View {
    VStack(spacing: 2) {
      header
      if project.hasMultipleServices, isHovered {
        VStack(spacing: 0) {
          ForEach(project.services) { service in
            ServiceRow(
              service: service,
              runtime: runtime(service),
              launchDisabled: launchDisabledReason != nil,
              send: send,
              openLogs: { openLogs(service) }
            )
          }
        }
        .padding(.leading, 16)
        .transition(.opacity)
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(.primary.opacity(isHovered ? 0.06 : 0))
    )
    .contentShape(Rectangle())
    .onHover { hovering in
      withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
    }
  }

  private var header: some View {
    HStack(spacing: 8) {
      StatusDot(color: summary.color)
      VStack(alignment: .leading, spacing: 1) {
        Text(project.name)
          .lineLimit(1)
        if let subtitle {
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(summary.errorMessage != nil ? .red : .secondary)
            .lineLimit(2)
        }
      }
      Spacer(minLength: 4)

      HStack(spacing: 2) {
        if let service = singleService {
          ServiceActions(service: service, runtime: runtime(service), send: send, openLogs: { openLogs(service) })
        }
        if summary.isActive {
          IconButton(systemImage: "folder", help: "Open folder") { send(.openFolder(project.id)) }
        }
        if project.hasMultipleServices, summary.runningCount > 0 {
          IconButton(systemImage: "arrow.clockwise", help: "Restart all services") { send(.restartTapped(project.id)) }
        }
      }
      .opacity(isHovered ? 1 : 0)
      .allowsHitTesting(isHovered)

      PlayStopButton(
        isActive: summary.isActive,
        isStopping: summary.status == .stopping,
        disabledReason: launchDisabledReason,
        size: 30,
        stopHelp: project.hasMultipleServices ? "Stop all services" : "Stop",
        launchHelp: project.hasMultipleServices ? "Launch all services" : "Launch",
        stop: { send(.stopTapped(project.id)) },
        launch: { send(.launchTapped(project.id)) }
      )
    }
  }

  private var subtitle: String? {
    if let service = singleService {
      return ServiceRow.subtitle(for: runtime(service))
    }
    let count = project.services.count
    switch summary.status {
    case .starting: return "Starting..."
    case .stopping: return "Stopping..."
    case .running: return "\(count) services running"
    case .partial:
      let progress = "\(summary.runningCount)/\(count) running"
      return summary.errorMessage.map { "\(progress) · \($0)" } ?? progress
    case .failed: return summary.errorMessage
    case .stopped: return "\(count) services"
    }
  }
}

private struct ServiceRow: View {
  let service: Service
  let runtime: ProjectRuntime
  let launchDisabled: Bool
  let send: (ProjectsFeature.Action) -> Void
  let openLogs: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      StatusDot(color: Self.color(for: runtime.status), size: 6)
      VStack(alignment: .leading, spacing: 0) {
        Text(service.name)
          .font(.callout)
          .lineLimit(1)
        if let subtitle = Self.subtitle(for: runtime) {
          Text(subtitle)
            .font(.caption2)
            .foregroundStyle(runtime.lastError != nil ? .red : .secondary)
            .lineLimit(1)
        }
      }
      Spacer(minLength: 4)
      ServiceActions(service: service, runtime: runtime, send: send, openLogs: openLogs)
      PlayStopButton(
        isActive: runtime.status.isActive,
        isStopping: runtime.status == .stopping,
        disabledReason: launchDisabled ? "Fix the project settings first." : nil,
        size: 24,
        stopHelp: "Stop \(service.name)",
        launchHelp: "Launch \(service.name)",
        stop: { send(.stopServiceTapped(service.id)) },
        launch: { send(.launchServiceTapped(service.id)) }
      )
    }
    .padding(.vertical, 3)
  }

  static func color(for status: ProjectRuntimeStatus) -> Color {
    switch status {
    case .running: .green
    case .starting, .stopping: .orange
    case .exited(.error): .red
    case .stopped, .exited(.normal): .gray.opacity(0.5)
    }
  }

  static func subtitle(for runtime: ProjectRuntime) -> String? {
    if let error = runtime.lastError { return error }
    switch runtime.status {
    case .starting: return "Starting..."
    case .stopping: return "Stopping..."
    case .running: return runtime.detectedURL.map { "\($0.host ?? "localhost")\($0.port.map { ":\($0)" } ?? "")" } ?? "Running"
    case let .exited(.error(message)): return message
    case .exited(.normal): return "Stopped normally"
    case .stopped: return nil
    }
  }
}

/// URL, logs and restart actions shared by single-service projects and service rows.
private struct ServiceActions: View {
  let service: Service
  let runtime: ProjectRuntime
  let send: (ProjectsFeature.Action) -> Void
  let openLogs: () -> Void

  var body: some View {
    if let url = runtime.detectedURL {
      IconButton(systemImage: "safari", help: "Open \(url.absoluteString)") { send(.openURL(service.id)) }
    }
    if runtime.status.isActive || runtime.hasLogs {
      IconButton(systemImage: "doc.text", help: "View logs", action: openLogs)
    }
    if case .running = runtime.status {
      IconButton(systemImage: "arrow.clockwise", help: "Restart") { send(.restartServiceTapped(service.id)) }
    }
  }
}
