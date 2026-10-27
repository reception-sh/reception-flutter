# Reception in Flutter – einfach erklärt

Flutter baut iPhone- und Android-Apps mit der Sprache Dart. Reception ergänzt darin **denselben nativen iOS-Chat wie in einer Swift-App**. Nachrichten, Fotos und Darstellung bleiben im Swift-SDK, das im Plugin `reception_flutter` fest mitgeliefert wird. Eine kleine Dart-Schicht verbindet es mit der App.

**Was müssen Kunden tun?** Drei Schritte:

1. `flutter pub add reception_flutter` ausführen und das iOS-Mindestziel der App auf 17.0 stellen. Swift Package Manager (Flutters Standard) und CocoaPods funktionieren beide, ohne die Podfile anzufassen.
2. Einmal in `main()` `await Reception.configure(appId: '…')` mit der öffentlichen App ID aufrufen.
3. Den vorhandenen Support-Button mit `Reception.openChat()` verbinden. Farben folgen dem App-Design; `Reception.unreadCount` liefert die Zahl ungelesener Antworten für ein Badge.

**Push:** Das Plugin registriert den Apple-Gerätetoken selbst, zeigt Reception-Banner nur bei geschlossenem Chat und öffnet beim Antippen den Chat – auch wenn die App vorher beendet war. Es fragt nie selbst nach Erlaubnis; die App behält ihre Abfrage und ruft danach `Reception.registerForPushIfAuthorized()` auf. Benachrichtigungen anderer Dienste (z. B. Firebase) laufen unverändert weiter.

**Hot Restart:** Beim Entwickeln startet Flutter den Dart-Code neu, der native Chat läuft weiter. Ungelesen-Zähler, Konfiguration und Einstellungen werden danach wieder aus dem nativen Teil gelesen.

**Nur iOS:** Unter Android und im Web passiert nichts; die Werte bleiben leer bzw. null.

**Geprüft (27.10.2026, Flutter 3.47.8, Xcode 26.5, iPhone-17-Pro-Simulator, lokales Backend):** automatische Dart- und Swift-Tests, Paketprüfungen, frische Simulator-Builds mit Swift Package Manager und CocoaPods, der Setup-Check des SDK, Antworten aus dem Dashboard mit Ungelesen-Badge, Name/E-Mail/Metadaten beim Server, Paywall-Filter (nur `plans` wird angeboten), Push im Vordergrund, bei offenem Chat, im Hintergrund und beim Kaltstart, Deutsch über die Gerätesprache und über die Sprachwahl in der App, Hell/Dunkel, eingebetteter Chat, Daten löschen, Abmelden und Hot Restart. Eine frisch angelegte Flutter-App ließ sich mit beiden Paketsystemen bauen; nötig war nur das Mindestziel 17.0.

**Gefunden:**
- Das Paket lässt sich so noch nicht veröffentlichen: generierter Code nutzt das Paket `meta`, das in `pubspec.yaml` fehlt (einzeilige Korrektur, siehe STATUS.md).
- Flutter-Apps müssen ihre Sprachen in der iOS-`Info.plist` eintragen (`CFBundleLocalizations`), sonst bleibt der Chat trotz deutscher Gerätesprache englisch. Das verlangt auch Flutters eigene Anleitung; unsere Doku sollte es erwähnen.

**Nicht geprüft:** Das Senden einer Paywall-Karte aus dem Dashboard und ihr Antippen (der lokale Test-Workspace hat kein Abo, deshalb ist der Posteingang gesperrt), die Benutzerdetails in der Dashboard-Ansicht (nur in der Datenbank geprüft), echte Push-Zustellung auf einem iPhone (die Beispiel-App hat keine Push-Berechtigung, daher kein Token), Fotos senden und Release-Builds.

[Anleitung](https://reception.sh/docs/flutter) · [Befehle und Ergebnisse](commands.txt) · [Screenshots](screenshots.txt)
