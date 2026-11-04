import Foundation

actor LogStore {
  private var buffers: [UUID: LogBuffer] = [:]

  func reset(for serviceID: UUID) {
    buffers[serviceID] = LogBuffer()
  }

  @discardableResult
  func append(_ data: Data, to serviceID: UUID) -> String {
    var buffer = buffers[serviceID, default: LogBuffer()]
    let visibleText = buffer.append(data)
    buffers[serviceID] = buffer
    return visibleText
  }

  @discardableResult
  func finish(for serviceID: UUID) -> String {
    guard var buffer = buffers[serviceID] else { return "" }
    let visibleText = buffer.finish()
    buffers[serviceID] = buffer
    return visibleText
  }

  func snapshot(for serviceID: UUID) -> LogSnapshot {
    buffers[serviceID]?.snapshot ?? LogSnapshot()
  }

  func remove(serviceID: UUID) {
    buffers.removeValue(forKey: serviceID)
  }
}

