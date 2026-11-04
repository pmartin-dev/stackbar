import Foundation

struct NotificationPreferences: Equatable, Sendable {
  var notifyOnNormalStop = true
  var notifyOnError = true
}

enum NotificationAuthorization: Equatable, Sendable {
  case notDetermined
  case denied
  case authorized
  case provisional
  case ephemeral
  case unknown

  var allowsNotifications: Bool {
    self == .authorized || self == .provisional || self == .ephemeral
  }
}

enum LoginItemStatus: Equatable, Sendable {
  case notRegistered
  case enabled
  case requiresApproval
  case notFound
  case unknown
}
