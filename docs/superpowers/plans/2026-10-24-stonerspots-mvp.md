# Stonerspots MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A community map app (Android, iOS, web) where people find, add and update "stoner spots" (benches, rivers, viewpoints), with photos and a sortable/filterable picture feed. Launch region: Germany, Austria, Switzerland and Liechtenstein (DACH).

**Architecture:** Flutter client talks to a stateless Go REST API (JSON over HTTPS). MariaDB 11.4 stores everything; spots use a `POINT NOT NULL` column (x = lon, y = lat) with a SPATIAL INDEX for fast "spots in view / near me" queries. Photos are stored on local disk behind a `Storage` interface (swap for S3-compatible storage later) and served via a static route.

**Tech Stack:**
- Backend: Go 1.23, `chi` router, `database/sql` + `go-sql-driver/mysql` (MariaDB-compatible), `golang-migrate`, `golang-jwt/jwt/v5`, `bcrypt` (`golang.org/x/crypto`), `disintegration/imaging`. Tests: stdlib `testing` + `httptest` against a real MariaDB reachable via `DATABASE_URL` (docker compose or local install; no DB mocks).
- App: Flutter 3.x, Riverpod, go_router, dio, `flutter_map` + `flutter_map_marker_cluster` (OpenStreetMap tiles, no API key, works on web), `geolocator`, `image_picker`, `flutter_secure_storage`.

**Spec:** No separate spec document. The requirements are the conversation summary in "Decisions" below. The user chose to skip the written-design step.

## Decisions (user's vs. my calls)

User decided: Flutter (Android/iOS/web); Go backend; MySQL-family DB (not Postgres); the user's machine is getting MariaDB installed, so **MariaDB 11.4** is the target; no PHP; community-driven; map of spots; photos and updates per spot; mini social feed with picture posts, sortable and filterable; reviews/ratings **later**; Region at first: Germany, Austria, Switzerland, Liechtenstein (DACH); map opens on the nicest spots nearby, and it must be fast.

My calls (change any of these in review):
- Monorepo: `backend/` and `app/`.
- Auth: email + password. Short-lived JWT access token (15 min) plus rotating refresh token (30 days, stored hashed).
- "Nice" ranking before reviews exist: one "nice" vote per user per spot; `like_count` on the spot is the ranking signal.
- Feed items are spot *updates* (text + photos). Creating a spot creates its first update. Sorts: `new`, `top`, `nearby`. Filters: `category`.
- Categories: `bench`, `river`, `lake`, `viewpoint`, `forest`, `park`, `other`.
- UI languages: German (default) and English via Flutter l10n.
- Safety basics in MVP: 18+ confirmation at signup, a report button, reports hide content at 3 distinct reporters. Rationale: community content plus app-store review.
- Spots must be inside a rough DACH bounding box (lat 45.8–55.1, lon 5.8–17.2) for the launch. The box also covers parts of neighbouring countries (Poland, Czechia, Italy, France, etc.); accepted for the MVP.
- Execution scope: **Tasks 1–10 only**. Task 11 (packaging/deployment) is dropped.
- Map fallback centre is (49.5, 10.5) at zoom 6 (middle of DACH); UI stays German + English.

## Global Constraints

- Go module name `stonerspots/backend`; all API routes under `/api/v1`.
- Coordinates are always `lat`, `lon` (float64, degrees) in JSON. MariaDB `POINT(x, y)` is stored as **x = lon, y = lat** (no axis swap, SRID 0); build points with `POINT(lon, lat)`, read with `ST_X` (lon) / `ST_Y` (lat), and compute distances with `ST_Distance_Sphere(a, b)` (metres).
- IDs are `BIGINT UNSIGNED` auto-increment, serialized as JSON numbers.
- Photo limits: max 8 MB upload, JPEG/PNG/WebP only (sniffed from bytes, not the header), max 4 photos per update. Stored as JPEG, long edge max 1600 px, plus a 400 px thumbnail. EXIF stripped.
- List endpoints cap `limit` at 50 (default 20) and use cursor pagination. Exception: `GET /spots` and `/spots/nearby` cap at 200 so the map can load a padded area at once.
- Errors are JSON `{"error": {"code": "<snake_case>", "message": "<text>"}}` with the matching HTTP status.
- No PHP anywhere.

## Review Focus

Behaviour the spec implies that no feature task asks for directly. Each line is pinned by a test in the task named in brackets.

1. Lat/lon swapped or out of range, e.g. `lat=200`, or `lat`/`lon` swapped so the point lands in the ocean → 400 `invalid_location`, and the region box rejects swapped values. [Task 3]
2. Upload that claims `image/jpeg` but is not an image, a giant file, or a photo with GPS EXIF → rejected or stripped; the stored file must contain no EXIF. [Task 4]
3. Map bounding box that is huge (whole world), inverted (`south > north`) or empty → 400 for inverted, capped result count for huge, `[]` (not `null`) for empty. [Task 3]
4. Several feed items with identical `created_at` → cursor pagination neither skips nor repeats items (tie-break on id). [Task 5]
5. Someone adds a spot a few metres from an existing one → 409 `possible_duplicate` with the nearby spot's id unless `force=true`. [Task 3]

---

## Parallel execution layout

Shared contracts are created up front so tasks can run at the same time without touching each other's files.

- **Wave 1 (parallel):** Task 1 (backend foundation) and Task 7 (Flutter foundation).
- **Wave 2 (all parallel, each in its own git worktree):** backend Tasks 2, 3, 4, 5, 6 and app Tasks 8, 9, 10.
- **Wave 3 (integration, sequential):** merge the branches, wire "creating a spot creates its first update" (Tasks 3+5), run `go test ./...` and `flutter test`, and run the app against the local backend.

File ownership rule: a task only edits the files listed under its own **Files**. Do not run `go mod tidy` or add dependencies; all backend and Flutter dependencies are added in Tasks 1 and 7. If a task truly needs another dependency, say so in its report instead of editing `go.mod` or `pubspec.yaml`.

## Task 1: Backend foundation (skeleton, MariaDB, all migrations, package stubs, token verification)

**Files:**
- Create: `backend/go.mod`, `backend/cmd/api/main.go`, `backend/internal/config/config.go`, `backend/internal/db/db.go`, `backend/internal/httpx/httpx.go`, `backend/internal/app/app.go`, `backend/internal/server/{server.go,health_test.go}`, `backend/internal/testutil/{testdb.go,token.go}`, `backend/internal/auth/{token.go,middleware.go,token_test.go,mount.go}`, stub `mount.go` in each of `backend/internal/{spots,photos,feed,engagement}/`, `backend/migrations/0001..0006_*.{up,down}.sql`, `docker-compose.yml`, `.gitignore`, `Makefile`

**Interfaces:**
- Produces:
  - `config.Load() (Config, error)`; env vars `DATABASE_URL` (default `stonerspots:stonerspots@tcp(127.0.0.1:3307)/stonerspots?parseTime=true&multiStatements=true`), `JWT_SECRET`, `UPLOAD_DIR`, `ADDR`, `PUBLIC_BASE_URL`.
  - `db.Open(dsn string) (*sql.DB, error)`, `db.Migrate(dsn, dir string) error`.
  - `app.Deps struct { DB *sql.DB; Cfg config.Config }` (package `internal/app`, imported by every module, so there are no import cycles).
  - Each module package exposes `Mount(r chi.Router, d app.Deps)`; Task 1 ships these as no-op stubs and `server.New(d app.Deps) http.Handler` calls all five under `/api/v1`. Later tasks fill in `Mount` and never edit `server.go`.
  - `httpx.JSON(w, status, v)`, `httpx.Error(w, status, code, msg)`.
  - `auth.IssueAccess(secret []byte, userID uint64, ttl time.Duration) (string, error)` (HS256, `sub` = user id), `auth.Middleware(secret []byte) func(http.Handler) http.Handler` (401 `unauthorized` if missing or invalid), `auth.Optional(secret []byte)` (no 401 when absent), `auth.UserID(ctx) (uint64, bool)`.
  - `testutil.NewDB(t *testing.T) *sql.DB`: connects via `DATABASE_URL`, creates a throwaway schema, runs the migrations, drops the schema on cleanup. If no DB is reachable it calls `t.Fatal` with a clear message.
  - `testutil.Token(t *testing.T, userID uint64) string`: a valid access token for the test `JWT_SECRET`; `testutil.NewUser(t, db) uint64` inserts a user row and returns its id.
  - **All migrations** (the shared schema contract): `0001_users`, `0002_refresh_tokens(id, user_id, token_hash, family_id, expires_at, revoked_at, created_at)`, `0003_spots`, `0004_photos`, `0005_updates`, `0006_likes_reports`, with columns exactly as listed in Tasks 2–6 below.

- [ ] **Step 1:** `docker-compose.yml` with `mariadb:11.4` on port 3307 (user/password/db all `stonerspots`, healthcheck). `.gitignore` for Go, Flutter, `uploads/`, `.env`. `Makefile` targets `db-up`, `test`, `run`.
- [ ] **Step 2: Write failing tests:** `TestHealth` (`GET /api/v1/health` returns 200 `{"status":"ok","db":"ok"}`), `TestTokenRoundTrip`, `TestMiddlewareRejectsMissingExpiredAndTamperedToken`, `TestOptionalAllowsAnonymous`, `TestMigrationsApplyAndRollBack`.
- [ ] **Step 3:** Run `cd backend && go test ./...`. Expected: FAIL (does not compile / DB missing).
- [ ] **Step 4:** Implement everything above. Verify the spatial column works on MariaDB in `TestMigrationsApplyAndRollBack`: insert `POINT(lon, lat)` into `spots`, and assert `ST_Y(location)` returns the lat and `EXPLAIN SELECT … WHERE MBRContains(…)` lists the spatial index.
- [ ] **Step 5:** Run `go test ./...`. Expected: PASS.
- [ ] **Step 6:** Commit `chore: backend foundation`.

## Task 2: Auth endpoints (register, login, refresh)

**Files:**
- Create/Modify: `backend/internal/auth/{service.go,handler.go,mount.go,auth_test.go}` (owns `mount.go`; Task 1 already provides the token and middleware code, which this task does not change)

**Interfaces:**
- Consumes: `auth.IssueAccess`, `app.Deps`, tables `users`, `refresh_tokens`.
- Produces:
  - `POST /api/v1/auth/register` `{email, password, display_name, adult: true}` → `201 {access_token, refresh_token, user}`; `adult` must be `true` (else 400 `adult_required`); password ≥ 10 chars; duplicate email → 409 `email_taken`.
  - `POST /api/v1/auth/login`, `POST /api/v1/auth/refresh` (rotates; reusing an old refresh token revokes the whole family).
  - `GET /api/v1/me` (auth).

- [ ] **Step 1:** Write failing tests in `auth_test.go`: `TestRegisterLoginRoundTrip`, `TestRegisterRequiresAdult`, `TestDuplicateEmail409`, `TestWrongPasswordDoesNotRevealWhetherEmailExists` (same 401 body for both cases), `TestRefreshRotates`, `TestReusedRefreshTokenRevokesFamily`, `TestMeReturnsCurrentUser`.
- [ ] **Step 2:** Run `go test ./internal/auth`. Expected: FAIL.
- [ ] **Step 3:** Implement. bcrypt cost 12, emails lower-cased and trimmed, refresh tokens are 32 random bytes (base64url), stored as SHA-256. Access token TTL 15 min, refresh 30 days.
- [ ] **Step 4:** Run `go test ./...`. Expected: PASS.
- [ ] **Step 5:** Commit `feat: email/password auth with rotating refresh tokens`.

## Task 3: Spots (create, get, map query, nearby, duplicate check)

**Files:**
- Create: `backend/internal/spots/{model.go,repo.go,handler.go,spots_test.go}`, `backend/migrations/0003_spots.up.sql` (+ down)

**Interfaces:**
- Consumes: `auth.Middleware`, `auth.UserID`, `testutil.Token`, `testutil.NewUser`. Table `spots` is created by Task 1's `0003_spots` migration. The Task 1 `spots/mount.go` stub is replaced by this task, which owns the package.
- Produces:
  - Table (already migrated): `spots(id, user_id, title, description, category ENUM(...), location POINT NOT NULL, like_count INT DEFAULT 0, status ENUM('active','hidden') DEFAULT 'active', created_at, SPATIAL INDEX(location))`.
  - `type Spot struct { ID uint64; Title, Description, Category string; Lat, Lon float64; LikeCount int; CreatedAt time.Time; CoverURL string; DistanceM *float64 }`.
  - `POST /api/v1/spots` (auth) `{title, description, category, lat, lon, force?}`; `GET /api/v1/spots/{id}`.
  - `GET /api/v1/spots?south=&west=&north=&east=&category=&limit=` returns spots in the bounding box, best (`like_count` desc, then `id`) first, via `MBRContains` so the spatial index is used.
  - `GET /api/v1/spots/nearby?lat=&lon=&radius_m=&limit=` sorted by `ST_Distance_Sphere`, radius max 50 000.
  - Repo: `Create(ctx, Spot, userID) (uint64, error)`, `InBBox(ctx, BBox, filter) ([]Spot, error)`, `Nearby(ctx, lat, lon float64, radiusM, limit int) ([]Spot, error)`, `FindWithin(ctx, lat, lon, meters float64) (*Spot, error)`.

- [ ] **Step 1:** Write failing tests: `TestCreateAndGetSpot`; `TestRejectsOutOfRangeAndSwappedCoordinates` (lat=200 and lat/lon swapped, both 400 `invalid_location`); `TestRejectsOutsideRegion` (e.g. Paris and the Atlantic; Berlin and Vienna are accepted); `TestInvertedBBox400`; `TestHugeBBoxIsCappedToLimit`; `TestEmptyBBoxReturnsEmptyArray` (JSON body is `[]`); `TestBBoxOrdersByLikeCountThenID`; `TestNearbyOrdersByDistance`; `TestDuplicateWithin25mReturns409WithExistingID`; `TestForceCreatesDuplicate`; `TestHiddenSpotsAreExcluded`; `TestCreateRequiresAuth`.
- [ ] **Step 2:** Run `go test ./internal/spots`. Expected: FAIL.
- [ ] **Step 3:** Implement `Mount`, including `Repo` and handlers. Validate title (3–80), description (≤ 1000), category membership. Use `ST_AsText`/`ST_Latitude`/`ST_Longitude` to read coordinates back. Add an `EXPLAIN` assertion test, `TestBBoxQueryUsesSpatialIndex`, that the plan's `key` is the spatial index.
- [ ] **Step 4:** Run `go test ./...`. Expected: PASS.
- [ ] **Step 5:** Commit `feat: spots with spatial queries`.

## Task 4: Photo upload and storage

**Files:**
- Create: `backend/internal/photos/{storage.go,process.go,handler.go,photos_test.go}`; replaces the Task 1 stub `photos/mount.go`, whose `Mount` also serves the static route `/media/*` from `Cfg.UploadDir`. The `photos` table comes from Task 1's `0004_photos`.

**Interfaces:**
- Consumes: `auth.Middleware`, `testutil.*`.
- Produces:
  - `type Storage interface { Put(ctx, key string, r io.Reader) error; Delete(ctx, key string) error; URL(key string) string }` and `NewLocalStorage(dir, baseURL string) Storage`.
  - `process.Normalize(r io.Reader, maxBytes int64) (full, thumb []byte, w, h int, err error)`: sniffs the type, decodes, auto-orients from EXIF, then re-encodes without metadata.
  - `POST /api/v1/photos` (auth, multipart `file`) → `201 {id, url, thumb_url}`. The photo is "unattached" until an update references its id (Task 5).
  - Table (already migrated): `photos(id, user_id, key, thumb_key, width, height, update_id NULL, created_at)`.

- [ ] **Step 1:** Write failing tests: `TestUploadJPEGReturnsURLs`; `TestRejectsTextFileWithJPEGContentType`; `TestRejectsOver8MB`; `TestStripsGPSExif` (fixture with GPS EXIF; re-read output bytes, assert no `Exif` marker); `TestLongEdgeResizedTo1600`; `TestRequiresAuth`.
- [ ] **Step 2:** Run `go test ./internal/photos`. Expected: FAIL.
- [ ] **Step 3:** Implement, using `http.MaxBytesReader` and file keys of the form `yyyy/mm/<random>.jpg`.
- [ ] **Step 4:** Run `go test ./...`. Expected: PASS.
- [ ] **Step 5:** Commit `feat: photo upload with resize and exif stripping`.

## Task 5: Updates and feed

**Files:**
- Create: `backend/internal/feed/{repo.go,handler.go,cursor.go,feed_test.go}`; replaces the Task 1 stub `feed/mount.go`. Tables come from Task 1's `0005_updates`. Tests insert spots, users and photos with plain SQL, so this task does not depend on the other tasks' code. Exports `feed.CreateUpdate(ctx, db, userID, spotID uint64, body string, photoIDs []uint64) (uint64, error)` so the integration wave can call it from the spots handler ("creating a spot creates its first update").

**Interfaces:**
- Consumes: `auth.Middleware`, `testutil.*`; tables `spots`, `photos`, `users`.
- Produces:
  - Table (already migrated): `spot_updates(id, spot_id, user_id, body, status, created_at, INDEX(created_at, id))`; `photos.update_id` FK.
  - `POST /api/v1/spots/{id}/updates` (auth) `{body, photo_ids[≤4]}`. Photos must belong to the caller and be unattached (else 400 `invalid_photo`).
  - `GET /api/v1/feed?sort=new|top|nearby&category=&lat=&lon=&cursor=&limit=` → `{items: [FeedItem], next_cursor}`. `nearby` requires lat/lon (else 400).
  - `type FeedItem struct { ID uint64; Body string; Photos []PhotoRef; CreatedAt time.Time; Author {ID, DisplayName}; Spot {ID, Title, Category, Lat, Lon, LikeCount} }`.
  - `cursor.Encode(sortKey, id)` / `cursor.Decode(string)` are opaque base64 JSON.

- [ ] **Step 1:** Write failing tests: `TestPostUpdateWithPhotos`; `TestCannotAttachSomeoneElsesPhoto`; `TestFeedNewestFirst`; `TestFeedTopSortsBySpotLikeCount`; `TestFeedNearbyRequiresLatLon`; `TestFeedCategoryFilter`; `TestCursorPaginationWithIdenticalTimestamps` (25 rows with the same `created_at`, page size 10, union of pages equals all 25 exactly once); `TestMalformedCursor400`; `TestHiddenUpdatesExcluded`.
- [ ] **Step 2:** Run `go test ./internal/feed`. Expected: FAIL.
- [ ] **Step 3:** Implement with keyset pagination (`(sort_key, id) < (?, ?)`); photos fetched in one batched query per page (no N+1).
- [ ] **Step 4:** Run `go test ./...`. Expected: PASS.
- [ ] **Step 5:** Commit `feat: spot updates and filterable feed`.

## Task 6: Likes and reports

**Files:**
- Create: `backend/internal/engagement/{handler.go,repo.go,engagement_test.go}`; replaces the Task 1 stub `engagement/mount.go`. Tables come from Task 1's `0006_likes_reports`: `spot_likes(user_id, spot_id, created_at, PK(user_id, spot_id))`, `reports(id, user_id, target_type ENUM('spot','update'), target_id, reason, created_at, UNIQUE(user_id, target_type, target_id))`. Tests insert spots and updates with plain SQL.

**Interfaces:**
- Consumes: `auth.Middleware`, `testutil.*`.
- Produces:
  - `PUT /api/v1/spots/{id}/like` and `DELETE …/like` (auth, idempotent). They maintain `spots.like_count` in the same transaction as `spot_likes(user_id, spot_id, PK(user_id, spot_id))`.
  - `POST /api/v1/reports` `{target_type: "spot"|"update", target_id, reason}`. One report per user per target; at 3 distinct reporters the target's `status` becomes `hidden`.

- [ ] **Step 1:** Write failing tests: `TestLikeIsIdempotent` (double PUT leaves count 1); `TestUnlikeNeverGoesNegative`; `TestConcurrentLikesKeepCountConsistent` (20 goroutines, distinct users); `TestThreeReportsHideTarget`; `TestSameUserReportingTwiceCountsOnce`.
- [ ] **Step 2:** Run `go test ./internal/engagement`. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `go test ./...`. Expected: PASS.
- [ ] **Step 5:** Commit `feat: spot likes and abuse reports`.

## Task 7: Flutter scaffold, theme, API client, auth flow

**Files:**
- Create: `app/` via `flutter create --org de.stonerspots --platforms android,ios,web app`; `app/lib/{main.dart,router.dart}`, `app/lib/core/{api_client.dart,token_store.dart,theme.dart}`, `app/lib/features/auth/{auth_repository.dart,auth_controller.dart,login_screen.dart,register_screen.dart}`, `app/lib/l10n/{app_de.arb,app_en.arb}`, `app/test/auth/auth_controller_test.dart`, `app/lib/core/models.dart`, placeholder screens `app/lib/features/{map/map_screen.dart,spots/spot_detail_screen.dart,spots/add_spot_screen.dart,feed/feed_screen.dart}` (each just a `Scaffold` with a title; Tasks 8, 9 and 10 replace them), `app/lib/core/providers.dart`

**Interfaces:**
- Produces:
  - `pubspec.yaml` with **every** dependency the app needs, added now so later tasks never edit it: `flutter_riverpod`, `go_router`, `dio`, `flutter_map`, `flutter_map_marker_cluster`, `latlong2`, `geolocator`, `image_picker`, `flutter_secure_storage`, `flutter_localizations`, `intl`, `cached_network_image`, dev: `mocktail`.
  - `core/models.dart`: immutable `Spot{id,title,description,category,lat,lon,likeCount,coverUrl,distanceM}`, `PhotoRef{id,url,thumbUrl}`, `Author{id,displayName}`, `FeedItem{id,body,photos,createdAt,author,spot}`, `User{id,email,displayName}`, each with `fromJson`, matching the API shapes in Tasks 3 and 5.
  - `core/providers.dart`: Riverpod `apiClientProvider`, `spotsRepositoryProvider`, `feedRepositoryProvider`, `updatesRepositoryProvider` declared as `throw UnimplementedError()` placeholders that Tasks 8, 9 and 10 each override-implement in their own feature file.
  - Router (`router.dart`) already declares the routes `/` (map), `/feed`, `/spot/:id`, `/spot/new`, `/login`, `/register`, wired to the placeholder screens, with the login redirect for `/spot/new`.
  - `ApiClient` (dio): base URL from `--dart-define=API_URL`; attaches the bearer token; on 401 performs one refresh then retries; exposes `Future<T> get/post/put/delete`.
  - `TokenStore { Future<Tokens?> read(); Future<void> write(Tokens); Future<void> clear(); }` (secure storage; in-memory fallback on web tests).
  - `AuthController` (Riverpod `AsyncNotifier<User?>`) with `login`, `register`, `logout`.
  - Router redirect: the map is public, while add-spot and post-update require login.

- [ ] **Step 1:** Write failing tests with a fake `AuthRepository`: `login stores tokens and exposes user`, `failed login surfaces error code`, `401 triggers one refresh then retries`, `register is blocked until the 18+ box is ticked`.
- [ ] **Step 2:** Run `cd app && flutter test`. Expected: FAIL.
- [ ] **Step 3:** Implement the above. Theme is dark-first, green accent. All strings come from ARB files (de default).
- [ ] **Step 4:** Run `flutter test && flutter analyze`. Expected: PASS and no issues.
- [ ] **Step 5:** Commit `feat(app): scaffold, api client, auth`.

## Task 8: Map screen (the home screen)

**Files:**
- Create: `app/lib/features/map/{map_screen.dart,spots_controller.dart,spot_marker.dart,spot_preview_sheet.dart}`, `app/lib/features/spots/{spot.dart,spots_repository.dart}`, `app/test/map/spots_controller_test.dart`
- Modify: `app/android/app/src/main/AndroidManifest.xml` (location permissions), `app/ios/Runner/Info.plist` (`NSLocationWhenInUseUsageDescription`)

**Interfaces:**
- Consumes: `ApiClient`.
- Produces:
  - `SpotsRepository.inBounds(LatLngBounds, {String? category}) → Future<List<Spot>>`.
  - `SpotsController`: debounced (400 ms) bbox fetch on map move; cancels stale requests; keeps previous markers visible while loading.
  - Map starts centred on the user's location, falling back to the region centre (49.5, 10.5, zoom 6) if permission is denied; top-N nicest spots are drawn larger; marker clustering; category filter chips; tapping a marker opens a bottom-sheet preview (cover photo, title, likes, "open").

- [ ] **Step 1:** Write failing tests: `debounces rapid camera moves into one request`, `stale response does not overwrite newer one`, `keeps old markers while loading`, `permission denied falls back to region centre`.
- [ ] **Step 2:** Run `flutter test test/map`. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `flutter test && flutter analyze`, then `flutter run -d chrome --dart-define=API_URL=http://localhost:8080/api/v1` against the local backend and check that the map loads and markers appear.
- [ ] **Step 5:** Commit `feat(app): map home screen`.

## Task 9: Spot detail and add-spot flow

**Files:**
- Create: `app/lib/features/spots/{spot_detail_screen.dart,add_spot_screen.dart,location_picker.dart,photo_uploader.dart,updates_repository.dart}`, `app/test/spots/add_spot_controller_test.dart`

**Interfaces:**
- Consumes: `POST /photos`, `POST /spots`, `POST /spots/{id}/updates`, like and report endpoints.
- Produces:
  - `PhotoUploader.upload(XFile) → Future<UploadedPhoto>` with progress stream.
  - `AddSpotController` handles: pick a point on a map (defaults to the current position), title, category, description, up to 4 photos. A 409 `possible_duplicate` shows "There's already a spot here — open it or add anyway".
  - Detail screen: photo gallery, description, update timeline, like button, report menu, "post update" button (login-gated).

- [ ] **Step 1:** Write failing tests: `submit is disabled until title, category and point are set`, `409 duplicate surfaces the existing spot and allows force`, `max 4 photos enforced`, `upload failure keeps form state`.
- [ ] **Step 2:** Run `flutter test test/spots`. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `flutter test && flutter analyze`; manually add a spot with a photo on web and check that it appears on the map and in the detail screen.
- [ ] **Step 5:** Commit `feat(app): spot detail and add-spot`.

## Task 10: Feed screen

**Files:**
- Create: `app/lib/features/feed/{feed_screen.dart,feed_controller.dart,feed_card.dart,feed_repository.dart}`, `app/test/feed/feed_controller_test.dart`
- Modify: `app/lib/router.dart` (bottom nav: Map, Feed, Profile)

**Interfaces:**
- Produces: `FeedController` (infinite scroll via cursor; `setSort(FeedSort)`, `setCategory(String?)` reset the list; `nearby` sort asks for location first and falls back to `new` if denied). `FeedCard` shows a photo (thumbnail first), author, spot name (taps through to the spot), time, like.

- [ ] **Step 1:** Write failing tests: `changing sort resets pagination`, `loads next page when near end and stops at null cursor`, `nearby falls back to new when location denied`, `no duplicate items after refresh`.
- [ ] **Step 2:** Run `flutter test test/feed`. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `flutter test && flutter analyze`; check the feed manually on web and on an Android emulator.
- [ ] **Step 5:** Commit `feat(app): picture feed with sort and filter`.

## Out of scope for this plan

- Task 11 (Docker/CI/deployment packaging) was dropped by the user for now. Note for later: the public OpenStreetMap tile server is not meant for heavy production use.
- Reviews and ratings (planned for after the MVP).
- Bubatzkarte or any consumption-ban-zone checking (decided to skip for now).
- Push notifications, comments, follows, DMs, admin dashboard, S3 storage, and languages beyond de/en.
