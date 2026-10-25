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

# 2. API on :8080
cd backend
DATABASE_URL='root:stonerspots@tcp(127.0.0.1:3307)/stonerspots?parseTime=true&multiStatements=true' \
JWT_SECRET=change-me UPLOAD_DIR=./uploads go run ./cmd/api

# 3. app (Linux desktop compiles fastest; use -d chrome / an emulator otherwise)
cd app
cp env/local.example.json env/local.json   # then fill in CARTO_KEY (optional)
flutter run -d linux --dart-define-from-file=env/local.json
```

Tests: `make test` (backend, needs the database) and `cd app && flutter test`.

Optional demo data from a GPX file: `cd backend && go run ./cmd/seedgpx -gpx spots.gpx`.

## Web app on GitHub Pages

The `Publish web app` workflow deploys the web build of the newest release to
https://devilapi.github.io/stonerspots/ and of the newest dev build to `/dev/`.
For it to reach a backend:

- repository secret `API_URL`: public **HTTPS** URL of the API, e.g.
  `https://api.example.com/api/v1` (compiled into every build, so it is public)
- backend env `ALLOWED_ORIGINS=https://devilapi.github.io` (CORS) and
  `PUBLIC_BASE_URL` set to the backend's HTTPS origin so photo URLs work

The database credentials (`DATABASE_URL`) are only ever set on the backend
server, never in the app or its build.

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
