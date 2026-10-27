import 'dart:convert';

import 'dart:ui' show Color, ColorSpace;
import 'package:flutter_test/flutter_test.dart';
import 'package:reception_flutter/reception_flutter.dart';
import 'package:reception_flutter/src/appearance.dart'
    show appearanceFromJson, validateAppearance;

import 'fake_host.dart';

void main() {
  const all = ReceptionAppearance(
    accentColor: ReceptionColor.hex('#ff8800'),
    onAccentColor: ReceptionColor.hex('#ffffff80'),
    title: '',
    welcomeTitle: 'Hello',
    welcomeText: 'Welcome',
    showsCloseButton: true,
    chatBackground: ReceptionColor.adaptive(
      light: '#123456',
      dark: '#abcdef80',
    ),
    incomingBackground: ReceptionColor.hex('#eeeeee'),
    incomingForeground: ReceptionColor.hex('#000000'),
    preferredColorScheme: ReceptionColorScheme.dark,
    closeIcon: ReceptionCloseIcon.chevronDown,
    closeImage: 'Close',
    fontDesign: ReceptionFontDesign.rounded,
    fontFamily: 'Avenir',
    fadesOlderMessages: false,
    welcomeIcon: ReceptionWelcomeIcon.symbol('star'),
    welcomeIconColor: ReceptionColor.hex('#aa00bb'),
    welcomeIconSize: 80,
    welcomeIconCornerRadius: 20,
    welcomeIconOffset: Offset(3, -5),
    hidesTitle: true,
    hidesWelcomeTitle: false,
    hidesWelcomeText: true,
  );
  const allJson = {
    'accentColor': '#ff8800',
    'onAccentColor': '#ffffff80',
    'title': '',
    'welcomeTitle': 'Hello',
    'welcomeText': 'Welcome',
    'showsCloseButton': true,
    'chatBackground': {'light': '#123456', 'dark': '#abcdef80'},
    'incomingBackground': '#eeeeee',
    'incomingForeground': '#000000',
    'preferredColorScheme': 'dark',
    'closeIcon': 'chevron.down',
    'closeImage': 'Close',
    'fontDesign': 'rounded',
    'fontFamily': 'Avenir',
    'fadesOlderMessages': false,
    'welcomeIcon': {'symbol': 'star'},
    'welcomeIconColor': '#aa00bb',
    'welcomeIconSize': 80.0,
    'welcomeIconCornerRadius': 20.0,
    'welcomeIconOffset': {'x': 3.0, 'y': -5.0},
    'hidesTitle': true,
    'hidesWelcomeTitle': false,
    'hidesWelcomeText': true,
  };

  late List<String> logs;
  setUp(() => logs = captureLogs());

  test('all 23 options produce the native JSON shape and round trip', () {
    expect(allJson, hasLength(23));
    expect(all.toJson(), allJson);
    expect(validateAppearance(all.toJson(), {}), allJson);
    expect(appearanceFromJson(allJson).toJson(), allJson);
    final decoded = jsonDecode(jsonEncode(allJson)) as Map<String, Object?>;
    expect(appearanceFromJson(decoded).toJson(), allJson);
    expect(const ReceptionAppearance().toJson(), isEmpty);
    expect(logs, isEmpty);
  });

  test('every enum and welcome icon variant maps to its native value', () {
    expect(
      [
        for (final icon in ReceptionCloseIcon.values)
          ReceptionAppearance(closeIcon: icon).toJson()['closeIcon'],
      ],
      ['xmark', 'chevron.down', 'arrow.down'],
    );
    expect(
      [
        for (final design in ReceptionFontDesign.values)
          ReceptionAppearance(fontDesign: design).toJson()['fontDesign'],
      ],
      ['default', 'rounded', 'serif', 'monospaced'],
    );
    expect(
      [
        for (final icon in [
          const ReceptionWelcomeIcon.symbol('star'),
          const ReceptionWelcomeIcon.image('Welcome'),
          ReceptionWelcomeIcon.hidden,
        ])
          ReceptionAppearance(welcomeIcon: icon).toJson()['welcomeIcon'],
      ],
      [
        {'symbol': 'star'},
        {'image': 'Welcome'},
        {'hidden': true},
      ],
    );
    for (final json in [
      {
        'closeIcon': 'arrow.down',
        'fontDesign': 'default',
        'preferredColorScheme': 'light',
      },
      {
        'welcomeIcon': {'image': 'Welcome'},
      },
      {
        'welcomeIcon': {'hidden': true},
      },
    ]) {
      expect(appearanceFromJson(json).toJson(), json);
    }
  });

  test('native nulls and unknown values read as unset', () {
    expect(
      appearanceFromJson({
        'chatBackground': null,
        'closeIcon': 'unknown',
        'welcomeIconSize': 'big',
        'extra': true,
      }).toJson(),
      isEmpty,
    );
  });

  test('copyWith replaces only the given fields', () {
    final copy = all.copyWith(
      title: 'Support',
      welcomeIcon: ReceptionWelcomeIcon.hidden,
    );
    expect(copy.toJson(), {
      ...allJson,
      'title': 'Support',
      'welcomeIcon': {'hidden': true},
    });
  });

  for (final value in <ReceptionAppearance>[
    const ReceptionAppearance(accentColor: ReceptionColor.hex('red')),
    const ReceptionAppearance(accentColor: ReceptionColor.hex('#fff')),
    const ReceptionAppearance(onAccentColor: ReceptionColor.hex('#gggggg')),
    const ReceptionAppearance(welcomeIconSize: double.nan),
    const ReceptionAppearance(welcomeIconSize: 161),
    const ReceptionAppearance(welcomeIconSize: 15),
    const ReceptionAppearance(welcomeIconCornerRadius: -1),
    const ReceptionAppearance(welcomeIconCornerRadius: 81),
    const ReceptionAppearance(welcomeIconOffset: Offset(double.infinity, 0)),
  ]) {
    test('invalid field is logged and ignored: ${value.toJson()}', () {
      expect(validateAppearance(value.toJson(), {}), isEmpty);
      expect(logs, hasLength(1));
    });
  }

  test('range limits are inclusive', () {
    const limits = ReceptionAppearance(
      welcomeIconSize: 16,
      welcomeIconCornerRadius: 80,
    );
    expect(validateAppearance(limits.toJson(), {}), limits.toJson());
    expect(
      validateAppearance(
        const ReceptionAppearance(
          welcomeIconSize: 160,
          welcomeIconCornerRadius: 0,
        ).toJson(),
        {},
      ),
      hasLength(2),
    );
  });

  test('invalid replacement retains that field while omitted fields reset', () {
    final previous = const ReceptionAppearance(
      accentColor: ReceptionColor.hex('#112233'),
      title: 'Old',
    ).toJson();
    expect(
      validateAppearance(
        const ReceptionAppearance(
          accentColor: ReceptionColor.hex('bad'),
        ).toJson(),
        previous,
      ),
      {'accentColor': '#112233'},
    );
    expect(validateAppearance({}, previous), isEmpty);
  });

  test('all six color options accept light/dark hex pairs', () {
    const pair = ReceptionColor.adaptive(light: '#123456', dark: '#ABCDEF80');
    const value = ReceptionAppearance(
      accentColor: pair,
      onAccentColor: pair,
      chatBackground: pair,
      incomingBackground: pair,
      incomingForeground: pair,
      welcomeIconColor: pair,
    );
    expect(validateAppearance(value.toJson(), {}), value.toJson());
    expect(
      value.toJson().values,
      everyElement({'light': '#123456', 'dark': '#ABCDEF80'}),
    );
  });

  for (final pair in [
    const ReceptionColor.adaptive(light: '#112233', dark: 'red'),
    const ReceptionColor.adaptive(light: '#12', dark: '#445566'),
  ]) {
    test(
      'invalid adaptive color retains the previous complete pair: ${pair.light}/${pair.dark}',
      () {
        final previous = const ReceptionAppearance(
          accentColor: ReceptionColor.adaptive(
            light: '#abcdef',
            dark: '#123456',
          ),
        ).toJson();
        expect(
          validateAppearance(
            ReceptionAppearance(accentColor: pair).toJson(),
            previous,
          ),
          previous,
        );
        expect(logs, ['[Reception] Invalid appearance.accentColor; ignored.']);
      },
    );
  }

  test('Flutter colors serialize to opaque or translucent hex', () {
    expect(
      ReceptionAppearance(
        accentColor: ReceptionColor.of(const Color(0xFFFF8800)),
      ).toJson(),
      {'accentColor': '#ff8800'},
    );
    expect(
      ReceptionAppearance(
        chatBackground: ReceptionColor.adaptiveOf(
          light: const Color(0x80FFFFFF),
          dark: const Color(0x00010203),
        ),
      ).toJson(),
      {
        'chatBackground': {'light': '#ffffff80', 'dark': '#01020300'},
      },
    );
    final json = ReceptionAppearance(
      accentColor: ReceptionColor.of(const Color.fromARGB(255, 18, 52, 86)),
      onAccentColor: ReceptionColor.adaptiveOf(
        light: const Color(0xFF000000),
        dark: const Color(0x33ABCDEF),
      ),
    ).toJson();
    expect(json, {
      'accentColor': '#123456',
      'onAccentColor': {'light': '#000000', 'dark': '#abcdef33'},
    });
    expect(validateAppearance(json, {}), json);
    expect(appearanceFromJson(json).toJson(), json);
    expect(logs, isEmpty);
  });

  test('Flutter colors convert to sRGB and clamp out-of-range components', () {
    final p3Red = Color.from(
      alpha: 1,
      red: 1,
      green: 0,
      blue: 0,
      colorSpace: ColorSpace.displayP3,
    );
    final extended = Color.from(
      alpha: 0.5,
      red: 1.5,
      green: -0.2,
      blue: 0.5,
      colorSpace: ColorSpace.extendedSRGB,
    );
    final json = ReceptionAppearance(
      accentColor: ReceptionColor.of(p3Red),
      chatBackground: ReceptionColor.adaptiveOf(light: extended, dark: p3Red),
    ).toJson();
    expect(json, {
      'accentColor': '#ff0000',
      'chatBackground': {'light': '#ff008080', 'dark': '#ff0000'},
    });
    expect(validateAppearance(json, {}), json);
  });
}
