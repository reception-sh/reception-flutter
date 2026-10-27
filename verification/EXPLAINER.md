# Reception in Flutter – einfach erklärt

Flutter baut iPhone- und Android-Apps mit der Sprache Dart. Reception ergänzt darin **denselben nativen iOS-Chat wie in einer Swift-App**. Nachrichten, Fotos und Darstellung bleiben im Swift-SDK, das im Plugin `reception_flutter` fest mitgeliefert wird. Eine kleine Dart-Schicht verbindet es mit der App.

**Was müssen Kunden tun?** Drei Schritte:

1. `flutter pub add reception_flutter` ausführen und das iOS-Mindestziel der App auf 17.0 stellen. Swift Package Manager (Flutters Standard) und CocoaPods funktionieren beide, ohne die Podfile anzufassen.
2. Einmal in `main()` `await Reception.configure(appId: '…')` mit der öffentlichen App ID aufrufen.
3. Den vorhandenen Support-Button mit `Reception.openChat()` verbinden. Farben folgen dem App-Design; `Reception.unreadCount` liefert die Zahl ungelesener Antworten für ein Badge.

**Push:** Das Plugin registriert den Apple-Gerätetoken selbst, zeigt Reception-Banner nur bei geschlossenem Chat und öffnet beim Antippen den Chat – auch wenn die App vorher beendet war. Es fragt nie selbst nach Erlaubnis; die App behält ihre Abfrage und ruft danach `Reception.registerForPushIfAuthorized()` auf. Benachrichtigungen anderer Dienste (z. B. Firebase) laufen unverändert weiter.

**Hot Restart:** Beim Entwickeln startet Flutter den Dart-Code neu, der native Chat läuft weiter. Ungelesen-Zähler, Konfiguration und Einstellungen werden danach wieder aus dem nativen Teil gelesen.

**Nur iOS:** Unter Android und im Web passiert nichts; die Werte bleiben leer bzw. null.

**Geprüft (27.10.2026, Flutter 3.47.8, Xcode 26.5, iPhone-17-Pro-Simulator, lokales Backend):** automatische Dart- und Swift-Tests, Paketprüfungen, frische Simulator-Builds mit Swift Package Manager und CocoaPods, der Setup-Check des SDK, Antworten aus dem Dashboard mit Ungelesen-Badge, Name/E-Mail/Metadaten in der Dashboard-Ansicht, Paywall-Filter (nur `plans` wird angeboten, auch im Dashboard-Dialog), eine Angebotskarte aus dem Dashboard, deren Antippen die App-Paywall-Funktion aufruft, während der Chat offen bleibt, der Apple-Gerätetoken im Simulator, Push im Vordergrund, bei offenem Chat, im Hintergrund und beim Kaltstart, Deutsch über die Gerätesprache und über die Sprachwahl in der App, Hell/Dunkel, eingebetteter Chat, Daten löschen, Abmelden und Hot Restart. Eine frisch angelegte Flutter-App ließ sich mit beiden Paketsystemen bauen; nötig war nur das Mindestziel 17.0.

**Gefunden:**
- In der ersten Runde fehlte das Paket `meta` in `pubspec.yaml`, und ein Prüfskript brauchte eine UTF-8-Spracheinstellung. Beides ist behoben; die Paketprüfung meldet jetzt 0 Warnungen.
- Flutter-Apps müssen ihre Sprachen in der iOS-`Info.plist` eintragen (`CFBundleLocalizations`), sonst bleibt der Chat trotz deutscher Gerätesprache englisch. Das verlangt auch Flutters eigene Anleitung; unsere Doku sollte es erwähnen.

**Nicht geprüft:** die Bewertungskarte (das Dashboard verlangt dafür eine App-Store-ID, die die Test-App nicht hat), echte Push-Zustellung vom Server auf ein iPhone (Pushes wurden im Simulator nachgestellt), Fotos senden und Release-Builds.

[Anleitung](https://reception.sh/docs/flutter) · [Befehle und Ergebnisse](commands.txt) · [Screenshots](screenshots.txt)
