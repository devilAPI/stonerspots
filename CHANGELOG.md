# Changelog

Releases are the GitHub releases `vX.Y.Z`; how one is made is in the README,
"Releasing 1.0". Development builds (`dev-<n>`) are not listed here.

## 1.0.12

- Feed filters reworked: the sort (New, Top, Nearby) is one glass row of
  tabs under the title; the filters moved to a filter button beside the
  title (a badge counts those that are on), which opens a sheet with all
  of them. The filters that are on show as a row under the sort, each
  removable with its x.
- New filter: distance from you. A slider from 1 to 500 km (or
  anywhere) keeps only spots within that radius of where you are, with
  every sort, and is remembered for next time (`radius_km` on
  `GET /feed`; needs the new server).
- Backend built with Go 1.27.4: fixes a vulnerability in the standard
  library's HTTP server and client (GO-2026-6859).

## 1.0.11

- Zone status without a zone nearby says just "Keine Verbotszone" ("No
  zone") instead of "Keine Verbotszone in OSM-Daten gefunden".
- A zone status that could not be checked (the server could not reach any
  Overpass server yet for that area, mostly countryside) is checked again
  every 30 seconds while it is shown, instead of staying an error.
- The profile's Spots / Updates switcher is the same glass row as the
  admin's sections; neither shows Material's ink ripple anymore.
- The map-style button on the add-spot map (and the spot page's small
  map, with its recenter button) sits on a glass capsule like the main
  map's controls.
- Home-screen app on iOS: a tap on the tab bar that iOS cancels (near the
  bottom edge) still switches the tab, and the page is kept from staying
  scrolled after the keyboard or a double tap, which left the bottom of
  the screen unresponsive (flutter/flutter#115829).
- Every page has the same top: the title floats over the page, which
  fades out beneath it, without a bar. The feed, login and register, add
  spot and admin pages had a hard edge; the feed's filters are two glass
  rows under its title now.
- Server: Germany's zones are built on the server from Geofabrik's
  OpenStreetMap extract once a week (about 4.5 GB download, deleted after;
  1.5 minutes and about 900 MB of memory on a desktop), so every German
  tile is ready at once instead of waiting for the busy public Overpass
  servers, which stay the fallback (`zones.extract`, on by default). The
  download goes to `osm/` next to `upload_dir`. The systemd unit allows
  the API 1536 MB (was 1 GB) for it.

## 1.0.10

- Profile pictures can be seen full size: a tap on someone's picture on
  their profile opens it (pinch to zoom); for your own, "Show picture" is
  the first entry of the sheet that changes it.

## 1.0.9

- iPhone home-screen app (installed from Safari): the tabs work again. The
  web engine reports no safe area, so the tab bar sat in the home
  indicator's swipe zone, where iOS swallows taps, and top controls under
  the clock; the app now reads the safe area from the browser.
- iOS 27 look: no more app bars. Pages have floating glass controls, a
  round back button (‹) on the left, the actions in one capsule on the
  right, and the title as plain text in between, over a soft fade of the
  page. Admin's sections are a glass row below them.
- Search is a round glass button beside the tabs (phones); it opens the
  map's search from any tab. With the side rail it stays on the map.
- The zone notes on the map ("Verbotszonen werden geladen", "Zoom in…",
  "could not be loaded") are glass capsules with an icon.

## 1.0.8

- Zones load reliably and fast. The server asks OpenStreetMap's Overpass
  for a block of 4 × 4 tiles at once (one to four queries for a screen
  instead of up to 48), tries other public Overpass servers when one is
  down or overloaded (as overpass-api.de often was), answers old data at
  once while it refreshes it, and keeps all of Germany cached in the
  background, areas with spots first. (Needs the 1.0.8 backend.)
- The app retries a zone tile that failed quietly and says "could not be
  loaded" only after three failures in a row, instead of at the first.
- The zone disclaimer no longer pops up while zooming in after every app
  start: confirming it is remembered, and it is asked only when you turn
  zones on (the ⓘ button shows it any time).
- The map always opens in 2D; 3D is no longer remembered.
- Also ships everything listed under 1.0.7, which was never released: its
  build could not fetch the glass package (a git dependency on a fork with
  Git LFS files); the package is now part of the repository.

## 1.0.7

Not released: its build failed (see 1.0.8, which ships these changes).

- Glass: bars, buttons, sheets and the tab bar use liquid_glass_renderer
  instead of liquid_glass_easy. Holding the tab bar swells it and lifts a
  loupe over the selected tab that follows the finger, also on the web;
  letting go snaps to the tab beneath it. (A fork of the package until its
  web fix, whynotmake-it/flutter_liquid_glass#266, is released.)
- Phones get the real, refracting glass (Flutter GPU is switched on for
  Android and iOS); where a device cannot, it is frosted as before. New
  setting "Real glass" turns it off (frosted, easier on GPU and battery).
- 3D map: the buildings are worked out about 2.5 times faster per frame
  (wall shading is computed once per building, buffers are reused), so
  panning the tilted map over a city no longer drops frames in the app's
  own work: on the Linux desktop over central Munich the slowest frames
  went from 28 to 13 ms.
- Settings: new "Map" section with "3D buildings" (off draws the tilted
  map without them, for older devices) and "Sharp map" (off loads normal
  instead of high-resolution tiles on sharp screens, a quarter of the
  data). New "Reduce motion": the map jumps instead of flying and tilts
  without animation; the system's "remove animations" does the same.

## 1.0.6

- Map: every spot shows up again when zoomed out. The map loaded at most
  200 spots of the area, the most liked first, so the older, liked spots
  of one region pushed out every newer one (e.g. all spots of some
  accounts). It now loads up to 1000; beyond that, the server spreads the
  spots it sends over the whole area. The list is sent compressed.
  (Needs the 1.0.6 backend.)
- Spot page: admins can delete the spot from the ⋮ menu (after asking);
  "Report" has a flag icon.
- Share button: the iPhone/iPad/Mac share icon on Apple devices, also in
  Safari.
- Profile picture: choosing one opens a cropper (drag, pinch, scroll or the
  slider to zoom; the circle shows what is kept). The cut is uploaded as a
  640 px JPEG without the photo's metadata.

## 1.0.5

- Zones: the note that says why a tapped place is a zone goes away again:
  after 6 seconds, with its ✕, or with a tap where there is no zone. (Since
  it has a button, Flutter kept it until it was dismissed.)
- Wide windows (navigation rail on the left): the rows of the profile's
  spots, the saved lists and the activity page start with their list again
  instead of a rail's width further right, cutting off their names.
- Turning the map with two fingers no longer tilts it now and then. A
  two-finger gesture is a tilt only when both fingers move up or down
  together; once it turns or pinches, it stays a turn or zoom until the
  fingers are lifted (as in the big map apps), and a tilt keeps the map
  exactly in place.
- 3D tilted all the way: no more band of sky above the map's far edge. The
  map is now sized so it reaches the top of the screen at every tilt; the
  steepest tilt is 50 degrees (was 60), with a slightly gentler perspective.

## 1.0.4

- 3D: zoom stops at 18.5. Further in, buildings near the viewer reached the
  eye and were drawn torn apart (like a box around the map); such buildings
  are now left out, and switching to 3D closer in zooms out to 18.5.
- Adding a spot: a zone check that fails can no longer keep "Save"
  spinning; the check only ever warns, so the spot is saved.
- Zones: while the server is still fetching an area from Overpass (which
  often takes 30-60 s per area right now), the map says "Loading zones…"
  and keeps asking every 10 s, instead of giving up after two minutes with
  "Zones could not be loaded". That message is left for real errors.

## 1.0.3

- Profile and saved lists: the small satellite thumbnails no longer carry a
  cut-off "…ld Imagery" over the picture; the lists credit Esri once below
  instead.
- Web: a release now really replaces the web app. GitHub Pages keeps the
  files of the first deployment of a commit, and 1.0.2 was tagged on the
  commit its dev build had deployed minutes before (the site stayed on
  1.0.1). A release commit's tag is now pushed before main, and a dev build
  of a commit that is already a release leaves the web deploy to it.

## 1.0.2

- Web: the map no longer shows a grey overlay and the 3D view loads. The
  Germany border used for the zone buttons was decoded wrongly on the web
  (bitwise operators are unsigned 32-bit there), which made the zone layer
  fail on every frame and cover the map.
- CI also runs the border tests in Chrome.

## 1.0.1

- Backend built with Go 1.27.3: fixes in the standard library for TLS
  certificate checks (GO-2026-6809) and an HTTP/2 server crash
  (GO-2026-6617).
- Web: the development-build notice shows only on the dev web app
  (`/dev/`), never on the stable address.

## 1.0.0

The first release: a community map of good places to smoke outdoors,
anywhere in the world.

### App (Android, iOS, web, Linux, Windows, macOS)

- **Map**: spots on an OpenStreetMap map (dark theme with CARTO tiles), spot
  search by name (Ctrl+K) and a compass that turns the map back to north.
  One button switches between the street map, satellite imagery (Esri) and
  a public transport map with every line and stop, worldwide (Thunderforest,
  or ÖPNVKarte without a key).
- **3D view**: the map tilts back with perspective and every building
  stands as a block with its OpenStreetMap height (OpenFreeMap), over all
  three maps, slightly see-through so the map stays readable. Two fingers
  dragged up or down (on a touchpad Shift + swipe) tilt the map smoothly
  from 2D into 3D and back; the 3D button does the same in one step.
- **Gestures**: a two-finger touchpad swipe moves the map, a pinch zooms, a
  mouse wheel zooms towards the cursor.
- **Spots**: add spots anywhere in the world, with photos and a location
  picker (address search, coordinates or map links); every spot has photos,
  the weather for the next hours (Open-Meteo), reviews and ratings, comments
  and photo updates from people who were there; share links and directions
  in the maps app.
- **No-consumption zones (Verbotszonen)** after § 5 KCanG from OpenStreetMap
  data, in Germany only: within sight of schools, children's and youth
  facilities, playgrounds (private ones too) and public sports facilities,
  pedestrian zones from 7 to 20 h, and places tagged `smoking:cannabis=no`.
  Spots show whether they lie in one, and adding a spot in one warns first.
  Off by default; the first time they are switched on in a session, the app
  explains what they can and cannot tell. Outside Germany the zone buttons
  are hidden.
- **Feed** of the newest updates, or only of people you follow ("Following").
- **Profiles** with profile pictures, the user's spots and updates,
  followers and following; follow anyone from their name.
- **Activity**: a bell on the profile tab shows who followed you, commented,
  or liked or rated your spots.
- **Saved lists**: save spots to your own lists.
- **Reports** on spots, updates, reviews and comments.
- **Legal**: Impressum, privacy policy and community rules in the app and on
  the web (operator details come from the server's config); "Download my
  data" gives every user a copy of what is stored about them.
- **Admin tools**: reports, users (ban), spots, tags and backend updates,
  with two-factor codes for admin actions.
- **Automatic updates** for Android, Linux, Windows and macOS: the apps
  install only files listed in checksums signed with the project's release
  key. Settings → Updates → "Update channel" switches between stable
  releases and dev builds.
- **Dev builds** say so when they start, with a way to the stable version
  (on the web: the stable web app; elsewhere: the latest release), and can
  be told to keep quiet for 30 days.
- Android home screen widgets (nearest spot, quick actions); German and
  English.

### Backend

- Go API with MariaDB 11.4 (spatial index for spots in view), rate limits
  per user and per client.
- Zone layer: places from OpenStreetMap (Overpass) by tile, cached for a
  week; only tiles in Germany are fetched, and places outside it are left
  out. A busy Overpass makes the app wait and ask again instead of failing.
- `install-backend.sh`: installs or updates the backend as a sandboxed
  systemd service, from releases (`--release`) or dev builds (`--dev`);
  checks the signed checksums, goes back to the previous binary when an
  update does not start, and never switches to a build with older database
  migrations. Admins can start updates from the app. `--instance NAME`
  installs a second backend next to the first (e.g. releases next to dev
  builds, each with its own database).

### Releases

- Built by GitHub Actions from a tag `vX.Y.Z`: backend for Linux amd64 and
  arm64, apps for every platform, `SHA256SUMS.txt` (backend) and
  `SHA256SUMS-apps.txt` (apps) signed with `ssh-keygen -Y sign`, and build
  provenance for every file. The web app goes to GitHub Pages.
- Dev builds and releases talk to separate backends (`API_URL_DEV`,
  `API_URL_RELEASE`).
