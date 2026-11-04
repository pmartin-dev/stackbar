import Darwin
import Foundation

enum URLDetector {
  static func firstLocalURL(in output: String, localAddresses: Set<String>) -> URL? {
    let expression = try! NSRegularExpression(pattern: #"https?://[^\s"'<>]+"#, options: [.caseInsensitive])
    let searchRange = NSRange(output.startIndex..<output.endIndex, in: output)
    let canonicalLocalAddresses = Set(localAddresses.compactMap(canonicalIPAddress))

    for match in expression.matches(in: output, range: searchRange) {
      guard let range = Range(match.range, in: output) else { continue }
      let candidate = String(output[range])
        .trimmingCharacters(in: CharacterSet(charactersIn: ".,;!?"))
      guard
        var components = URLComponents(string: candidate),
        let scheme = components.scheme?.lowercased(),
        scheme == "http" || scheme == "https",
        let rawHost = components.host
      else {
        continue
      }

      let host = rawHost.lowercased()
      if host == "0.0.0.0" {
        components.host = "localhost"
        return components.url
      }
      if host == "localhost" {
        return components.url
      }
      guard let address = canonicalIPAddress(rawHost) else { continue }
      if isLoopback(address) || canonicalLocalAddresses.contains(address) {
        return components.url
      }
    }
    return nil
  }

  private static func canonicalIPAddress(_ host: String) -> String? {
    let host = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    var ipv4 = in_addr()
    if host.withCString({ inet_pton(AF_INET, $0, &ipv4) }) == 1 {
      var address = ipv4
      var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
      guard inet_ntop(AF_INET, &address, &buffer, socklen_t(buffer.count)) != nil else {
        return nil
      }
      return stringFromCStringBuffer(buffer)
    }

    var ipv6 = in6_addr()
    if host.withCString({ inet_pton(AF_INET6, $0, &ipv6) }) == 1 {
      var address = ipv6
      var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
      guard inet_ntop(AF_INET6, &address, &buffer, socklen_t(buffer.count)) != nil else {
        return nil
      }
      return stringFromCStringBuffer(buffer)
    }
    return nil
  }

  private static func isLoopback(_ address: String) -> Bool {
    address.hasPrefix("127.") || address == "::1"
  }
}

enum LocalAddressProvider {
  static func addresses() throws -> Set<String> {
    var interfaces: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&interfaces) == 0, let interfaces else {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    defer { freeifaddrs(interfaces) }

    var addresses = Set<String>()
    var current: UnsafeMutablePointer<ifaddrs>? = interfaces
    while let interface = current {
      if let socketAddress = interface.pointee.ifa_addr,
         let address = printableIPAddress(socketAddress) {
        addresses.insert(address)
      }
      current = interface.pointee.ifa_next
    }
    return addresses
  }

  private static func printableIPAddress(_ socketAddress: UnsafePointer<sockaddr>) -> String? {
    switch Int32(socketAddress.pointee.sa_family) {
    case AF_INET:
      var address = UnsafeRawPointer(socketAddress)
        .assumingMemoryBound(to: sockaddr_in.self)
        .pointee.sin_addr
      var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
      guard inet_ntop(AF_INET, &address, &buffer, socklen_t(buffer.count)) != nil else {
        return nil
      }
      return stringFromCStringBuffer(buffer)
    case AF_INET6:
      var address = UnsafeRawPointer(socketAddress)
        .assumingMemoryBound(to: sockaddr_in6.self)
        .pointee.sin6_addr
      var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
      guard inet_ntop(AF_INET6, &address, &buffer, socklen_t(buffer.count)) != nil else {
        return nil
      }
      return stringFromCStringBuffer(buffer)
    default:
      return nil
    }
  }

}

private func stringFromCStringBuffer(_ buffer: [CChar]) -> String {
  String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
}
