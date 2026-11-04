import Testing
@testable import Stackbar

struct LoginShellTests {
  @Test
  func usesInteractiveLoginZshArguments() throws {
    let shell = try LoginShell(path: "/bin/zsh")

    #expect(shell.arguments(for: "npm run dev") == ["-ilc", "npm run dev"])
  }

  @Test
  func usesInteractiveLoginBashArguments() throws {
    let shell = try LoginShell(path: "/bin/bash")

    #expect(shell.arguments(for: "make run") == ["--login", "-i", "-c", "make run"])
  }

  @Test
  func rejectsUnsupportedShells() {
    #expect(throws: LoginShellError.self) {
      try LoginShell(path: "/bin/fish")
    }
  }
}
