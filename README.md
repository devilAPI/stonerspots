# Stonerspots

A community map for finding good places to smoke weed outdoors: nice benches,
rivers, lakes, viewpoints. People add spots, post photo updates, and browse a
small picture feed. Launch region: Germany, Austria, Switzerland, Liechtenstein.

- **App:** Flutter (Android, iOS, web, Linux desktop for development) in [`app/`](app)
- **API:** Go + chi + MariaDB (spatial index for "spots in view") in [`backend/`](backend)
- **Plan / decisions:** [`docs/superpowers/plans/`](docs/superpowers/plans)

> Spots are community content. Consumption near schools, playgrounds and in
> pedestrian zones is restricted by law (KCanG in Germany); a zone check is not
> built yet. Users must confirm they are 18+.

## Run it locally

```sh
# 1. database (MariaDB 11.4 on 127.0.0.1:3307)
make db-up

# 2. API on :8080 (config.yaml: database, JWT secret, CORS, ...; env vars override it)
cd backend
cp config.example.yaml config.yaml
go run ./cmd/api

# 3. app (Linux desktop compiles fastest; use -d chrome / an emulator otherwise)
cd app
cp env/local.example.json env/local.json   # then fill in CARTO_KEY (optional)
flutter run -d linux --dart-define-from-file=env/local.json
```

The table layout is in `backend/schema.example.sql` (generated from
`backend/migrations/`, which the API applies on start).

Tests: `make test` (backend, needs the database) and `cd app && flutter test`.

Optional demo data from a GPX file: `cd backend && go run ./cmd/seedgpx -gpx spots.gpx`.

## Install the backend on a server

`install-backend.sh` downloads the newest backend build from the GitHub
releases (amd64 or arm64), verifies its checksum and installs it as the
systemd service `stonerspots-backend`. Run it again to update.

One-liner, straight from GitHub:

```sh
# newest release
curl -fsSL https://raw.githubusercontent.com/devilAPI/stonerspots/main/install-backend.sh | sudo bash
# newest dev build
curl -fsSL https://raw.githubusercontent.com/devilAPI/stonerspots/main/install-backend.sh | sudo bash -s -- --dev
```

Or from a checkout: `sudo ./install-backend.sh [--dev]`.

Binaries go to `/opt/stonerspots`, photos to `/var/lib/stonerspots/uploads`.
The first run creates `/etc/stonerspots/config.yaml` with a random JWT secret;
fill in the database there (MariaDB 11.4, not installed by the script), then
`sudo systemctl start stonerspots-backend`.

## Web app on GitHub Pages

The `Publish web app` workflow deploys the web build of the newest release to
https://devilapi.github.io/stonerspots/ and of the newest dev build to `/dev/`.
For it to reach a backend:

- repository secret `API_URL`: public **HTTPS** URL of the API, e.g.
  `https://api.example.com/api/v1` (compiled into every build, so it is public)
- backend `allowed_origins: [https://devilapi.github.io]` (CORS) and
  `public_base_url` set to the backend's HTTPS origin so photo URLs work, in its
  `config.yaml` (or the env vars `ALLOWED_ORIGINS` / `PUBLIC_BASE_URL`)

The database credentials are only ever set on the backend server (its
`config.yaml`), never in the app or its build.

## Map tiles

- Light theme: OpenStreetMap standard tiles (fine for development, not for heavy
  production traffic).
- Dark theme: CARTO Dark Matter, needs a free key from
  <https://carto.com/basemaps/apikey>, passed as `CARTO_KEY`. Without a key the
  app falls back to the OpenStreetMap tiles. The key is visible in the built app;
  restrict it in CARTO's dashboard.
- Satellite previews: Esri World Imagery. Check CARTO's and Esri's terms before
  a commercial launch.

Map data © OpenStreetMap contributors.
