# Reception in Flutter – einfach erklärt

Flutter baut iPhone- und Android-Apps mit der Sprache Dart. Reception ergänzt darin **denselben nativen iOS-Chat wie in einer Swift-App**. Nachrichten, Fotos und Darstellung bleiben im Swift-SDK, das im Plugin `reception_flutter` fest mitgeliefert wird. Eine kleine Dart-Schicht verbindet es mit der App.

**Was müssen Kunden tun?** Drei Schritte:

1. `flutter pub add reception_flutter` ausführen und das iOS-Mindestziel der App auf 17.0 stellen. Swift Package Manager (Flutters Standard) und CocoaPods funktionieren beide, ohne die Podfile anzufassen.
2. Einmal in `main()` `await Reception.configure(appId: '…')` mit der öffentlichen App ID aufrufen.
3. Den vorhandenen Support-Button mit `Reception.openChat()` verbinden. Farben folgen dem App-Design; `Reception.unreadCount` liefert die Zahl ungelesener Antworten für ein Badge.

**Push:** Das Plugin registriert den Apple-Gerätetoken selbst, zeigt Reception-Banner nur bei geschlossenem Chat und öffnet beim Antippen den Chat – auch wenn die App vorher beendet war. Es fragt nie selbst nach Erlaubnis; die App behält ihre Abfrage und ruft danach `Reception.registerForPushIfAuthorized()` auf. Benachrichtigungen anderer Dienste (z. B. Firebase) laufen unverändert weiter.

**Hot Restart:** Beim Entwickeln startet Flutter den Dart-Code neu, der native Chat läuft weiter. Ungelesen-Zähler, Konfiguration und Einstellungen werden danach wieder aus dem nativen Teil gelesen.

**Nur iOS:** Unter Android und im Web passiert nichts; die Werte bleiben leer bzw. null.

**Geprüft (Schlussrunde am 28.10.2026, 13:29–14:02 Uhr, auf dem endgültigen Plugin-Code; Flutter 3.47.8, Xcode 26.5, iPhone-17-Pro-Simulator, lokales Backend):** alle automatischen Prüfungen (60 Dart-Tests, Swift-Tests in der Beispiel-App, Paketprüfung ohne Warnungen), frische Simulator-Builds mit Swift Package Manager und CocoaPods, der Setup-Check des SDK, Antworten aus dem Dashboard mit Ungelesen-Badge, Name/E-Mail/Metadaten in der Dashboard-Ansicht, Paywall-Filter (nur `plans` wird angeboten), Angebotskarte aus dem Dashboard (Antippen ruft die Paywall-Funktion der App auf, der Chat bleibt offen), Bewertungskarte (das Antippen wird gemeldet), Apple-Gerätetoken im Simulator, Push im Vordergrund, bei offenem Chat, im Hintergrund und beim Kaltstart – dort öffnet sich der Chat bereits im App-Design – und ein zweiter Push kurz danach öffnet den Chat erneut, Deutsch über die Gerätesprache und über die Sprachwahl in der App, Hell/Dunkel, eingebetteter Chat, Daten löschen, Abmelden und Hot Restart. Eine frisch angelegte Flutter-App ließ sich mit beiden Paketsystemen bauen; nötig war nur das Mindestziel 17.0.

**Gefunden:**
- In der ersten Runde fehlte das Paket `meta` in `pubspec.yaml`, und ein Prüfskript brauchte eine UTF-8-Spracheinstellung. Beides ist behoben.
- Flutter-Apps müssen ihre Sprachen in der iOS-`Info.plist` eintragen (`CFBundleLocalizations`), sonst bleibt der Chat trotz deutscher Gerätesprache englisch. Das verlangt auch Flutters eigene Anleitung; unsere Doku sollte es erwähnen.

**Zusatzrunde (29.10.2026):** Auch geprüft sind jetzt Fotos senden (bis zu fünf, im Chat und im Dashboard), die Grenzen für Nachrichtenmenge, Länge und Fotoanzahl (die App zeigt jeweils einen Hinweis und sendet danach weiter), der eingebettete Chat mit eingeblendeter Tastatur, ein vom Server abgelehnter Identitäts-Token und ein korrekt signierter (im Dashboard „verifiziert“), eine Automation, die den Chat öffnet, das iPad, Web und macOS (dort ohne Wirkung), ein Paket-Abbild in einer frischen App, sowie das Zusammenspiel mit Firebase Messaging und flutter_local_notifications: Banner, Antippen und deren eigene Benachrichtigungen funktionieren weiter.

**Version 1.1 (31.10.2026, SDK 1.7):** Link-Karten aus dem Dashboard öffnen Webseiten in einem Safari-Fenster über dem Chat (oder, abgeschaltet, in Safari selbst), die iOS-Einstellungen der App und Bildschirme der eigenen App („settings“, „order“ mit Bestellnummer) – der Chat schließt sich vorher, das Dashboard zeigt, ob der Link geöffnet wurde. Die neue Karte „Benachrichtigungen erlauben“ im Chat funktioniert, erscheint aber nur, wenn die App das Dashboard-Design nicht abschaltet (`usesRemoteAppearance`); das ist als Fund in STATUS.md vermerkt. Push, Integrationstest und alle automatischen Prüfungen laufen weiter fehlerfrei.

**Nicht geprüft:** echte Push-Zustellung vom Server auf ein iPhone im Simulator-Ablauf (Pushes wurden nachgestellt; ein separater Gerätetest ist in STATUS.md vermerkt), das App-Store-Bewertungsfenster selbst (im Simulator gibt es keinen App Store) und ältere Flutter-Versionen als 3.47 (Mindestversion ist 3.44).

[Anleitung](https://reception.sh/docs/flutter) · [Befehle und Ergebnisse](commands.txt) · [Screenshots](screenshots.txt)
