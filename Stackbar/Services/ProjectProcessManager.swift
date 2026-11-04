import Darwin
import Foundation

enum ProjectProcessManagerError: LocalizedError, Equatable, Sendable {
  case sessionAlreadyActive
  case sessionNotFound
  case processHostUnavailable(String)
  case signalFailed(Int32)
  case stopCommandTimedOut
  case stopCommandStillRunning
  case stopCommandFailed(String)
  case processDidNotStop
  case stopFailed(String)

  var errorDescription: String? {
    switch self {
    case .sessionAlreadyActive:
      "This service already has an active session."
    case .sessionNotFound:
      "This service does not have an active session."
    case let .processHostUnavailable(path):
      "The process host is missing or not executable: \(path)"
    case let .signalFailed(code):
      "Could not signal the project process group (errno \(code))."
    case .stopCommandTimedOut:
      "The stop command exceeded its 30-second limit."
    case .stopCommandStillRunning:
      "The stop command did not stop after receiving a termination request."
    case let .stopCommandFailed(message):
      "The stop command failed: \(message)"
    case .processDidNotStop:
      "The project process group did not stop within 10 seconds."
    case let .stopFailed(message):
      message
    }
  }
}

struct ProcessStopFailure: Equatable, Sendable {
  var serviceID: UUID
  var message: String
}

enum ProjectProcessEvent: Equatable, Sendable {
  case started(serviceID: UUID, processIdentifier: Int32)
  case output(serviceID: UUID, text: String)
  case detectedURL(serviceID: UUID, url: URL)
  case finished(serviceID: UUID, exit: ProjectExit)
  case stopFailed(serviceID: UUID, message: String)
  case logsRemoved(serviceID: UUID)
}

actor ProjectProcessManager {
  private struct Session {
    var launch: ServiceLaunch
    /// Nil for a session adopted from a previous Stackbar run.
    var process: Process?
    var processGroup: pid_t
    var startedAt: Double?
    var shell: LoginShell
    var localAddresses: Set<String>
    var isStopping = false
    var detectedURL: URL?
    var urlDetectionBuffer = ""
    var diagnosticsBuffer = ""
    var failureHint: String?
    var outputTask: Task<Void, Never>?
    var lingeringStopProcesses: [Process] = []
  }

  private let logStore: LogStore
  private let helperURL: URL?
  private let registry: RunningServiceRegistry?
  private var sessions: [UUID: Session] = [:]
  private var subscribers: [UUID: AsyncStream<ProjectProcessEvent>.Continuation] = [:]

  init(logStore: LogStore = LogStore(), helperURL: URL? = nil, registry: RunningServiceRegistry? = nil) {
    self.logStore = logStore
    self.helperURL = helperURL
    self.registry = registry
  }

  func events() -> AsyncStream<ProjectProcessEvent> {
    let subscriberID = UUID()
    let (stream, continuation) = AsyncStream<ProjectProcessEvent>.makeStream()
    subscribers[subscriberID] = continuation
    continuation.onTermination = { [weak self] _ in
      Task { await self?.removeSubscriber(subscriberID) }
    }
    return stream
  }

  @discardableResult
  func start(_ launch: ServiceLaunch, localAddresses: Set<String>? = nil) async throws -> Int32 {
    guard sessions[launch.id] == nil else {
      throw ProjectProcessManagerError.sessionAlreadyActive
    }
    guard !launch.launchCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ProjectValidationError.emptyLaunchCommand(Service.defaultName)
    }

    let shell = try LoginShell.current()
    let addresses: Set<String>
    if let localAddresses {
      addresses = localAddresses
    } else {
      addresses = try LocalAddressProvider.addresses()
    }
    let host = try processHostURL()
    await logStore.reset(for: launch.id)

    let outputPipe = Pipe()
    let process = Process()
    process.executableURL = host
    process.arguments = [launch.directoryPath, shell.path] + shell.arguments(for: launch.launchCommand)
    process.currentDirectoryURL = launch.directoryURL
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = outputPipe
    process.standardError = outputPipe

    let outputStream = makeOutputStream(from: outputPipe.fileHandleForReading)
    do {
      try process.run()
      outputPipe.fileHandleForWriting.closeFile()
    } catch {
      outputPipe.fileHandleForReading.readabilityHandler = nil
      outputPipe.fileHandleForReading.closeFile()
      outputPipe.fileHandleForWriting.closeFile()
      throw error
    }

    let processIdentifier = process.processIdentifier
    sessions[launch.id] = Session(
      launch: launch,
      process: process,
      processGroup: processIdentifier,
      startedAt: RunningServiceRegistry.processStartTime(processIdentifier),
      shell: shell,
      localAddresses: addresses
    )
    saveRegistry()
    let outputTask = Task { [weak self] in
      for await data in outputStream {
        guard let self else { return }
        await self.receiveOutput(data, serviceID: launch.id)
      }
      await self?.finishOutput(serviceID: launch.id)
    }
    sessions[launch.id]?.outputTask = outputTask

    Task { [weak self] in
      await self?.monitor(process, serviceID: launch.id)
    }
    publish(.started(serviceID: launch.id, processIdentifier: processIdentifier))
    return processIdentifier
  }

  func stop(serviceID: UUID) async throws {
    guard var session = sessions[serviceID] else {
      throw ProjectProcessManagerError.sessionNotFound
    }
    guard !session.isStopping else {
      throw ProjectProcessManagerError.sessionAlreadyActive
    }
    session.isStopping = true
    sessions[serviceID] = session

    var stopCommandFailure: String?
    if session.lingeringStopProcesses.isEmpty,
       let command = session.launch.stopCommand,
       !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      do {
        if let process = try await runStopCommand(command, directoryPath: session.launch.directoryPath, shell: session.shell) {
          if let latestSession = sessions[serviceID] {
            session = latestSession
          }
          session.lingeringStopProcesses.append(process)
          sessions[serviceID] = session
          stopCommandFailure = ProjectProcessManagerError.stopCommandStillRunning.localizedDescription
        }
      } catch {
        stopCommandFailure = error.localizedDescription
      }
    }
    if let latestSession = sessions[serviceID] {
      session = latestSession
    }

    let stopError: String?
    do {
      try sendTerminationSignal(to: session.processGroup)
      for process in session.lingeringStopProcesses {
        try sendTerminationSignal(to: process.processIdentifier)
      }
      let stopped = try await waitForSessionGroups(session, timeout: .seconds(10))
      guard stopped else { throw ProjectProcessManagerError.processDidNotStop }
      stopError = nil
    } catch {
      stopError = error.localizedDescription
    }

    guard let stopError else {
      if let outputTask = session.outputTask {
        await outputTask.value
      }
      endSession(serviceID)
      let exit = stopCommandFailure.map(ProjectExit.error) ?? .normal
      publish(.finished(serviceID: serviceID, exit: exit))
      if let stopCommandFailure {
        throw ProjectProcessManagerError.stopCommandFailed(stopCommandFailure)
      }
      return
    }

    let activeStopProcesses = session.lingeringStopProcesses.filter {
      $0.isRunning || processGroupExists($0.processIdentifier)
    }
    if var currentSession = sessions[serviceID] {
      currentSession.isStopping = false
      currentSession.lingeringStopProcesses = activeStopProcesses
      sessions[serviceID] = currentSession
    }
    let message = [stopCommandFailure, stopError]
      .compactMap { $0 }
      .joined(separator: " ")
    publish(.stopFailed(serviceID: serviceID, message: message))
    throw ProjectProcessManagerError.stopFailed(message)
  }

  @discardableResult
  func restart(_ launch: ServiceLaunch, localAddresses: Set<String>? = nil) async throws -> Int32 {
    try await stop(serviceID: launch.id)
    return try await start(launch, localAddresses: localAddresses)
  }

  /// Runs a one-shot command (such as a project-level stop command) with the same 30-second limit as stop commands.
  func runCommand(_ command: String, in directoryPath: String) async throws {
    let shell = try LoginShell.current()
    if let lingering = try await runStopCommand(command, directoryPath: directoryPath, shell: shell) {
      try? sendTerminationSignal(to: lingering.processIdentifier)
      throw ProjectProcessManagerError.stopCommandStillRunning
    }
  }

  func stopAll() async -> [ProcessStopFailure] {
    let serviceIDs = Array(sessions.keys)
    return await withTaskGroup(of: ProcessStopFailure?.self) { group in
      for serviceID in serviceIDs {
        group.addTask {
          do {
            try await self.stop(serviceID: serviceID)
            return nil
          } catch {
            return ProcessStopFailure(serviceID: serviceID, message: error.localizedDescription)
          }
        }
      }

      var failures: [ProcessStopFailure] = []
      for await failure in group {
        if let failure {
          failures.append(failure)
        }
      }
      return failures
    }
  }

  /// Adopts services left running by a previous Stackbar run (crash or force quit).
  /// Returns the adopted services and their process group; stale registry entries are dropped.
  func adoptOrphans(_ launches: [ServiceLaunch]) -> [UUID: Int32] {
    guard let registry else { return [:] }
    var adopted: [UUID: Int32] = [:]
    for entry in registry.load() where sessions[entry.serviceID] == nil {
      guard
        let launch = launches.first(where: { $0.id == entry.serviceID }),
        RunningServiceRegistry.isAlive(entry),
        let shell = try? LoginShell.current()
      else {
        continue
      }
      sessions[entry.serviceID] = Session(
        launch: launch,
        process: nil,
        processGroup: entry.processGroup,
        startedAt: entry.startedAt,
        shell: shell,
        localAddresses: []
      )
      adopted[entry.serviceID] = entry.processGroup
      Task { [weak self] in
        await self?.monitorAdopted(serviceID: entry.serviceID, processGroup: entry.processGroup)
      }
    }
    saveRegistry()
    return adopted
  }

  func activeServiceIDs() -> Set<UUID> {
    Set(sessions.keys)
  }

  func removeLogs(for serviceID: UUID) async {
    await logStore.remove(serviceID: serviceID)
    publish(.logsRemoved(serviceID: serviceID))
  }

  private func processHostURL() throws -> URL {
    let applicationHelper = Bundle.main.bundleURL
      .appendingPathComponent("Contents", isDirectory: true)
      .appendingPathComponent("MacOS", isDirectory: true)
      .appendingPathComponent("Helpers", isDirectory: true)
      .appendingPathComponent("StackbarProcessHost")
    let url = helperURL ?? applicationHelper
    guard FileManager.default.isExecutableFile(atPath: url.path) else {
      throw ProjectProcessManagerError.processHostUnavailable(url.path)
    }
    return url
  }

  private func makeOutputStream(from handle: FileHandle) -> AsyncStream<Data> {
    AsyncStream { continuation in
      handle.readabilityHandler = { readyHandle in
        let data = readyHandle.availableData
        if data.isEmpty {
          readyHandle.readabilityHandler = nil
          continuation.finish()
        } else {
          continuation.yield(data)
        }
      }
    }
  }

  private func receiveOutput(_ data: Data, serviceID: UUID) async {
    let text = await logStore.append(data, to: serviceID)
    publishVisibleText(text, serviceID: serviceID)
  }

  private func publishVisibleText(_ text: String, serviceID: UUID) {
    guard !text.isEmpty else { return }
    publish(.output(serviceID: serviceID, text: text))

    if var session = sessions[serviceID], session.failureHint == nil {
      session.diagnosticsBuffer = String((session.diagnosticsBuffer + text).suffix(4_096))
      session.failureHint = OutputDiagnostics.failureHint(in: session.diagnosticsBuffer)
      sessions[serviceID] = session
    }

    guard var session = sessions[serviceID], session.detectedURL == nil else { return }
    session.urlDetectionBuffer.append(text)
    if let url = URLDetector.firstLocalURL(
      in: session.urlDetectionBuffer,
      localAddresses: session.localAddresses
    ) {
      session.detectedURL = url
      session.urlDetectionBuffer = ""
      sessions[serviceID] = session
      publish(.detectedURL(serviceID: serviceID, url: url))
    } else {
      session.urlDetectionBuffer = String(session.urlDetectionBuffer.suffix(4_096))
      sessions[serviceID] = session
    }
  }

  private func finishOutput(serviceID: UUID) async {
    let text = await logStore.finish(for: serviceID)
    publishVisibleText(text, serviceID: serviceID)
  }

  private func monitor(_ process: Process, serviceID: UUID) async {
    while process.isRunning {
      do {
        try await Task.sleep(for: .milliseconds(100))
      } catch {
        return
      }
    }

    guard var session = sessions[serviceID], !session.isStopping else { return }
    if processGroupExists(process.processIdentifier) {
      session.isStopping = false
      sessions[serviceID] = session
      publish(
        .stopFailed(
          serviceID: serviceID,
          message: "The login shell exited while child processes remain. Stop the project to terminate them."
        )
      )
      return
    }
    if session.lingeringStopProcesses.contains(where: {
      $0.isRunning || processGroupExists($0.processIdentifier)
    }) {
      publish(
        .stopFailed(
          serviceID: serviceID,
          message: "The project shell exited, but its stop command still has active processes."
        )
      )
      return
    }

    if let outputTask = session.outputTask {
      await outputTask.value
    }
    let failureHint = sessions[serviceID]?.failureHint
    endSession(serviceID)
    publish(.finished(serviceID: serviceID, exit: exitClassification(for: process, failureHint: failureHint)))
  }

  private func monitorAdopted(serviceID: UUID, processGroup: pid_t) async {
    while processGroupExists(processGroup) {
      do {
        try await Task.sleep(for: .milliseconds(500))
      } catch {
        return
      }
    }
    guard let session = sessions[serviceID], !session.isStopping, session.processGroup == processGroup else {
      return
    }
    endSession(serviceID)
    publish(.finished(serviceID: serviceID, exit: .normal))
  }

  private func endSession(_ serviceID: UUID) {
    sessions[serviceID] = nil
    saveRegistry()
  }

  private func saveRegistry() {
    registry?.save(sessions.map { serviceID, session in
      RunningServiceRegistry.Entry(
        serviceID: serviceID,
        processGroup: session.processGroup,
        startedAt: session.startedAt
      )
    })
  }

  private func runStopCommand(
    _ command: String,
    directoryPath: String,
    shell: LoginShell
  ) async throws -> Process? {
    let process = Process()
    process.executableURL = try processHostURL()
    process.arguments = [directoryPath, shell.path] + shell.arguments(for: command)
    process.currentDirectoryURL = URL(fileURLWithPath: directoryPath, isDirectory: true)
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()

    let processIdentifier = process.processIdentifier
    guard try await waitForGroups(
      [(process: process, identifier: processIdentifier)],
      timeout: .seconds(30)
    ) else {
      try sendTerminationSignal(to: processIdentifier)
      return processGroupExists(processIdentifier) ? process : nil
    }

    guard process.terminationReason == .exit, process.terminationStatus == 0 else {
      throw ProjectProcessManagerError.stopCommandFailed(
        "exit status \(process.terminationStatus)"
      )
    }
    return nil
  }

  private func waitForSessionGroups(_ session: Session, timeout: Duration) async throws -> Bool {
    var groups: [(process: Process?, identifier: pid_t)] = [
      (process: session.process, identifier: session.processGroup)
    ]
    groups.append(
      contentsOf: session.lingeringStopProcesses.map {
        (process: Optional($0), identifier: $0.processIdentifier)
      }
    )
    return try await waitForGroups(groups, timeout: timeout)
  }

  private func waitForGroups(
    _ groups: [(process: Process?, identifier: pid_t)],
    timeout: Duration
  ) async throws -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while groups.contains(where: { group in
      group.process?.isRunning == true || processGroupExists(group.identifier)
    }) {
      guard ContinuousClock.now < deadline else { return false }
      try await Task.sleep(for: .milliseconds(50))
    }
    return true
  }

  private func sendTerminationSignal(to processGroup: pid_t) throws {
    guard kill(-processGroup, SIGTERM) != 0, errno != ESRCH else { return }
    throw ProjectProcessManagerError.signalFailed(errno)
  }

  private func processGroupExists(_ processGroup: pid_t) -> Bool {
    if kill(-processGroup, 0) == 0 { return true }
    return errno != ESRCH
  }

  private func exitClassification(for process: Process, failureHint: String?) -> ProjectExit {
    guard process.terminationReason == .exit, process.terminationStatus == 0 else {
      return .error(failureHint ?? "Process exited with status \(process.terminationStatus).")
    }
    return .normal
  }

  private func publish(_ event: ProjectProcessEvent) {
    for continuation in subscribers.values {
      continuation.yield(event)
    }
  }

  private func removeSubscriber(_ id: UUID) {
    subscribers[id] = nil
  }
}
