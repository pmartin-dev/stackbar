import AppKit
import ComposableArchitecture
import SwiftUI

struct PreferencesView: View {
  @Bindable var store: StoreOf<AppFeature>
  @State private var newDrafts: [ProjectDraft] = []
  @State private var expandedIDs: Set<UUID> = []

  private var savedIDs: Set<UUID> { Set(store.projects.projects.map(\.id)) }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        SettingsSection("Projects") {
          if store.projects.projects.isEmpty && newDrafts.isEmpty {
            Text("No projects configured.")
              .foregroundStyle(.secondary)
              .padding(8)
          }
          ForEach(store.projects.projects) { project in
            projectCard(ProjectDraft(project: project), saved: project)
          }
          ForEach(newDrafts.filter { !savedIDs.contains($0.id) }) { draft in
            projectCard(draft, saved: nil)
          }
        } accessory: {
          Button {
            guard let url = FolderPicker.choose() else { return }
            var draft = ProjectDraft()
            draft.chooseDirectory(url)
            newDrafts.append(draft)
            expandedIDs.insert(draft.id)
          } label: {
            Label("Add Project", systemImage: "plus")
          }
          .buttonStyle(HoverButtonStyle(padding: 6))
        }

        if let error = store.projects.errorMessage ?? store.preferences.errorMessage {
          Label(error, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.red)
            .padding(.horizontal, 4)
        }

        SettingsSection("Launch at Login") {
          SettingsToggleRow(
            title: "Launch Stackbar at login",
            hint: loginItemHint,
            isOn: Binding(
              get: { store.preferences.loginItemStatus == .enabled },
              set: { store.send(.preferences(.loginItemChanged($0))) }
            )
          )
        }

        SettingsSection("Notifications") {
          SettingsToggleRow(
            title: "Notify when a project stops normally",
            isOn: Binding(
              get: { store.preferences.notificationPreferences.notifyOnNormalStop },
              set: {
                var preferences = store.preferences.notificationPreferences
                preferences.notifyOnNormalStop = $0
                store.send(.preferences(.notificationPreferencesChanged(preferences)))
              }
            )
          )
          SettingsToggleRow(
            title: "Notify when a project stops with an error",
            isOn: Binding(
              get: { store.preferences.notificationPreferences.notifyOnError },
              set: {
                var preferences = store.preferences.notificationPreferences
                preferences.notifyOnError = $0
                store.send(.preferences(.notificationPreferencesChanged(preferences)))
              }
            )
          )
          Text(notificationAuthorizationDescription)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
      }
      .padding(20)
    }
    .frame(width: 560, height: 600)
    .onChange(of: store.projects.projects.map(\.id)) { _, ids in
      newDrafts.removeAll { ids.contains($0.id) }
    }
  }

  private var loginItemHint: String? {
    switch store.preferences.loginItemStatus {
    case .requiresApproval: "Enable Stackbar in System Settings > General > Login Items."
    case .notFound: "macOS could not find Stackbar's login item."
    case .unknown: "Checking login item status..."
    case .notRegistered, .enabled: nil
    }
  }

  private func projectCard(_ draft: ProjectDraft, saved: Project?) -> some View {
    ProjectCard(
      initialDraft: draft,
      saved: saved,
      otherProjects: store.projects.projects.filter { $0.id != draft.id },
      summary: saved.map { store.projects.summary(for: $0) },
      isPendingDelete: saved != nil && store.projects.pendingDeleteID == draft.id,
      isExpanded: Binding(
        get: { expandedIDs.contains(draft.id) },
        set: { if $0 { expandedIDs.insert(draft.id) } else { expandedIDs.remove(draft.id) } }
      ),
      send: { store.send(.projects($0)) },
      onSave: { project in
        await store.send(.projects(.saveProject(project))).finish()
        if store.projects.lastSavedProjectID == project.id { return nil }
        return store.projects.errorMessage ?? "Could not save the project."
      },
      onDelete: {
        if saved == nil {
          newDrafts.removeAll { $0.id == draft.id }
        } else {
          store.send(.projects(.deleteTapped(draft.id)))
        }
      }
    )
    .id(draft.id)
  }

  private var notificationAuthorizationDescription: String {
    switch store.preferences.notificationAuthorization {
    case .notDetermined:
      "macOS will ask for notification permission when you first launch a project."
    case .denied:
      "Notifications are disabled. Enable them in System Settings > Notifications."
    case .authorized, .provisional, .ephemeral:
      "Stackbar is allowed to send notifications."
    case .unknown:
      "Checking notification permission..."
    }
  }

}

private struct ProjectCard: View {
  @State private var draft: ProjectDraft
  @State private var saveError: String?
  @State private var isDropTargeted = false
  @State private var isHovered = false
  @State private var detectedCommands: [DetectedCommand]?
  @State private var selectedCommandIDs: Set<DetectedCommand.ID> = []
  @State private var showsAllDetected = false
  @FocusState private var isNameFocused: Bool

  let saved: Project?
  let otherProjects: [Project]
  let summary: ProjectStatusSummary?
  let isPendingDelete: Bool
  @Binding var isExpanded: Bool
  let send: (ProjectsFeature.Action) -> Void
  let onSave: (Project) async -> String?
  let onDelete: () -> Void

  init(
    initialDraft: ProjectDraft,
    saved: Project?,
    otherProjects: [Project],
    summary: ProjectStatusSummary?,
    isPendingDelete: Bool,
    isExpanded: Binding<Bool>,
    send: @escaping (ProjectsFeature.Action) -> Void,
    onSave: @escaping (Project) async -> String?,
    onDelete: @escaping () -> Void
  ) {
    _draft = State(initialValue: initialDraft)
    self.saved = saved
    self.otherProjects = otherProjects
    self.summary = summary
    self.isPendingDelete = isPendingDelete
    _isExpanded = isExpanded
    self.send = send
    self.onSave = onSave
    self.onDelete = onDelete
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      if isPendingDelete {
        deleteConfirmation
      }
      if isExpanded {
        details
          .padding(.horizontal, 8)
          .padding(.top, 4)
          .padding(.bottom, 10)
          .transition(.opacity)
      }
    }
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(isDropTargeted ? Color.accentColor.opacity(0.15) : .primary.opacity(isHovered || isExpanded ? 0.06 : 0))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .strokeBorder(Color.accentColor.opacity(isDropTargeted ? 0.8 : 0), lineWidth: 1.5)
    )
    .onHover { hovering in
      withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
    }
    .dropDestination(for: URL.self) { urls, _ in
      guard let url = urls.first(where: \.hasDirectoryPath) else { return false }
      folderChosen(url)
      isExpanded = true
      return true
    } isTargeted: { isDropTargeted = $0 }
    .onAppear {
      guard saved == nil else { return }
      if draft.directoryURL != nil, hasNoLaunchCommand {
        detectCommands()
      } else {
        isNameFocused = true
      }
    }
    .task(id: draft) {
      try? await Task.sleep(for: .milliseconds(400))
      guard !Task.isCancelled else { return }
      await autosave()
    }
  }

  private var header: some View {
    HStack(spacing: 8) {
      Image(systemName: "chevron.right")
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.secondary)
        .rotationEffect(.degrees(isExpanded ? 90 : 0))
        .frame(width: 12)
      StatusDot(color: summary?.color ?? .gray.opacity(0.5))
      VStack(alignment: .leading, spacing: 1) {
        Text(draft.name.isEmpty ? "New Project" : draft.name)
          .lineLimit(1)
          .foregroundStyle(draft.name.isEmpty ? .secondary : .primary)
        Text(headerSubtitle)
          .font(.caption)
          .foregroundStyle(summary?.errorMessage != nil ? .red : .secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      Spacer(minLength: 4)

      HStack(spacing: 2) {
        if saved != nil {
          IconButton(systemImage: "folder", help: "Open folder") { send(.openFolder(draft.id)) }
        }
        IconButton(systemImage: "trash", help: saved == nil ? "Discard" : "Delete project", action: onDelete)
      }
      .opacity(isHovered ? 1 : 0)
      .allowsHitTesting(isHovered)

      PlayStopButton(
        isActive: summary?.isActive ?? false,
        isStopping: summary?.status == .stopping,
        disabledReason: launchDisabledReason,
        size: 30,
        stopHelp: (saved?.hasMultipleServices ?? false) ? "Stop all services" : "Stop",
        launchHelp: (saved?.hasMultipleServices ?? false) ? "Launch all services" : "Launch",
        stop: { send(.stopTapped(draft.id)) },
        launch: { send(.launchTapped(draft.id)) }
      )
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .contentShape(Rectangle())
    .onTapGesture {
      withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() }
    }
  }

  private var headerSubtitle: String {
    if let error = summary?.errorMessage { return error }
    return draft.directoryURL?.path ?? "No folder"
  }

  private var launchDisabledReason: String? {
    guard saved != nil else { return "Save the project first." }
    if saveError != nil || validationError != nil { return "Fix the project settings first." }
    return nil
  }

  private var deleteConfirmation: some View {
    HStack(spacing: 8) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
      Text("\(draft.name) is running. Stop and delete it?")
        .font(.callout)
        .lineLimit(2)
      Spacer(minLength: 4)
      Button("Cancel") { send(.cancelDelete) }
        .buttonStyle(HoverButtonStyle(padding: 6))
      Button("Stop and Delete") { send(.confirmDelete) }
        .buttonStyle(TintedButtonStyle(tint: .red))
    }
    .padding(8)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(Color.red.opacity(0.08))
    )
    .padding(.horizontal, 8)
    .padding(.bottom, 8)
  }

  private var details: some View {
    VStack(alignment: .leading, spacing: 10) {
      field("Name") {
        TextField("Name", text: $draft.name, prompt: Text(""))
          .focused($isNameFocused)
          .fieldChrome()
      }
      field("Folder") {
        HStack(spacing: 4) {
          Text(draft.directoryURL?.path ?? "Choose or drop a folder")
            .foregroundStyle(draft.directoryURL == nil ? .secondary : .primary)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fieldChrome()
          Button { chooseFolder() } label: {
            Label("Choose...", systemImage: "folder")
          }
          .buttonStyle(HoverButtonStyle(padding: 6))
          Button { detectCommands() } label: {
            Label("Detect", systemImage: "wand.and.stars")
          }
          .buttonStyle(HoverButtonStyle(padding: 6))
          .disabled(draft.directoryURL == nil)
          .help("Scan the folder for launch commands")
        }
      }
      if let detectedCommands {
        detectionPanel(detectedCommands)
      }
      if isMultiService {
        servicesSection
      } else {
        commandFields(for: $draft.services[0])
        addServiceButton
      }
      statusMessage
    }
    .labelsHidden()
  }

  private var validationError: ProjectValidationError? {
    do {
      _ = try draft.validated(alongside: otherProjects)
      return nil
    } catch let error as ProjectValidationError {
      return error
    } catch {
      return nil
    }
  }

  @ViewBuilder
  private var statusMessage: some View {
    if let saveError {
      Label(saveError, systemImage: "exclamationmark.triangle.fill")
        .foregroundStyle(.red)
    } else if let error = validationError {
      switch error {
      case .emptyName, .emptyLaunchCommand, .emptyServiceName, .noDirectorySelected:
        Text(saved == nil
          ? "Fill in the name, folder and launch command to save."
          : "Not saved: \(error.localizedDescription)")
          .foregroundStyle(saved == nil ? Color.secondary : Color.red)
      default:
        Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(.red)
      }
    }
  }

  private var isMultiService: Bool {
    draft.services.count > 1 || !draft.stopCommand.isEmpty
  }

  @ViewBuilder
  private var servicesSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Services")
        .font(.caption)
        .foregroundStyle(.secondary)
      ForEach($draft.services) { $service in
        VStack(alignment: .leading, spacing: 8) {
          HStack(alignment: .bottom, spacing: 8) {
            field("Service name") {
              TextField("Service name", text: $service.name, prompt: Text(""))
                .fieldChrome()
            }
            field("Subfolder (optional)") {
              TextField("Subfolder", text: $service.relativeDirectory, prompt: Text(""))
                .fieldChrome(monospaced: true)
            }
            IconButton(systemImage: "minus.circle", help: "Remove service") {
              draft.removeService(service.id)
            }
            .disabled(draft.services.count == 1)
          }
          commandFields(for: $service)
        }
        .padding(10)
        .background(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.primary.opacity(0.04))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(.primary.opacity(0.06))
        )
      }
      addServiceButton
      field("Project stop command (optional, runs after every service has stopped)") {
        TextField("Project stop command", text: $draft.stopCommand, prompt: Text(""), axis: .vertical)
          .lineLimit(1...3)
          .fieldChrome(monospaced: true)
      }
    }
  }

  private var addServiceButton: some View {
    Button {
      draft.addService()
    } label: {
      Label("Add Service", systemImage: "plus.circle")
    }
    .buttonStyle(HoverButtonStyle(padding: 6))
  }

  @ViewBuilder
  private func commandFields(for service: Binding<ServiceDraft>) -> some View {
    field("Launch command") {
      TextField("Launch command", text: service.launchCommand, prompt: Text(""), axis: .vertical)
        .lineLimit(1...4)
        .fieldChrome(monospaced: true)
    }
    field("Stop command (optional)") {
      TextField("Stop command", text: service.stopCommand, prompt: Text(""), axis: .vertical)
        .lineLimit(1...3)
        .fieldChrome(monospaced: true)
    }
  }

  private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      content()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func autosave() async {
    guard
      let project = try? draft.validated(alongside: otherProjects),
      project != saved
    else {
      saveError = nil
      return
    }
    saveError = await onSave(project)
  }

  private func chooseFolder() {
    if let url = FolderPicker.choose(startingAt: draft.directoryURL) {
      folderChosen(url)
    }
  }

  private var hasNoLaunchCommand: Bool {
    draft.services.allSatisfy { $0.launchCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
  }

  private func folderChosen(_ url: URL) {
    draft.chooseDirectory(url)
    if hasNoLaunchCommand {
      detectCommands()
    }
  }

  private func detectCommands() {
    guard let directoryURL = draft.directoryURL else { return }
    let commands = CommandDetector.detect(in: directoryURL)
    selectedCommandIDs = Set(commands.filter(\.isLikelyService).map(\.id))
    showsAllDetected = !commands.contains(where: \.isLikelyService)
    detectedCommands = commands
  }

  @ViewBuilder
  private func detectionPanel(_ commands: [DetectedCommand]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("Detected commands", systemImage: "wand.and.stars")
        .font(.subheadline.weight(.semibold))
      if commands.isEmpty {
        Text("No commands detected in this folder.")
          .foregroundStyle(.secondary)
      } else {
        let visible = showsAllDetected ? commands : commands.filter { $0.isLikelyService || selectedCommandIDs.contains($0.id) }
        ForEach(DetectedCommand.Source.allCases.filter { source in visible.contains { $0.source == source } }, id: \.self) { source in
          VStack(alignment: .leading, spacing: 2) {
            Text(source.displayName)
              .font(.caption)
              .foregroundStyle(.secondary)
              .padding(.horizontal, 4)
            ForEach(visible.filter { $0.source == source }) { command in
              detectedCommandRow(command)
            }
          }
        }
        if visible.count < commands.count || showsAllDetected && commands.contains(where: \.isLikelyService) {
          Button {
            withAnimation(.easeOut(duration: 0.15)) { showsAllDetected.toggle() }
          } label: {
            Label(
              showsAllDetected ? "Show suggested only" : "Show \(commands.count - visible.count) more commands",
              systemImage: showsAllDetected ? "chevron.up" : "chevron.down"
            )
            .font(.callout)
          }
          .buttonStyle(HoverButtonStyle(padding: 5))
        }
      }
      HStack(spacing: 6) {
        Spacer()
        Button("Cancel") { detectedCommands = nil }
          .buttonStyle(HoverButtonStyle(padding: 6))
        if !commands.isEmpty {
          Button(selectedCommandIDs.count == 1 ? "Add 1 Service" : "Add \(selectedCommandIDs.count) Services") {
            draft.applyDetected(commands.filter { selectedCommandIDs.contains($0.id) })
            detectedCommands = nil
          }
          .buttonStyle(TintedButtonStyle(tint: .accentColor))
          .disabled(selectedCommandIDs.isEmpty)
        }
      }
    }
    .padding(10)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(.primary.opacity(0.04))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .strokeBorder(Color.accentColor.opacity(0.35))
    )
  }

  private func detectedCommandRow(_ command: DetectedCommand) -> some View {
    let isSelected = selectedCommandIDs.contains(command.id)
    return Button {
      selectionBinding(for: command.id).wrappedValue.toggle()
    } label: {
      HStack(spacing: 8) {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .font(.system(size: 15))
          .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        Text(command.name)
          .foregroundStyle(.primary)
        Text(command.command)
          .font(.callout.monospaced())
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.tail)
        Spacer(minLength: 0)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .buttonStyle(HoverButtonStyle(padding: 5))
  }

  private func selectionBinding(for id: DetectedCommand.ID) -> Binding<Bool> {
    Binding(
      get: { selectedCommandIDs.contains(id) },
      set: { isOn in
        if isOn { selectedCommandIDs.insert(id) } else { selectedCommandIDs.remove(id) }
      }
    )
  }
}

@MainActor
private enum FolderPicker {
  static func choose(startingAt directory: URL? = nil) -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = "Choose"
    panel.directoryURL = directory
    return panel.runModal() == .OK ? panel.url : nil
  }
}
