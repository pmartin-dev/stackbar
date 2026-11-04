import AppKit
import ComposableArchitecture

@MainActor
final class AppTerminationCoordinator: NSObject, NSApplicationDelegate {
  @Dependency(\.projectProcessClient) private var processClient
  @Dependency(\.projectRepositoryClient) private var repositoryClient

  private var isHandlingTermination = false

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard !isHandlingTermination else { return .terminateCancel }
    isHandlingTermination = true

    Task { @MainActor in
      let activeServiceIDs = await processClient.activeServiceIDs()
      guard !activeServiceIDs.isEmpty else {
        sender.reply(toApplicationShouldTerminate: true)
        return
      }

      let confirmation = NSAlert()
      confirmation.alertStyle = .warning
      confirmation.messageText = "Quit Stackbar?"
      confirmation.informativeText =
        "\(activeServiceIDs.count) service(s) are running. Stackbar will stop them before quitting."
      confirmation.addButton(withTitle: "Stop Projects and Quit")
      confirmation.addButton(withTitle: "Cancel")
      guard confirmation.runModal() == .alertFirstButtonReturn else {
        isHandlingTermination = false
        sender.reply(toApplicationShouldTerminate: false)
        return
      }

      var projectNameError: String? = nil
      let projects: [Project]
      do {
        projects = try await repositoryClient.load()
      } catch {
        projects = []
        projectNameError = error.localizedDescription
      }

      let failures = await processClient.stopAll()
      var failureDetails = failures.map { failure in
        "\(Self.displayName(of: failure.serviceID, in: projects)): \(failure.message)"
      }
      let projectsToStop = projects.filter { project in
        project.stopCommand != nil && project.services.contains { activeServiceIDs.contains($0.id) }
      }
      for project in projectsToStop {
        guard let command = project.stopCommand else { continue }
        do {
          try await processClient.runCommand(command, project.directoryPath)
        } catch {
          failureDetails.append("\(project.name) stop command: \(error.localizedDescription)")
        }
      }
      guard !failureDetails.isEmpty else {
        sender.reply(toApplicationShouldTerminate: true)
        return
      }

      if let projectNameError {
        failureDetails.append("Could not load project names: \(projectNameError)")
      }
      let failureAlert = NSAlert()
      failureAlert.alertStyle = .critical
      failureAlert.messageText = "Stackbar could not stop every project."
      failureAlert.informativeText = failureDetails.joined(separator: "\n")
      failureAlert.addButton(withTitle: "Keep Stackbar Open")
      failureAlert.runModal()
      isHandlingTermination = false
      sender.reply(toApplicationShouldTerminate: false)
    }

    return .terminateLater
  }

  private static func displayName(of serviceID: UUID, in projects: [Project]) -> String {
    guard
      let project = projects.first(where: { $0.services.contains { $0.id == serviceID } }),
      let service = project.services.first(where: { $0.id == serviceID })
    else {
      return serviceID.uuidString
    }
    return project.hasMultipleServices ? "\(project.name) › \(service.name)" : project.name
  }
}
