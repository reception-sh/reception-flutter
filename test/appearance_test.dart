import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reception_flutter/reception_flutter.dart';
import 'package:reception_flutter/src/appearance.dart'
    show appearanceFromJson, validateAppearance;

import 'fake_host.dart';

void main() {
  const all = Appearance(
    accentColor: AppearanceColor.hex('#ff8800'),
    onAccentColor: AppearanceColor.hex('#ffffff80'),
    title: '',
    welcomeTitle: 'Hello',
    welcomeText: 'Welcome',
    showsCloseButton: true,
    chatBackground: AppearanceColor.adaptive(
      light: '#123456',
      dark: '#abcdef80',
    ),
    incomingBackground: AppearanceColor.hex('#eeeeee'),
    incomingForeground: AppearanceColor.hex('#000000'),
    preferredColorScheme: PreferredColorScheme.dark,
    closeIcon: CloseIcon.chevronDown,
    closeImage: 'Close',
    fontDesign: FontDesign.rounded,
    fontFamily: 'Avenir',
    fadesOlderMessages: false,
    welcomeIcon: WelcomeIcon.symbol('star'),
    welcomeIconColor: AppearanceColor.hex('#aa00bb'),
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
    expect(const Appearance().toJson(), isEmpty);
    expect(logs, isEmpty);
  });

  test('every enum and welcome icon variant maps to its native value', () {
    expect(
      [
        for (final icon in CloseIcon.values)
          Appearance(closeIcon: icon).toJson()['closeIcon'],
      ],
      ['xmark', 'chevron.down', 'arrow.down'],
    );
    expect(
      [
        for (final design in FontDesign.values)
          Appearance(fontDesign: design).toJson()['fontDesign'],
      ],
      ['default', 'rounded', 'serif', 'monospaced'],
    );
    expect(
      [
        for (final icon in [
          const WelcomeIcon.symbol('star'),
          const WelcomeIcon.image('Welcome'),
          WelcomeIcon.hidden,
        ])
          Appearance(welcomeIcon: icon).toJson()['welcomeIcon'],
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
      welcomeIcon: WelcomeIcon.hidden,
    );
    expect(copy.toJson(), {
      ...allJson,
      'title': 'Support',
      'welcomeIcon': {'hidden': true},
    });
  });

  for (final value in <Appearance>[
    const Appearance(accentColor: AppearanceColor.hex('red')),
    const Appearance(accentColor: AppearanceColor.hex('#fff')),
    const Appearance(onAccentColor: AppearanceColor.hex('#gggggg')),
    const Appearance(welcomeIconSize: double.nan),
    const Appearance(welcomeIconSize: 161),
    const Appearance(welcomeIconSize: 15),
    const Appearance(welcomeIconCornerRadius: -1),
    const Appearance(welcomeIconCornerRadius: 81),
    const Appearance(welcomeIconOffset: Offset(double.infinity, 0)),
  ]) {
    test('invalid field is logged and ignored: ${value.toJson()}', () {
      expect(validateAppearance(value.toJson(), {}), isEmpty);
      expect(logs, hasLength(1));
    });
  }

  test('range limits are inclusive', () {
    const limits = Appearance(welcomeIconSize: 16, welcomeIconCornerRadius: 80);
    expect(validateAppearance(limits.toJson(), {}), limits.toJson());
    expect(
      validateAppearance(
        const Appearance(
          welcomeIconSize: 160,
          welcomeIconCornerRadius: 0,
        ).toJson(),
        {},
      ),
      hasLength(2),
    );
  });

  test('invalid replacement retains that field while omitted fields reset', () {
    final previous = const Appearance(
      accentColor: AppearanceColor.hex('#112233'),
      title: 'Old',
    ).toJson();
    expect(
      validateAppearance(
        const Appearance(accentColor: AppearanceColor.hex('bad')).toJson(),
        previous,
      ),
      {'accentColor': '#112233'},
    );
    expect(validateAppearance({}, previous), isEmpty);
  });

  test('all six color options accept light/dark hex pairs', () {
    const pair = AppearanceColor.adaptive(light: '#123456', dark: '#ABCDEF80');
    const value = Appearance(
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
    const AppearanceColor.adaptive(light: '#112233', dark: 'red'),
    const AppearanceColor.adaptive(light: '#12', dark: '#445566'),
  ]) {
    test(
      'invalid adaptive color retains the previous complete pair: ${pair.light}/${pair.dark}',
      () {
        final previous = const Appearance(
          accentColor: AppearanceColor.adaptive(
            light: '#abcdef',
            dark: '#123456',
          ),
        ).toJson();
        expect(
          validateAppearance(Appearance(accentColor: pair).toJson(), previous),
          previous,
        );
        expect(logs, ['[Reception] Invalid appearance.accentColor; ignored.']);
      },
    );
  }

  test('Flutter colors serialize to opaque or translucent hex', () {
    expect(
      Appearance(
        accentColor: AppearanceColor.of(const Color(0xFFFF8800)),
      ).toJson(),
      {'accentColor': '#ff8800'},
    );
    expect(
      Appearance(
        chatBackground: AppearanceColor.adaptiveOf(
          light: const Color(0x80FFFFFF),
          dark: const Color(0x00010203),
        ),
      ).toJson(),
      {
        'chatBackground': {'light': '#ffffff80', 'dark': '#01020300'},
      },
    );
    final json = Appearance(
      accentColor: AppearanceColor.of(const Color.fromARGB(255, 18, 52, 86)),
      onAccentColor: AppearanceColor.adaptiveOf(
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
}
