import Foundation

/// Decodes the APNs device token that Dart passes as hex.
internal enum PushToken {
  static func decode(_ token: String) -> Data? {
    guard token.utf8.count <= 512,
      token.range(of: "^([0-9a-fA-F]{2})+$", options: .regularExpression) != nil
    else { return nil }
    var bytes: [UInt8] = []
    var index = token.startIndex
    while index < token.endIndex {
      let end = token.index(index, offsetBy: 2)
      guard let byte = UInt8(token[index..<end], radix: 16) else { return nil }
      bytes.append(byte)
      index = end
    }
    return Data(bytes)
  }
}
