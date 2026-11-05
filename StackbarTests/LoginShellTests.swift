import Testing
@testable import Stackbar

struct LoginShellTests {
  @Test
  func usesInteractiveLoginZshArguments() throws {
    let shell = try LoginShell(path: "/bin/zsh")

    #expect(shell.arguments(for: "npm run dev") == ["-ilc", "set +m; npm run dev"])
  }

  @Test
  func usesInteractiveLoginBashArguments() throws {
    let shell = try LoginShell(path: "/bin/bash")

    #expect(shell.arguments(for: "make run") == ["--login", "-i", "-c", "set +m; make run"])
  }

  @Test
  func rejectsUnsupportedShells() {
    #expect(throws: LoginShellError.self) {
      try LoginShell(path: "/bin/fish")
    }
  }
}
