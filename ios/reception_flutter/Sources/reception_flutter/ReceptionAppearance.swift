import SwiftUI
import os

@MainActor
internal enum ReceptionAppearance {
  private static let logger = Logger(
    subsystem: "com.reception.flutter", category: "Appearance")

  static func apply(_ json: String) {
    guard let data = json.data(using: .utf8),
      let values = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else { return }
    var style = Reception.Appearance()
    var accepted = values
    func color(_ key: String) -> Color? {
      ReceptionColor.decode(values[key]).map { Color(uiColor: $0) }
    }
    style.accentColor = color("accentColor") ?? .accentColor
    style.onAccentColor = color("onAccentColor")
    style.chatBackground = color("chatBackground")
    style.incomingBackground = color("incomingBackground")
    style.incomingForeground = color("incomingForeground")
    style.welcomeIconColor = color("welcomeIconColor")
    if let value = values["title"] as? String { style.title = value }
    if let value = values["welcomeTitle"] as? String { style.welcomeTitle = value }
    if let value = values["welcomeText"] as? String { style.welcomeText = value }
    if let value = values["showsCloseButton"] as? Bool { style.showsCloseButton = value }
    if let value = values["fadesOlderMessages"] as? Bool { style.fadesOlderMessages = value }
    if let value = values["hidesTitle"] as? Bool { style.hidesTitle = value }
    if let value = values["hidesWelcomeTitle"] as? Bool { style.hidesWelcomeTitle = value }
    if let value = values["hidesWelcomeText"] as? Bool { style.hidesWelcomeText = value }
    if let value = values["hidesPushStatus"] as? Bool { style.hidesPushStatus = value }
    if let value = values["closeIcon"] as? String, let icon = Reception.CloseIcon(rawValue: value) {
      style.closeIcon = icon
    }
    switch values["preferredColorScheme"] as? String {
    case "light": style.preferredColorScheme = .light
    case "dark": style.preferredColorScheme = .dark
    default: break
    }
    switch values["fontDesign"] as? String {
    case "default": style.fontDesign = .default
    case "rounded": style.fontDesign = .rounded
    case "serif": style.fontDesign = .serif
    case "monospaced": style.fontDesign = .monospaced
    default: break
    }
    if let value = values["fontFamily"] as? String {
      if UIFont(name: value, size: 17) != nil {
        style.fontFamily = value
      } else {
        logger.error("Unregistered font ignored")
        style.fontFamily = Reception.shared.appearance.fontFamily
        accepted["fontFamily"] = ReceptionHost.appearanceValues["fontFamily"]
      }
    }
    if let value = values["welcomeIconSize"] as? Double, value.isFinite, (16...160).contains(value)
    {
      style.welcomeIconSize = value
    }
    if let value = values["welcomeIconCornerRadius"] as? Double, value.isFinite,
      (0...80).contains(value)
    {
      style.welcomeIconCornerRadius = value
    }
    if let value = values["welcomeIconOffset"] as? [String: Double], let x = value["x"],
      let y = value["y"], (-1000...1000).contains(x), (-1000...1000).contains(y)
    {
      style.welcomeIconOffset = CGSize(width: x, height: y)
    }
    if let name = values["closeImage"] as? String {
      if let image = UIImage(named: name) {
        style.closeImage = Image(uiImage: image)
      } else {
        logger.error("Missing close image ignored")
        style.closeImage = Reception.shared.appearance.closeImage
        accepted["closeImage"] = ReceptionHost.appearanceValues["closeImage"]
      }
    }
    if let icon = values["welcomeIcon"] as? [String: Any] {
      if icon["hidden"] as? Bool == true {
        style.welcomeIcon = .hidden
      } else if let symbol = icon["symbol"] as? String, UIImage(systemName: symbol) != nil {
        style.welcomeIcon = .symbol(symbol)
      } else if let name = icon["image"] as? String, let image = UIImage(named: name) {
        style.welcomeIcon = .image(Image(uiImage: image))
      } else {
        logger.error("Missing welcome icon ignored")
        style.welcomeIcon = Reception.shared.appearance.welcomeIcon
        accepted["welcomeIcon"] = ReceptionHost.appearanceValues["welcomeIcon"]
      }
    }
    ReceptionHost.appearanceValues = accepted
    Reception.shared.appearance = style
  }
}
