// Datenschutzerklärung / privacy policy, German and English.
//
// TEMPLATE: written from what the code does (backend/ and app/ as of
// November 2026), not by a lawyer. The operator must review it before a
// public launch and keep it in step with the code (new third parties, new
// data, other retention). Edit the text right here; the format is described
// in legal_markdown.dart (headings, "- " lists, **bold**, blank lines
// between paragraphs). {{controller}} is replaced by the operator's details
// from the server (config.yaml, legal: section), so no name or address is
// ever written into this file. Change [kPrivacyVersionDe] and
// [kPrivacyVersionEn] whenever the content changes.

/// Shown as "Stand: …" / "Last updated: …" at the top.
const kPrivacyVersionDe = '11. November 2026';
const kPrivacyVersionEn = '11 November 2026';

const privacyTextDe =
    '''
# Datenschutzerklärung

Stand: $kPrivacyVersionDe

Stonerspots ist eine Community-Karte für Orte, an denen Erwachsene draußen kiffen können. Diese Erklärung beschreibt, welche Daten die Apps (Android, iOS, Web, Linux, Windows, macOS) und der Stonerspots-Server verarbeiten, wozu und wie lange. Stonerspots verwendet keine Werbung, keine Analyse- oder Tracking-Dienste und keine Cookies.

## 1. Verantwortlicher

{{controller}}

Der Stonerspots-Server (die API) wird vom Verantwortlichen selbst auf einem eigenen Server betrieben. Die Web-App wird über GitHub Pages ausgeliefert (siehe Abschnitt 9). Der Quellcode ist öffentlich: github.com/devilAPI/stonerspots.

## 2. Dein Konto

Für die Registrierung speichern wir:

- deine **E-Mail-Adresse** (für die Anmeldung, die Bestätigung deiner Adresse und das Zurücksetzen des Passworts; sie ist für andere Nutzer nicht sichtbar),
- deinen **Anzeigenamen** (öffentlich sichtbar),
- dein **Passwort nur als bcrypt-Hash**, nie im Klartext,
- den Zeitpunkt, zu dem du bestätigt hast, dass du mindestens 18 Jahre alt bist, und den Zeitpunkt der Registrierung,
- ob deine E-Mail-Adresse bestätigt ist; für Bestätigungs- und Passwort-Links nur deren Hash und Ablaufzeit (Bestätigung 24 Stunden, Passwort-Reset 1 Stunde),
- optional ein **Profilbild** (öffentlich sichtbar),
- optional eine **Bio**, ein kurzer Text über dich (öffentlich sichtbar),
- bei einer Sperre durch die Moderation deren Zeitpunkt,
- bei Administratoren zusätzlich den geheimen Schlüssel für die Zwei-Faktor-Anmeldung (TOTP) und den zuletzt verwendeten Code-Zeitraum.

Dein öffentliches Profil zeigt Anzeigenamen, Profilbild, Bio, seit wann du dabei bist, deine Spots und Updates sowie die Zahl deiner Spots, Updates, Follower und der Leute, denen du folgst.

**Anmeldung:** Nach dem Login erhält die App einen Zugangs-Token (15 Minuten gültig, wird auf dem Server nicht gespeichert) und einen Erneuerungs-Token (30 Tage gültig). Vom Erneuerungs-Token speichert der Server nur einen Hash mit Erstellungs-, Ablauf- und Widerrufszeit; diese Einträge bleiben bis zur Löschung deines Kontos gespeichert. Bei einer Passwortänderung oder Sperre werden alle Erneuerungs-Tokens widerrufen.

Rechtsgrundlage: Art. 6 Abs. 1 lit. b DSGVO (Bereitstellung des Dienstes, den du mit der Registrierung nutzt).

## 3. Was du veröffentlichst

- **Spots:** Titel, Beschreibung, genaue Koordinaten, Tags und Zeitpunkt. Spots sind mit deinem Anzeigenamen für alle sichtbar, auch ohne Anmeldung.
- **Updates:** Text, Kategorie (z. B. „noch gut", „voll") und bis zu 4 Fotos; öffentlich mit deinem Anzeigenamen. Du kannst sie bearbeiten und löschen.
- **Fotos und Profilbilder:** Der Server liest jedes Bild ein und speichert es neu kodiert. Dabei werden alle Metadaten entfernt (EXIF, also auch eine GPS-Position, Kameramodell und Aufnahmezeit). Hochgeladene Fotos, die nie in einem Update veröffentlicht werden, löscht der Server nach 24 Stunden automatisch.
- **Kommentare und Bewertungen** (1 bis 5 Sterne mit Text): öffentlich mit deinem Anzeigenamen; du kannst sie löschen.
- **Likes und Folgen:** Die Anzahl ist öffentlich. Wer deinem Spot ein Like gibt, ihn kommentiert oder bewertet und wer dir folgt, erscheint in deiner Aktivität (Benachrichtigungen) – umgekehrt erscheinst du in der Aktivität der anderen Person.
- **Listen** gespeicherter Spots sind privat und nur für dich sichtbar.
- **Meldungen:** Wenn du einen Inhalt meldest, speichern wir den Inhalt, deinen Grund und den Zeitpunkt. Administratoren sehen, wer gemeldet hat.

**Moderation:** Administratoren können Inhalte ausblenden, bearbeiten oder löschen und Konten sperren; dafür sehen sie auch E-Mail-Adressen. Ein Inhalt, den mehrere Nutzer melden, kann automatisch ausgeblendet werden, bis ein Administrator ihn prüft.

Bitte überlege, was du veröffentlichst: Öffentliche Spots und Updates können Rückschlüsse darauf zulassen, wo und wann du Cannabis konsumierst. Trage keine Spots an deiner Wohnadresse ein und keine Fotos, auf denen andere Menschen erkennbar sind.

Rechtsgrundlagen: Art. 6 Abs. 1 lit. b DSGVO (die Funktionen, die du nutzt); für die Moderation Art. 6 Abs. 1 lit. f DSGVO (berechtigtes Interesse an einer sicheren, rechtmäßigen Plattform). Soweit deine Inhalte Rückschlüsse auf Gesundheitsdaten erlauben, machst du sie selbst öffentlich (Art. 9 Abs. 2 lit. e DSGVO).

## 4. Dein Standort

Die App fragt nur mit deiner Erlaubnis nach dem Standort deines Geräts. Du kannst die Erlaubnis jederzeit in den Einstellungen deines Geräts oder Browsers zurücknehmen; die App funktioniert dann weiter, nur ohne „in deiner Nähe".

- **Karte:** Der Standort wird nur auf dem Gerät verwendet, um die Karte dort zu zeigen. Er wird nicht an den Server geschickt. Die App lädt die Spots des sichtbaren Kartenausschnitts; dadurch erfährt der Server, welchen Ausschnitt du ansiehst (auch wenn er um deinen Standort liegt), speichert ihn aber nicht.
- **Feed „In der Nähe" und Spot-Suche:** Hier schickt die App deine Koordinaten mit der Anfrage an den Server, damit er nach Entfernung sortieren kann. Der Server verwendet sie nur für diese Antwort und speichert sie nicht; sein Protokoll enthält keine Anfrageparameter.
- **Widget „Nächster Spot" (Android):** Die Entfernung wird auf dem Gerät berechnet. Das Widget speichert nur Name, Nummer und Entfernung des Spots, keine Koordinaten.
- **Neuer Spot:** Die Koordinaten, die du für einen Spot wählst, werden mit dem Spot veröffentlicht.
- **Verbotszonen:** Nur wenn du sie einschaltest und nur für Gebiete in Deutschland: Um Verbotszonen (z. B. rund um Schulen und Spielplätze) anzuzeigen, schickt die App den sichtbaren Kartenausschnitt bzw. die Position eines Spots an unseren Server. Der Server fragt die Zonen bei der Overpass API ab, einem öffentlichen Dienst für OpenStreetMap-Daten (standardmäßig overpass-api.de) – nur mit den Koordinaten des Gebiets, ohne deine IP-Adresse oder andere Daten von dir. Die Antworten hält der Server in einem Zwischenspeicher, damit dasselbe Gebiet nicht erneut abgefragt wird.
- **Adresssuche beim Anlegen eines Spots:** Der Suchtext geht an unseren Server, der ihn an den Dienst Nominatim der OpenStreetMap Foundation weiterleitet – ohne deine IP-Adresse. Der Server hält Suchtexte und Ergebnisse bis zu 24 Stunden im Arbeitsspeicher, um Nominatim nicht doppelt zu fragen.

Rechtsgrundlage: Art. 6 Abs. 1 lit. a DSGVO (deine Einwilligung durch die Standortfreigabe) und lit. b (die Funktion, die du aufrufst).

## 5. Technische Daten auf dem Server

- **IP-Adresse:** Zum Schutz vor Missbrauch begrenzt der Server die Zahl der Anfragen pro IP-Adresse (z. B. Anmeldeversuche). Dafür hält er IP-Adressen mit einem Zähler im Arbeitsspeicher, nicht in der Datenbank; sie verfallen, sobald sie nicht mehr gebraucht werden, spätestens bei einem Neustart. Ebenso zählt er falsche Passwörter pro Konto und Tageskontingente pro Nutzer (z. B. neue Spots pro Tag) im Arbeitsspeicher.
- **Server-Protokoll:** Normale Anfragen protokolliert der Server nicht. Er schreibt eine Zeile ins Systemprotokoll bei abgewiesenen Anfragen wegen zu vieler Versuche (Status 429) und bei Serverfehlern (5xx) – mit Zeit, Methode, Pfad ohne Parameter, Dauer, IP-Adresse und einer zufälligen Anfrage-Nummer –, bei falschen Zwei-Faktor-Codes und Passwörtern in Administrator-Funktionen (mit IP-Adresse und Nutzernummer) und bei Fehlern im Mailversand. Diese Zeilen landen im System-Journal (journald) des Servers. Der Server löscht sie nicht selbst; sie werden nach den Protokoll-Einstellungen des Servers überschrieben.
- **Webserver (Reverse Proxy):** Vor dem Stonerspots-Server läuft ein Webserver, der die verschlüsselte Verbindung (HTTPS) herstellt. Je nach Einrichtung protokolliert er Zugriffe mit IP-Adresse, Zeit, angefragter Adresse, Status und Browser- bzw. App-Kennung.
- **Datensicherung:** Der Betreiber kann verschlüsselte Sicherungskopien der Datenbank und der Fotos anlegen. Gelöschte Daten verschwinden daraus, wenn die betreffenden Sicherungen überschrieben werden.

Rechtsgrundlage: Art. 6 Abs. 1 lit. f DSGVO (berechtigtes Interesse an einem sicheren, stabilen Betrieb und der Abwehr von Angriffen).

## 6. E-Mails

Wenn der Betreiber den Mailversand eingerichtet hat, schickt der Server dir eine E-Mail zur Bestätigung deiner Adresse nach der Registrierung und auf Anfrage einen Link zum Zurücksetzen des Passworts. Die Mails werden über den Mailserver (SMTP) des Betreibers bzw. seines Mail-Anbieters versendet, der dafür deine E-Mail-Adresse und den Inhalt der Mail verarbeitet. Newsletter oder Werbung gibt es nicht.

Rechtsgrundlage: Art. 6 Abs. 1 lit. b DSGVO.

## 7. Prüfung auf bekannte Passwörter

Bei der Registrierung und bei einer Passwortänderung prüft der Server, ob dein neues Passwort in bekannten Datenlecks vorkommt. Dazu berechnet er den SHA-1-Hash des Passworts und schickt **nur die ersten 5 Zeichen dieses Hashs** an den Dienst „Pwned Passwords" von Have I Been Pwned (api.pwnedpasswords.com). Der Dienst antwortet mit allen bekannten Hashs, die so beginnen; der Vergleich findet auf unserem Server statt. Dein Passwort, sein vollständiger Hash und deine IP-Adresse verlassen unseren Server dabei nicht.

Rechtsgrundlage: Art. 6 Abs. 1 lit. f DSGVO (Schutz deines Kontos).

## 8. Speicherung auf deinem Gerät

- Die Anmelde-Tokens liegen im sicheren Speicher des Betriebssystems (Schlüsselbund, Keystore o. Ä.), in der Web-App im lokalen Speicher (localStorage) des Browsers für diese Seite.
- Einstellungen (z. B. Transparenz, Verbotszonen an oder aus, 3D-Ansicht, automatische Update-Suche und Update-Kanal, eine übersprungene Version, bis wann der Hinweis auf eine Entwicklerversion ausgeblendet ist) und die zuletzt geladene Liste der App-Versionen speichert die App lokal.
- Bilder werden zwischengespeichert, damit sie nicht jedes Mal neu geladen werden.

Diese Daten verlassen dein Gerät nicht und sind für die Funktion der App unbedingt erforderlich (§ 25 Abs. 2 Nr. 2 TDDDG). Du löschst sie, indem du dich abmeldest bzw. die App-Daten oder Website-Daten löschst.

## 9. Dienste, die die App direkt aufruft

Für die folgenden Funktionen verbindet sich die App direkt mit anderen Anbietern. Diese sehen dabei – wie bei jedem Abruf im Internet – deine IP-Adresse, die Uhrzeit und technische Angaben (z. B. App- oder Browser-Kennung) und das, was abgerufen wird:

- **Kartenkacheln:** OpenStreetMap Foundation (tile.openstreetmap.org) für die Standardkarte; CARTO (basemaps.cartocdn.com) für die dunkle Karte, wenn diese App-Version sie verwendet; für die ÖPNV-Karte, nur wenn du sie einschaltest, Thunderforest (tile.thunderforest.com) oder, in App-Versionen ohne Thunderforest-Zugang, ÖPNVKarte (tileserver.memomaps.de, memomaps.de); Esri (server.arcgisonline.com) für Satellitenbilder in der Satellitenansicht und in Vorschaubildern von Spots; OpenFreeMap (tiles.openfreemap.org) für die Gebäude der 3D-Ansicht, nur solange sie eingeschaltet ist. Aus den abgerufenen Kacheln ist erkennbar, welchen Kartenausschnitt du ansiehst.
- **Wetter:** Open-Meteo (api.open-meteo.com) erhält beim Öffnen einer Spot-Seite die Koordinaten des Spots (nicht deinen Standort).
- **App-Updates** (Android, Windows, Linux, macOS): Die App fragt beim Start höchstens alle 6 Stunden bei GitHub (api.github.com) nach neuen Versionen und lädt Updates von GitHub herunter. Die automatische Suche lässt sich unter Einstellungen → Updates abschalten.
- **Web-App:** Die Web-App wird von GitHub Pages (GitHub, Inc.) ausgeliefert, das dabei deine IP-Adresse verarbeitet. Beim Start lädt sie Schriftarten und Teile ihrer Grafik-Engine von Servern von Google (fonts.gstatic.com, www.gstatic.com).
- **Google Maps:** Nur wenn du „In Google Maps öffnen" antippst, öffnet sich Google Maps (App oder Browser) mit den Koordinaten des Spots; dort gelten die Datenschutzbestimmungen von Google.
- **Teilen:** Wenn du einen Link teilst, geht er an die App, die du dafür auswählst.

Einige dieser Anbieter sitzen außerhalb der EU, etwa im Vereinigten Königreich (Angemessenheitsbeschluss der EU-Kommission) oder in den USA. Rechtsgrundlage ist Art. 6 Abs. 1 lit. f DSGVO (berechtigtes Interesse an der Darstellung der Karte und den Funktionen der App) bzw. lit. b, wenn du die Funktion ausdrücklich aufrufst.

## 10. Speicherdauer und Löschung

- Dein Konto und deine Inhalte bleiben gespeichert, bis du sie oder dein Konto löschst oder die Moderation sie entfernt. Ausgeblendete Inhalte bleiben gespeichert, bis sie gelöscht werden.
- **Konto löschen** (Profil → Menü → Konto löschen, mit deinem Passwort) löscht sofort: dein Konto, alle Spots, die du angelegt hast (mit allen Updates, Fotos, Kommentaren, Bewertungen und Likes – auch denen anderer Nutzer – zu diesen Spots), deine Updates, Fotos und dein Profilbild (auch die Bilddateien), deine Kommentare, Bewertungen, Likes, Listen und Meldungen, Meldungen über deine Inhalte, deine Folgen-Beziehungen in beide Richtungen, deine Aktivität und deine Anmeldesitzungen.
- Zu den Server-Protokollen, Zählern im Arbeitsspeicher und Sicherungskopien siehe Abschnitt 5.

## 11. Deine Rechte

Du hast das Recht auf Auskunft (Art. 15 DSGVO), Berichtigung (Art. 16), Löschung (Art. 17), Einschränkung der Verarbeitung (Art. 18), Datenübertragbarkeit (Art. 20) und Widerspruch gegen Verarbeitungen auf Grundlage berechtigter Interessen (Art. 21). Eine Einwilligung (z. B. die Standortfreigabe) kannst du jederzeit mit Wirkung für die Zukunft widerrufen (Art. 7 Abs. 3).

- **Deine Daten herunterladen:** Profil → Menü → „Meine Daten herunterladen" liefert alles, was der Server über dein Konto gespeichert hat, als JSON-Datei (ohne Passwort-Hash und geheime Schlüssel).
- **Löschen:** Updates, Kommentare und Bewertungen kannst du selbst löschen, dein Konto unter Profil → Menü → Konto löschen. Für alles andere (z. B. einen Spot oder deinen Anzeigenamen) schreib uns.
- Für Fragen und Anträge nutze die Kontaktdaten oben.

Du hast außerdem das Recht, dich bei einer Datenschutz-Aufsichtsbehörde zu beschweren (Art. 77 DSGVO), insbesondere in dem EU-Staat, in dem du wohnst oder arbeitst.

## 12. Altersgrenze

Stonerspots ist nur für Erwachsene. Mit der Registrierung bestätigst du, dass du mindestens 18 Jahre alt bist.

## 13. Änderungen

Wenn sich die App oder der Server ändern, passen wir diese Erklärung an. Es gilt die Fassung, die in der App angezeigt wird; das Datum steht oben.
''';

const privacyTextEn =
    '''
# Privacy policy

Last updated: $kPrivacyVersionEn

Stonerspots is a community map of places where adults can smoke weed outdoors. This policy describes which data the apps (Android, iOS, web, Linux, Windows, macOS) and the Stonerspots server process, why, and for how long. Stonerspots uses no advertising, no analytics or tracking services and no cookies.

## 1. Controller

{{controller}}

The Stonerspots server (the API) is run by the controller on their own server. The web app is served by GitHub Pages (see section 9). The source code is public: github.com/devilAPI/stonerspots.

## 2. Your account

When you register we store:

- your **email address** (for logging in, confirming your address and resetting your password; other users cannot see it),
- your **display name** (public),
- your **password only as a bcrypt hash**, never in plain text,
- when you confirmed that you are at least 18 years old, and when you registered,
- whether your email address is confirmed; for confirmation and password links only their hash and expiry (confirmation 24 hours, password reset 1 hour),
- optionally a **profile picture** (public),
- optionally a **bio**, a short text about you (public),
- when your account was banned by moderation, if it was,
- for administrators also the secret key of their two-factor login (TOTP) and the last code period used.

Your public profile shows your display name, profile picture, bio, since when you are a member, your spots and updates, and the number of your spots, updates, followers and people you follow.

**Login:** After logging in the app receives an access token (valid for 15 minutes, not stored on the server) and a refresh token (valid for 30 days). Of the refresh token the server stores only a hash with its creation, expiry and revocation time; these entries are kept until your account is deleted. Changing your password or a ban revokes all refresh tokens.

Legal basis: Art. 6(1)(b) GDPR (providing the service you use by registering).

## 3. What you publish

- **Spots:** title, description, exact coordinates, tags and time. Spots are visible to everyone with your display name, also without logging in.
- **Updates:** text, a category (e.g. "still good", "crowded") and up to 4 photos; public with your display name. You can edit and delete them.
- **Photos and profile pictures:** The server reads every image and stores it re-encoded. All metadata is removed in the process (EXIF, so also a GPS position, camera model and capture time). Uploaded photos that are never published in an update are deleted automatically after 24 hours.
- **Comments and reviews** (1 to 5 stars with text): public with your display name; you can delete them.
- **Likes and follows:** The counts are public. Whoever likes, comments on or reviews your spot, and whoever follows you, shows up in your activity (notifications) – and you show up in the other person's activity.
- **Lists** of saved spots are private and only visible to you.
- **Reports:** When you report content we store the content, your reason and the time. Administrators can see who reported.

**Moderation:** Administrators can hide, edit or delete content and ban accounts; for this they can also see email addresses. Content reported by several users can be hidden automatically until an administrator reviews it.

Please think about what you publish: public spots and updates can reveal where and when you consume cannabis. Do not add spots at your home address or photos in which other people can be recognised.

Legal bases: Art. 6(1)(b) GDPR (the features you use); for moderation Art. 6(1)(f) GDPR (legitimate interest in a safe and lawful platform). Where your content allows conclusions about health data, you make it public yourself (Art. 9(2)(e) GDPR).

## 4. Your location

The app asks for your device's location only with your permission. You can withdraw the permission at any time in your device or browser settings; the app keeps working, just without "near you".

- **Map:** The location is only used on the device to show the map there. It is not sent to the server. The app loads the spots of the visible map area; so the server learns which area you are looking at (also when it is around your location), but it does not store it.
- **Feed "Nearby" and spot search:** Here the app sends your coordinates with the request so that the server can sort by distance. The server uses them only for this answer and does not store them; its log contains no request parameters.
- **"Nearest spot" widget (Android):** The distance is calculated on the device. The widget stores only the spot's name, number and distance, no coordinates.
- **New spot:** The coordinates you choose for a spot are published with it.
- **No-smoking zones:** Only when you switch them on, and only for areas in Germany: to show no-smoking zones (e.g. around schools and playgrounds), the app sends the visible map area or a spot's position to our server. The server fetches the zones from the Overpass API, a public service for OpenStreetMap data (by default overpass-api.de) – with the coordinates of the area only, without your IP address or any other data of yours. The server keeps the answers in a cache so that the same area is not fetched again.
- **Address search when adding a spot:** The search text goes to our server, which forwards it to the Nominatim service of the OpenStreetMap Foundation – without your IP address. The server keeps search texts and results in memory for up to 24 hours so as not to ask Nominatim twice.

Legal basis: Art. 6(1)(a) GDPR (your consent by granting location access) and (b) (the feature you use).

## 5. Technical data on the server

- **IP address:** To prevent abuse the server limits the number of requests per IP address (e.g. login attempts). For this it keeps IP addresses with a counter in memory, not in the database; they expire as soon as they are no longer needed, at the latest when the server restarts. It also counts wrong passwords per account and daily quotas per user (e.g. new spots per day) in memory.
- **Server log:** The server does not log normal requests. It writes one line to the system log for requests refused because of too many attempts (status 429) and for server errors (5xx) – with time, method, path without parameters, duration, IP address and a random request number –, for wrong two-factor codes and passwords in administrator functions (with IP address and user number), and for errors when sending mail. These lines go to the server's system journal (journald). The server does not delete them itself; they are overwritten according to the server's log settings.
- **Web server (reverse proxy):** A web server in front of the Stonerspots server provides the encrypted connection (HTTPS). Depending on its setup it logs requests with IP address, time, requested address, status and browser or app identifier.
- **Backups:** The operator may keep encrypted backups of the database and the photos. Deleted data disappears from them when those backups are overwritten.

Legal basis: Art. 6(1)(f) GDPR (legitimate interest in secure, stable operation and in fending off attacks).

## 6. Emails

If the operator has set up sending mail, the server sends you an email to confirm your address after registering and, on request, a link to reset your password. The mails are sent through the mail server (SMTP) of the operator or their mail provider, which processes your email address and the content of the mail for this. There are no newsletters or advertising.

Legal basis: Art. 6(1)(b) GDPR.

## 7. Check for known passwords

When you register and when you change your password, the server checks whether the new password appears in known data breaches. It calculates the SHA-1 hash of the password and sends **only the first 5 characters of this hash** to the "Pwned Passwords" service of Have I Been Pwned (api.pwnedpasswords.com). The service answers with all known hashes that start like this; the comparison happens on our server. Your password, its full hash and your IP address do not leave our server in the process.

Legal basis: Art. 6(1)(f) GDPR (protecting your account).

## 8. Storage on your device

- The login tokens are kept in the operating system's secure storage (keychain, keystore or similar), in the web app in the browser's local storage (localStorage) for this site.
- Settings (e.g. transparency, no-smoking zones on or off, the 3D view, automatic update checks and the update channel, a skipped version, until when the development-build notice is hidden) and the last loaded list of app versions are stored locally by the app.
- Images are cached so that they do not have to be loaded every time.

This data does not leave your device and is strictly necessary for the app to work (§ 25(2) no. 2 TDDDG). You delete it by logging out or by clearing the app's or website's data.

## 9. Services the app contacts directly

For the following features the app connects directly to other providers. Like with any request on the internet, they see your IP address, the time, technical details (e.g. app or browser identifier) and what is requested:

- **Map tiles:** OpenStreetMap Foundation (tile.openstreetmap.org) for the standard map; CARTO (basemaps.cartocdn.com) for the dark map, if this app version uses it; for the public transport map, only when you switch it on, Thunderforest (tile.thunderforest.com) or, in app versions without Thunderforest access, ÖPNVKarte (tileserver.memomaps.de, memomaps.de); Esri (server.arcgisonline.com) for satellite images in the satellite view and in spot previews; OpenFreeMap (tiles.openfreemap.org) for the buildings of the 3D view, only while it is switched on. The tiles requested show which map area you are looking at.
- **Weather:** Open-Meteo (api.open-meteo.com) receives the coordinates of the spot (not your location) when you open a spot page.
- **App updates** (Android, Windows, Linux, macOS): At start, at most every 6 hours, the app asks GitHub (api.github.com) for new versions and downloads updates from GitHub. Automatic checks can be switched off under Settings → Updates.
- **Web app:** The web app is served by GitHub Pages (GitHub, Inc.), which processes your IP address. At start it loads fonts and parts of its graphics engine from Google servers (fonts.gstatic.com, www.gstatic.com).
- **Google Maps:** Only when you tap "Open in Google Maps", Google Maps (app or browser) opens with the spot's coordinates; Google's privacy policy applies there.
- **Sharing:** When you share a link, it goes to the app you pick for it.

Some of these providers are located outside the EU, for example in the United Kingdom (adequacy decision of the EU Commission) or in the USA. The legal basis is Art. 6(1)(f) GDPR (legitimate interest in showing the map and providing the app's features) or (b) when you explicitly use the feature.

## 10. Retention and deletion

- Your account and your content are kept until you delete them or your account, or moderation removes them. Hidden content is kept until it is deleted.
- **Deleting your account** (Profile → menu → Delete account, with your password) immediately deletes: your account, all spots you created (with all updates, photos, comments, reviews and likes on those spots – including other users'), your updates, photos and profile picture (including the image files), your comments, reviews, likes, lists and reports, reports about your content, your follow relations in both directions, your activity and your login sessions.
- For server logs, counters in memory and backups see section 5.

## 11. Your rights

You have the right of access (Art. 15 GDPR), rectification (Art. 16), erasure (Art. 17), restriction of processing (Art. 18), data portability (Art. 20) and to object to processing based on legitimate interests (Art. 21). You can withdraw consent (e.g. location access) at any time with effect for the future (Art. 7(3)).

- **Download your data:** Profile → menu → "Download my data" gives you everything the server has stored about your account as a JSON file (without password hash and secret keys).
- **Deleting:** You can delete updates, comments and reviews yourself, and your account under Profile → menu → Delete account. For anything else (e.g. a spot or your display name) write to us.
- For questions and requests use the contact details above.

You also have the right to lodge a complaint with a data protection supervisory authority (Art. 77 GDPR), in particular in the EU country where you live or work.

## 12. Age limit

Stonerspots is for adults only. By registering you confirm that you are at least 18 years old.

## 13. Changes

When the app or the server change, we update this policy. The version shown in the app applies; its date is at the top.
''';
