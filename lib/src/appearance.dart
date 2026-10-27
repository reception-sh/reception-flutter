import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'platform.dart';

/// A chat color: one hex value, or a light/dark pair that follows the native
/// color scheme. Hex values are `#RRGGBB` or `#RRGGBBAA`.
@immutable
class AppearanceColor {
  /// One color for both color schemes.
  const AppearanceColor.hex(String hex)
    : light = hex,
      dark = hex,
      _adaptive = false;

  /// Separate colors for light and dark mode.
  const AppearanceColor.adaptive({required this.light, required this.dark})
    : _adaptive = true;

  /// One Flutter [color] for both color schemes.
  AppearanceColor.of(Color color) : this.hex(_hexOf(color));

  /// Separate Flutter colors for light and dark mode.
  AppearanceColor.adaptiveOf({required Color light, required Color dark})
    : this.adaptive(light: _hexOf(light), dark: _hexOf(dark));

  /// Hex value used in light mode.
  final String light;

  /// Hex value used in dark mode.
  final String dark;

  final bool _adaptive;

  Object _toJson() => _adaptive ? {'light': light, 'dark': dark} : light;

  /// `#RRGGBB` for opaque colors, otherwise `#RRGGBBAA`.
  static String _hexOf(Color color) {
    String byte(double component) =>
        (component * 255).round().toRadixString(16).padLeft(2, '0');
    final rgb = '#${byte(color.r)}${byte(color.g)}${byte(color.b)}';
    final alpha = byte(color.a);
    return alpha == 'ff' ? rgb : '$rgb$alpha';
  }
}

/// The icon above the welcome heading in an empty chat.
@immutable
class WelcomeIcon {
  /// An SF Symbol, for example `star`.
  const WelcomeIcon.symbol(String name) : _key = 'symbol', _value = name;

  /// An image from the host app's iOS asset catalog (not a Flutter asset).
  const WelcomeIcon.image(String name) : _key = 'image', _value = name;

  const WelcomeIcon._hidden() : _key = 'hidden', _value = true;

  /// No welcome icon.
  static const hidden = WelcomeIcon._hidden();

  final String _key;
  final Object _value;

  Map<String, Object> _toJson() => {_key: _value};
}

/// Symbol of the presented chat's close button.
enum CloseIcon {
  /// A cross (default).
  xmark('xmark'),

  /// A downward chevron.
  chevronDown('chevron.down'),

  /// A downward arrow.
  arrowDown('arrow.down');

  const CloseIcon(this._json);
  final String _json;
}

/// System font design of the chat.
enum FontDesign {
  /// The standard system design (Swift `.default`).
  standard('default'),

  /// Rounded.
  rounded('rounded'),

  /// Serif.
  serif('serif'),

  /// Monospaced.
  monospaced('monospaced');

  const FontDesign(this._json);
  final String _json;
}

/// Color scheme forced on the chat; leave unset to follow the app.
enum PreferredColorScheme {
  /// Always light.
  light,

  /// Always dark.
  dark,
}

/// Local chat styling. Assign a complete value to `Reception.appearance`:
/// unset (null) fields use the Swift SDK defaults, and invalid fields log and
/// keep their previous value. Published dashboard appearance overrides these
/// values unless `Reception.usesRemoteAppearance` is false.
@immutable
class Appearance {
  /// Creates an appearance; every field is optional.
  const Appearance({
    this.accentColor,
    this.onAccentColor,
    this.title,
    this.welcomeTitle,
    this.welcomeText,
    this.showsCloseButton,
    this.chatBackground,
    this.incomingBackground,
    this.incomingForeground,
    this.preferredColorScheme,
    this.closeIcon,
    this.closeImage,
    this.fontDesign,
    this.fontFamily,
    this.fadesOlderMessages,
    this.welcomeIcon,
    this.welcomeIconColor,
    this.welcomeIconSize,
    this.welcomeIconCornerRadius,
    this.welcomeIconOffset,
    this.hidesTitle,
    this.hidesWelcomeTitle,
    this.hidesWelcomeText,
  });

  /// Outgoing bubble fills and accented controls.
  final AppearanceColor? accentColor;

  /// Text and symbols on accent surfaces.
  final AppearanceColor? onAccentColor;

  /// Navigation title at the top of the chat.
  final String? title;

  /// Heading shown in an empty chat.
  final String? welcomeTitle;

  /// Supporting text below the welcome heading.
  final String? welcomeText;

  /// Whether the presented chat shows a close button.
  final bool? showsCloseButton;

  /// Background behind the conversation.
  final AppearanceColor? chatBackground;

  /// Incoming bubble, review card and paywall card fills.
  final AppearanceColor? incomingBackground;

  /// Incoming message text and review/paywall card body text.
  final AppearanceColor? incomingForeground;

  /// Forces light or dark mode; null follows the app.
  final PreferredColorScheme? preferredColorScheme;

  /// Close button symbol.
  final CloseIcon? closeIcon;

  /// Close button image: a name from the host app's iOS asset catalog.
  final String? closeImage;

  /// System font design.
  final FontDesign? fontDesign;

  /// Font family name registered with iOS (Flutter `pubspec.yaml` fonts are
  /// not available to UIKit).
  final String? fontFamily;

  /// Whether older outgoing text bubbles use lighter fills.
  final bool? fadesOlderMessages;

  /// Symbol, image, or no icon above the welcome heading.
  final WelcomeIcon? welcomeIcon;

  /// Color of a welcome icon symbol.
  final AppearanceColor? welcomeIconColor;

  /// Welcome icon size in points, 16 to 160.
  final double? welcomeIconSize;

  /// Corner radius of welcome images in points, 0 to 80.
  final double? welcomeIconCornerRadius;

  /// Welcome icon position offset in points.
  final Offset? welcomeIconOffset;

  /// Hides the navigation title.
  final bool? hidesTitle;

  /// Hides the welcome heading.
  final bool? hidesWelcomeTitle;

  /// Hides the welcome text.
  final bool? hidesWelcomeText;

  /// Returns a copy with the given fields replaced.
  Appearance copyWith({
    AppearanceColor? accentColor,
    AppearanceColor? onAccentColor,
    String? title,
    String? welcomeTitle,
    String? welcomeText,
    bool? showsCloseButton,
    AppearanceColor? chatBackground,
    AppearanceColor? incomingBackground,
    AppearanceColor? incomingForeground,
    PreferredColorScheme? preferredColorScheme,
    CloseIcon? closeIcon,
    String? closeImage,
    FontDesign? fontDesign,
    String? fontFamily,
    bool? fadesOlderMessages,
    WelcomeIcon? welcomeIcon,
    AppearanceColor? welcomeIconColor,
    double? welcomeIconSize,
    double? welcomeIconCornerRadius,
    Offset? welcomeIconOffset,
    bool? hidesTitle,
    bool? hidesWelcomeTitle,
    bool? hidesWelcomeText,
  }) => Appearance(
    accentColor: accentColor ?? this.accentColor,
    onAccentColor: onAccentColor ?? this.onAccentColor,
    title: title ?? this.title,
    welcomeTitle: welcomeTitle ?? this.welcomeTitle,
    welcomeText: welcomeText ?? this.welcomeText,
    showsCloseButton: showsCloseButton ?? this.showsCloseButton,
    chatBackground: chatBackground ?? this.chatBackground,
    incomingBackground: incomingBackground ?? this.incomingBackground,
    incomingForeground: incomingForeground ?? this.incomingForeground,
    preferredColorScheme: preferredColorScheme ?? this.preferredColorScheme,
    closeIcon: closeIcon ?? this.closeIcon,
    closeImage: closeImage ?? this.closeImage,
    fontDesign: fontDesign ?? this.fontDesign,
    fontFamily: fontFamily ?? this.fontFamily,
    fadesOlderMessages: fadesOlderMessages ?? this.fadesOlderMessages,
    welcomeIcon: welcomeIcon ?? this.welcomeIcon,
    welcomeIconColor: welcomeIconColor ?? this.welcomeIconColor,
    welcomeIconSize: welcomeIconSize ?? this.welcomeIconSize,
    welcomeIconCornerRadius:
        welcomeIconCornerRadius ?? this.welcomeIconCornerRadius,
    welcomeIconOffset: welcomeIconOffset ?? this.welcomeIconOffset,
    hidesTitle: hidesTitle ?? this.hidesTitle,
    hidesWelcomeTitle: hidesWelcomeTitle ?? this.hidesWelcomeTitle,
    hidesWelcomeText: hidesWelcomeText ?? this.hidesWelcomeText,
  );

  /// The JSON object the native parser reads; unset fields are omitted.
  Map<String, Object> toJson() => {
    'accentColor': ?accentColor?._toJson(),
    'onAccentColor': ?onAccentColor?._toJson(),
    'title': ?title,
    'welcomeTitle': ?welcomeTitle,
    'welcomeText': ?welcomeText,
    'showsCloseButton': ?showsCloseButton,
    'chatBackground': ?chatBackground?._toJson(),
    'incomingBackground': ?incomingBackground?._toJson(),
    'incomingForeground': ?incomingForeground?._toJson(),
    'preferredColorScheme': ?preferredColorScheme?.name,
    'closeIcon': ?closeIcon?._json,
    'closeImage': ?closeImage,
    'fontDesign': ?fontDesign?._json,
    'fontFamily': ?fontFamily,
    'fadesOlderMessages': ?fadesOlderMessages,
    'welcomeIcon': ?welcomeIcon?._toJson(),
    'welcomeIconColor': ?welcomeIconColor?._toJson(),
    'welcomeIconSize': ?welcomeIconSize,
    'welcomeIconCornerRadius': ?welcomeIconCornerRadius,
    if (welcomeIconOffset case final offset?)
      'welcomeIconOffset': {'x': offset.dx, 'y': offset.dy},
    'hidesTitle': ?hidesTitle,
    'hidesWelcomeTitle': ?hidesWelcomeTitle,
    'hidesWelcomeText': ?hidesWelcomeText,
  };
}

/// Reads an appearance from the native JSON shape, skipping unknown values.
Appearance appearanceFromJson(Map<String, Object?> json) {
  AppearanceColor? color(String key) => switch (json[key]) {
    final String hex => AppearanceColor.hex(hex),
    {'light': final String light, 'dark': final String dark} =>
      AppearanceColor.adaptive(light: light, dark: dark),
    _ => null,
  };
  T? value<T>(String key) => switch (json[key]) {
    final T value => value,
    _ => null,
  };
  double? number(String key) => value<num>(key)?.toDouble();

  return Appearance(
    accentColor: color('accentColor'),
    onAccentColor: color('onAccentColor'),
    title: value('title'),
    welcomeTitle: value('welcomeTitle'),
    welcomeText: value('welcomeText'),
    showsCloseButton: value('showsCloseButton'),
    chatBackground: color('chatBackground'),
    incomingBackground: color('incomingBackground'),
    incomingForeground: color('incomingForeground'),
    preferredColorScheme: PreferredColorScheme.values
        .where((scheme) => scheme.name == json['preferredColorScheme'])
        .firstOrNull,
    closeIcon: CloseIcon.values
        .where((icon) => icon._json == json['closeIcon'])
        .firstOrNull,
    closeImage: value('closeImage'),
    fontDesign: FontDesign.values
        .where((design) => design._json == json['fontDesign'])
        .firstOrNull,
    fontFamily: value('fontFamily'),
    fadesOlderMessages: value('fadesOlderMessages'),
    welcomeIcon: switch (json['welcomeIcon']) {
      {'symbol': final String name} => WelcomeIcon.symbol(name),
      {'image': final String name} => WelcomeIcon.image(name),
      {'hidden': true} => WelcomeIcon.hidden,
      _ => null,
    },
    welcomeIconColor: color('welcomeIconColor'),
    welcomeIconSize: number('welcomeIconSize'),
    welcomeIconCornerRadius: number('welcomeIconCornerRadius'),
    welcomeIconOffset: switch (json['welcomeIconOffset']) {
      {'x': final num x, 'y': final num y} => Offset(
        x.toDouble(),
        y.toDouble(),
      ),
      _ => null,
    },
    hidesTitle: value('hidesTitle'),
    hidesWelcomeTitle: value('hidesWelcomeTitle'),
    hidesWelcomeText: value('hidesWelcomeText'),
  );
}

final _hex = RegExp(r'^#[\da-f]{6}([\da-f]{2})?$', caseSensitive: false);

bool _color(Object? value) => switch (value) {
  final String hex => _hex.hasMatch(hex),
  {'light': final String light, 'dark': final String dark} =>
    _hex.hasMatch(light) && _hex.hasMatch(dark),
  _ => false,
};

bool Function(Object?) _range(double min, double max) =>
    (value) =>
        value is double && value.isFinite && value >= min && value <= max;

// Only fields whose Dart type admits invalid values need a runtime check.
final Map<String, bool Function(Object?)> _validators = {
  'accentColor': _color,
  'onAccentColor': _color,
  'chatBackground': _color,
  'incomingBackground': _color,
  'incomingForeground': _color,
  'welcomeIconColor': _color,
  'welcomeIconSize': _range(16, 160),
  'welcomeIconCornerRadius': _range(0, 80),
  'welcomeIconOffset': (value) => switch (value) {
    {'x': final double x, 'y': final double y} => x.isFinite && y.isFinite,
    _ => false,
  },
};

/// Validates [value] (from [Appearance.toJson]). Invalid fields log and keep
/// their [previous] value instead of resetting a working customization.
Map<String, Object> validateAppearance(
  Map<String, Object> value,
  Map<String, Object> previous,
) {
  final result = <String, Object>{};
  for (final MapEntry(:key, value: entry) in value.entries) {
    if (_validators[key]?.call(entry) ?? true) {
      result[key] = entry;
    } else {
      warnInvalid('appearance.$key');
      if (previous[key] case final kept?) result[key] = kept;
    }
  }
  return result;
}
