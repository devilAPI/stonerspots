# Changelog

Releases are the GitHub releases `vX.Y.Z`; how one is made is in the README,
"Releasing 1.0". Development builds (`dev-<n>`) are not listed here.

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
