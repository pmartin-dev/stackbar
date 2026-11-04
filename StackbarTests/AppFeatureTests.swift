import Testing
@testable import Stackbar

struct AppFeatureTests {
  @Test
  func startsWithEmptyProjectsAndEnabledNotificationPreferences() {
    let state = AppFeature.State()

    #expect(state.projects.projects.isEmpty)
    #expect(state.preferences.notificationPreferences.notifyOnNormalStop)
    #expect(state.preferences.notificationPreferences.notifyOnError)
  }
}
