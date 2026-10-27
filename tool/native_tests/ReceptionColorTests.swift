import UIKit

@main
struct ColorTests {
  @MainActor static func main() {
    let pair = ["light": "#112233", "dark": "#aabbcc80"]
    guard let color = ReceptionColor.decode(pair) else {
      preconditionFailure("Valid pair rejected")
    }
    let light = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
    let dark = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    precondition(light.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
    precondition(abs(red - 17.0 / 255) < 0.001 && abs(alpha - 1) < 0.001)
    precondition(dark.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
    precondition(abs(red - 170.0 / 255) < 0.001 && abs(alpha - 128.0 / 255) < 0.001)
    precondition(ReceptionColor.decode(["light": "#112233"]) == nil)
    precondition(ReceptionColor.decode(["light": "#112233", "dark": "wrong"]) == nil)
    precondition(ReceptionColor.decode("#12345678") != nil)
    guard let opaque = ReceptionColor.decode("#FF8000") else { preconditionFailure("Valid hex rejected") }
    precondition(opaque.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
    precondition(abs(red - 1) < 0.001 && abs(green - 128.0 / 255) < 0.001 && blue < 0.001 && abs(alpha - 1) < 0.001)
    for value: Any in ["#12345", "123456", "#GGGGGG", "#1234567", "#123456789", 42] {
      precondition(ReceptionColor.decode(value) == nil, "Malformed color accepted")
    }
    print("ReceptionColor: hex, alpha, dynamic light/dark pairs and malformed input passed")
  }
}
