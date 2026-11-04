import Darwin
import Foundation
import Testing
@testable import Stackbar

struct ProjectProcessManagerTests {
  @Test
  func launchesOnceAndStopsTheProcessGroupAfterRunningStopCommand() async throws {
    let root = try makeProcessTestDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let projectFolder = root.appendingPathComponent("Example", isDirectory: true)
    try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: false)
    let stopMarker = root.appendingPathComponent("stop-command-ran")
    let project = Project(
      name: "Example",
      directoryURL: projectFolder,
      launchCommand: "sleep 60 & echo child-started; wait",
      stopCommand: "printf stopped > '\(stopMarker.path)'"
    )
    let logs = LogStore()
    let manager = try makeProcessManager(logStore: logs)

    let processIdentifier = try await manager.start(try #require(project.launch(for: project.id)), localAddresses: [])
    defer { Task { _ = await manager.stopAll() } }
    try await waitForOutput(logs, projectID: project.id, containing: "child-started")

    await #expect(throws: ProjectProcessManagerError.self) {
      try await manager.start(try #require(project.launch(for: project.id)), localAddresses: [])
    }
    try await manager.stop(serviceID: project.id)

    let stopCommandOutput = try String(contentsOf: stopMarker, encoding: .utf8)
    let activeIDs = await manager.activeServiceIDs()
    let groupStatus = kill(-pid_t(processIdentifier), 0)
    let groupError = errno

    #expect(stopCommandOutput == "stopped")
    #expect(activeIDs.isEmpty)
    #expect(groupStatus == -1)
    #expect(groupError == ESRCH)
    #expect((await logs.snapshot(for: project.id)).text.contains("child-started"))
  }

  @Test
  func failedStopCommandStillTerminatesProjectAndReportsError() async throws {
    let root = try makeProcessTestDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let projectFolder = root.appendingPathComponent("Example", isDirectory: true)
    try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: false)
    let project = Project(
      name: "Example",
      directoryURL: projectFolder,
      launchCommand: "sleep 60 & echo child-started; wait",
      stopCommand: "exit 1"
    )
    let logs = LogStore()
    let manager = try makeProcessManager(logStore: logs)

    try await manager.start(try #require(project.launch(for: project.id)), localAddresses: [])
    defer { Task { _ = await manager.stopAll() } }
    try await waitForOutput(logs, projectID: project.id, containing: "child-started")

    await #expect(throws: ProjectProcessManagerError.self) {
      try await manager.stop(serviceID: project.id)
    }
    let activeIDs = await manager.activeServiceIDs()
    #expect(activeIDs.isEmpty)
  }

  @Test
  func givenProjectStopCommandWhenRunningItThenItRunsInTheProjectFolderAndReportsFailures() async throws {
    let root = try makeProcessTestDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let manager = try makeProcessManager(logStore: LogStore())

    try await manager.runCommand("printf done > marker", in: root.path)

    #expect(try String(contentsOf: root.appendingPathComponent("marker"), encoding: .utf8) == "done")
    await #expect(throws: ProjectProcessManagerError.self) {
      try await manager.runCommand("exit 3", in: root.path)
    }
  }
}

extension ProjectProcessManagerTests {
  @Test
  func givenServiceLeftRunningByPreviousRunWhenAdoptingThenItCanBeStopped() async throws {
    let root = try makeProcessTestDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let registry = RunningServiceRegistry(fileURL: root.appendingPathComponent("running.json"))
    let project = Project(name: "Example", directoryURL: root, launchCommand: "sleep 60 & echo child-started; wait")
    let launch = try #require(project.launch(for: project.id))
    let logs = LogStore()
    let crashed = try makeProcessManager(logStore: logs, registry: registry)
    let processGroup = try await crashed.start(launch, localAddresses: [])
    try await waitForOutput(logs, projectID: project.id, containing: "child-started")
    #expect(registry.load().map(\.serviceID) == [project.id])

    let relaunched = try makeProcessManager(logStore: LogStore(), registry: registry)
    let adopted = await relaunched.adoptOrphans([launch])
    #expect(adopted == [project.id: processGroup])
    #expect(await relaunched.activeServiceIDs() == [project.id])

    try await relaunched.stop(serviceID: project.id)

    #expect(kill(-processGroup, 0) == -1)
    #expect(registry.load().isEmpty)
  }

  @Test
  func givenDeadOrUnknownRegistryEntriesWhenAdoptingThenTheyAreDropped() async throws {
    let root = try makeProcessTestDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let registry = RunningServiceRegistry(fileURL: root.appendingPathComponent("running.json"))
    let finished = Process()
    finished.executableURL = URL(fileURLWithPath: "/usr/bin/true")
    try finished.run()
    finished.waitUntilExit()
    let project = Project(name: "Example", directoryURL: root, launchCommand: "sleep 60")
    let launch = try #require(project.launch(for: project.id))
    registry.save([
      .init(serviceID: project.id, processGroup: finished.processIdentifier, startedAt: nil),
      .init(serviceID: UUID(), processGroup: getpgrp(), startedAt: nil),
    ])

    let manager = try makeProcessManager(logStore: LogStore(), registry: registry)
    let adopted = await manager.adoptOrphans([launch])

    #expect(adopted.isEmpty)
    #expect(registry.load().isEmpty)
  }
}

private final class ProcessManagerTestBundle: NSObject {}

private func makeProcessManager(
  logStore: LogStore,
  registry: RunningServiceRegistry? = nil
) throws -> ProjectProcessManager {
  let helperURL = Bundle(for: ProcessManagerTestBundle.self).bundleURL
    .appendingPathComponent("Contents", isDirectory: true)
    .appendingPathComponent("MacOS", isDirectory: true)
    .appendingPathComponent("StackbarProcessHost")
  guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
    throw ProjectProcessManagerError.processHostUnavailable(helperURL.path)
  }
  return ProjectProcessManager(logStore: logStore, helperURL: helperURL, registry: registry)
}

private func waitForOutput(
  _ logs: LogStore,
  projectID: UUID,
  containing expectedText: String
) async throws {
  let deadline = ContinuousClock.now.advanced(by: .seconds(5))
  while ContinuousClock.now < deadline {
    if await logs.snapshot(for: projectID).text.contains(expectedText) {
      return
    }
    try await Task.sleep(for: .milliseconds(50))
  }
  throw ProjectProcessManagerError.stopFailed("Timed out waiting for project output.")
}

private func makeProcessTestDirectory() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("StackbarProcessTests-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
  return directory
}
