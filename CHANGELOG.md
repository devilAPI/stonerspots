# Changelog

Releases are the GitHub releases `vX.Y.Z`; how one is made is in the README,
"Releasing 1.0". Development builds (`dev-<n>`) are not listed here.

## 1.0.0

The first release: a community map of good places to smoke outdoors,
anywhere in the world.

### App (Android, iOS, web, Linux, Windows, macOS)

- **Map**: spots on an OpenStreetMap map (dark theme with CARTO tiles,
  optional public transport layer), spot search by name (Ctrl+K) and a
  compass that turns the map back to north.
- **Spots**: add spots with photos and a location picker; every spot has
  photos, the weather for the next hours (Open-Meteo), reviews and ratings,
  comments and photo updates from people who were there; share links and
  directions in the maps app.
- **Feed** of the newest updates, or only of people you follow ("Following").
- **Profiles** with profile pictures, the user's spots and updates,
  followers and following; follow anyone from their name.
- **Activity**: a bell on the profile tab shows who followed you, commented,
  or liked or rated your spots.
- **Saved lists**: save spots to your own lists.
- **Reports** on spots, updates, reviews and comments.
- **Admin tools**: reports, users (ban), spots, tags and backend updates,
  with two-factor codes for admin actions.
- **Automatic updates** for Android, Linux, Windows and macOS: the apps
  install only files listed in checksums signed with the project's release
  key.
- Android home screen widgets (nearest spot, quick actions); German and
  English.

### Backend

- Go API with MariaDB 11.4 (spatial index for spots in view), rate limits
  per user and per client.
- `install-backend.sh`: installs or updates the backend as a sandboxed
  systemd service, from releases (`--release`) or dev builds (`--dev`);
  checks the signed checksums, goes back to the previous binary when an
  update does not start, and never switches to a build with older database
  migrations. Admins can start updates from the app.

### Releases

- Built by GitHub Actions from a tag `vX.Y.Z`: backend for Linux amd64 and
  arm64, apps for every platform, `SHA256SUMS.txt` (backend) and
  `SHA256SUMS-apps.txt` (apps) signed with `ssh-keygen -Y sign`, and build
  provenance for every file. The web app goes to GitHub Pages.
