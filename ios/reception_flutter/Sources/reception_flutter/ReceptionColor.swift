import UIKit

internal enum ReceptionColor {
  static func decode(_ value: Any?) -> UIColor? {
    if let hex = value as? String { return decodeHex(hex) }
    guard let pair = value as? [String: String], pair.count == 2,
      let lightHex = pair["light"], let darkHex = pair["dark"],
      let light = decodeHex(lightHex), let dark = decodeHex(darkHex)
    else { return nil }
    return UIColor { traits in traits.userInterfaceStyle == .dark ? dark : light }
  }

  private static func decodeHex(_ text: String) -> UIColor? {
    guard text.range(of: "^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$", options: .regularExpression) != nil,
      let value = UInt32(text.dropFirst(), radix: 16)
    else { return nil }
    let rgba = text.count == 7 ? (value << 8) | 255 : value
    return UIColor(
      red: CGFloat((rgba >> 24) & 255) / 255,
      green: CGFloat((rgba >> 16) & 255) / 255,
      blue: CGFloat((rgba >> 8) & 255) / 255,
      alpha: CGFloat(rgba & 255) / 255)
  }
}
