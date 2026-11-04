import Foundation
import Testing
@testable import Stackbar

struct RuntimeDomainTests {
  @Test(arguments: [
    ("ERROR:    [Errno 48] Address already in use", "The port is already in use by another process."),
    ("Error: listen EADDRINUSE: address already in use :::3000", "Port 3000 is already in use by another process."),
    ("Bind for 0.0.0.0:5432 failed: port is already allocated", "Port 5432 is already in use by another process."),
    ("Port 4200 is already in use.", "Port 4200 is already in use by another process."),
  ])
  func explainsPortAlreadyInUse(output: String, expected: String) {
    #expect(OutputDiagnostics.failureHint(in: "starting\n\(output)\n") == expected)
  }

  @Test
  func ignoresOutputWithoutKnownFailure() {
    #expect(OutputDiagnostics.failureHint(in: "Listening on http://localhost:3000\nready") == nil)
  }

  @Test
  func identifiesOnlyLocalURLsAndKeepsFirstMatch() throws {
    let detectedURL = URLDetector.firstLocalURL(
      in: "Remote: https://example.com, local: http://192.168.1.8:8080/health",
      localAddresses: ["192.168.1.8"]
    )

    #expect(detectedURL?.absoluteString == "http://192.168.1.8:8080/health")
  }

  @Test
  func detectsLoopbackAndNormalizesWildcardAddress() {
    let loopback = URLDetector.firstLocalURL(
      in: "http://[::1]:4000 http://0.0.0.0:3000/",
      localAddresses: []
    )
    let wildcard = URLDetector.firstLocalURL(
      in: "Listening at http://0.0.0.0:3000/",
      localAddresses: []
    )

    #expect(loopback?.absoluteString == "http://[::1]:4000")
    #expect(wildcard?.absoluteString == "http://localhost:3000/")
  }

  @Test
  func ignoresNonLocalAddresses() {
    #expect(
      URLDetector.firstLocalURL(
        in: "http://example.com http://192.168.1.2:3000",
        localAddresses: []
      ) == nil
    )
  }

  @Test
  func streamsUtf8AndAnsiSequencesAcrossChunks() {
    var buffer = LogBuffer(maximumBytes: 64)
    let firstChunk = Data("caf\u{00E9}".utf8)
    let bytes = Array(firstChunk)
    let splitAt = bytes.count - 1

    _ = buffer.append(Data(bytes.prefix(splitAt)))
    _ = buffer.append(Data(bytes.suffix(from: splitAt)))
    _ = buffer.append(Data("\u{1B}[".utf8))
    _ = buffer.append(Data("31mred\u{1B}[0m\n".utf8))

    #expect(buffer.snapshot.text == "caféred\n")
  }

  @Test
  func evictsOldLinesAndBoundsLongSingleLines() {
    var lineBuffer = LogBuffer(maximumBytes: 8)
    _ = lineBuffer.append(Data("first\n".utf8))
    _ = lineBuffer.append(Data("second\n".utf8))
    #expect(lineBuffer.snapshot.text == "second\n")
    #expect(lineBuffer.snapshot.wasTruncated)

    var longLineBuffer = LogBuffer(maximumBytes: 5)
    _ = longLineBuffer.append(Data("0123456789".utf8))
    #expect(longLineBuffer.snapshot.text == "56789")
    #expect(longLineBuffer.snapshot.wasTruncated)
  }

  @Test
  func inactiveRuntimeIsNotRunning() {
    #expect(!ProjectRuntimeStatus.exited(.normal).isActive)
    #expect(ProjectRuntimeStatus.running(processIdentifier: 42).isActive)
  }
}
