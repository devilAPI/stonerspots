package lists_test

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"slices"
	"strings"
	"sync"
	"testing"

	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/config"
	"stonerspots/backend/internal/lists"
	"stonerspots/backend/internal/testutil"
)

type list struct {
	ID        uint64 `json:"id"`
	Name      string `json:"name"`
	IsDefault bool   `json:"is_default"`
	SpotCount int    `json:"spot_count"`
	CoverURL  string `json:"cover_url"`
}

type spot struct {
	ID       uint64   `json:"id"`
	Title    string   `json:"title"`
	CoverURL string   `json:"cover_url"`
	Tags     []string `json:"tags"`
}

func setup(t *testing.T) (*sql.DB, http.Handler) {
	t.Helper()
	db := testutil.NewDB(t)
	r := chi.NewRouter()
	lists.Mount(r, app.Deps{DB: db, Cfg: config.Config{
		JWTSecret: []byte(testutil.JWTSecret), PublicBaseURL: "http://test",
	}})
	return db, r
}

func newSpot(t *testing.T, db *sql.DB, owner uint64) uint64 {
	t.Helper()
	res, err := db.Exec(`INSERT INTO spots (user_id, title, description, location)
		VALUES (?, 's', 'd', ST_GeomFromText('POINT(10 50)'))`, owner)
	if err != nil {
		t.Fatal(err)
	}
	id, _ := res.LastInsertId()
	return uint64(id)
}

// addPhoto attaches a photo with the given status to a new update of the spot.
func addPhoto(t *testing.T, db *sql.DB, spot, owner uint64, key, status string) {
	t.Helper()
	res, err := db.Exec(`INSERT INTO spot_updates (spot_id, user_id, body) VALUES (?, ?, 'b')`, spot, owner)
	if err != nil {
		t.Fatal(err)
	}
	upd, _ := res.LastInsertId()
	if _, err := db.Exec("INSERT INTO photos (user_id, `key`, thumb_key, width, height, status, update_id) VALUES (?, ?, ?, 1, 1, ?, ?)",
		owner, key+".jpg", key+"_thumb.jpg", status, upd); err != nil {
		t.Fatal(err)
	}
}

func do(t *testing.T, h http.Handler, method, path string, user uint64, body string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	if user != 0 {
		req.Header.Set("Authorization", "Bearer "+testutil.Token(t, user))
	}
	w := httptest.NewRecorder()
	h.ServeHTTP(w, req)
	return w
}

func decode[T any](t *testing.T, w *httptest.ResponseRecorder) T {
	t.Helper()
	var v T
	if err := json.Unmarshal(w.Body.Bytes(), &v); err != nil {
		t.Fatalf("decode %q: %v", w.Body.String(), err)
	}
	return v
}

func nameBody(name string) string {
	b, _ := json.Marshal(map[string]string{"name": name})
	return string(b)
}

func create(t *testing.T, h http.Handler, user uint64, name string) list {
	t.Helper()
	w := do(t, h, "POST", "/lists", user, nameBody(name))
	if w.Code != http.StatusCreated {
		t.Fatalf("create %q: %d %s", name, w.Code, w.Body)
	}
	return decode[list](t, w)
}

func myLists(t *testing.T, h http.Handler, user uint64) []list {
	t.Helper()
	w := do(t, h, "GET", "/lists", user, "")
	if w.Code != 200 {
		t.Fatalf("lists: %d %s", w.Code, w.Body)
	}
	return decode[struct {
		Items []list `json:"items"`
	}](t, w).Items
}

func listByID(t *testing.T, h http.Handler, user, id uint64) list {
	t.Helper()
	for _, l := range myLists(t, h, user) {
		if l.ID == id {
			return l
		}
	}
	t.Fatalf("list %d not found", id)
	return list{}
}

func add(t *testing.T, h http.Handler, user, id, spot uint64) {
	t.Helper()
	if w := do(t, h, "PUT", fmt.Sprintf("/lists/%d/spots/%d", id, spot), user, ""); w.Code != 200 {
		t.Fatalf("add: %d %s", w.Code, w.Body)
	}
}

func spotsOf(t *testing.T, h http.Handler, user, id uint64) []spot {
	t.Helper()
	w := do(t, h, "GET", fmt.Sprintf("/lists/%d/spots", id), user, "")
	if w.Code != 200 {
		t.Fatalf("spots: %d %s", w.Code, w.Body)
	}
	return decode[struct {
		Items []spot `json:"items"`
	}](t, w).Items
}

func membership(t *testing.T, h http.Handler, user, spot uint64) []uint64 {
	t.Helper()
	w := do(t, h, "GET", fmt.Sprintf("/spots/%d/lists", spot), user, "")
	if w.Code != 200 {
		t.Fatalf("membership: %d %s", w.Code, w.Body)
	}
	return decode[struct {
		ListIDs []uint64 `json:"list_ids"`
	}](t, w).ListIDs
}

func count(t *testing.T, db *sql.DB, q string, args ...any) int {
	t.Helper()
	var n int
	if err := db.QueryRow(q, args...).Scan(&n); err != nil {
		t.Fatal(err)
	}
	return n
}

func TestEveryRouteNeedsLogin(t *testing.T) {
	_, h := setup(t)
	for _, c := range [][2]string{
		{"GET", "/lists"}, {"POST", "/lists"}, {"GET", "/lists/1"}, {"PATCH", "/lists/1"},
		{"DELETE", "/lists/1"}, {"GET", "/lists/1/spots"}, {"PUT", "/lists/1/spots/1"},
		{"DELETE", "/lists/1/spots/1"}, {"PUT", "/lists/default/spots/1"}, {"GET", "/spots/1/lists"},
	} {
		if w := do(t, h, c[0], c[1], 0, ""); w.Code != http.StatusUnauthorized {
			t.Errorf("%s %s: %d", c[0], c[1], w.Code)
		}
	}
}

func TestFavouritesExistOnceFromTheFirstRequest(t *testing.T) {
	db, h := setup(t)
	u := testutil.NewUser(t, db)
	var wg sync.WaitGroup
	for range 8 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if w := do(t, h, "GET", "/lists", u, ""); w.Code != 200 {
				t.Errorf("got %d", w.Code)
			}
		}()
	}
	wg.Wait()
	got := myLists(t, h, u)
	if len(got) != 1 || !got[0].IsDefault || got[0].SpotCount != 0 || got[0].CoverURL != "" {
		t.Fatalf("%+v", got)
	}
	if n := count(t, db, `SELECT COUNT(*) FROM spot_lists WHERE user_id = ?`, u); n != 1 {
		t.Fatalf("rows = %d", n)
	}
}

func TestSaveToFavouritesCreatesThemOnDemand(t *testing.T) {
	db, h := setup(t)
	u := testutil.NewUser(t, db)
	s := newSpot(t, db, u)
	for range 2 { // idempotent
		w := do(t, h, "PUT", fmt.Sprintf("/lists/default/spots/%d", s), u, "")
		if w.Code != 200 {
			t.Fatalf("got %d %s", w.Code, w.Body)
		}
		ids := decode[struct {
			ListIDs []uint64 `json:"list_ids"`
		}](t, w).ListIDs
		if len(ids) != 1 {
			t.Fatalf("list_ids = %v", ids)
		}
	}
	got := myLists(t, h, u)
	if len(got) != 1 || !got[0].IsDefault || got[0].SpotCount != 1 {
		t.Fatalf("%+v", got)
	}
	if ids := membership(t, h, u, s); !slices.Equal(ids, []uint64{got[0].ID}) {
		t.Fatalf("membership = %v", ids)
	}
}

func TestCreateRenameDelete(t *testing.T) {
	db, h := setup(t)
	u := testutil.NewUser(t, db)
	l := create(t, h, u, "  Summer by the river ")
	if l.Name != "Summer by the river" || l.IsDefault || l.SpotCount != 0 {
		t.Fatalf("%+v", l)
	}
	w := do(t, h, "GET", fmt.Sprintf("/lists/%d", l.ID), u, "")
	if w.Code != 200 || decode[list](t, w).Name != l.Name {
		t.Fatalf("get: %d %s", w.Code, w.Body)
	}
	w = do(t, h, "PATCH", fmt.Sprintf("/lists/%d", l.ID), u, nameBody("Rainy days"))
	if w.Code != 200 || decode[list](t, w).Name != "Rainy days" {
		t.Fatalf("rename: %d %s", w.Code, w.Body)
	}
	if w = do(t, h, "DELETE", fmt.Sprintf("/lists/%d", l.ID), u, ""); w.Code != http.StatusNoContent {
		t.Fatalf("delete: %d %s", w.Code, w.Body)
	}
	if w = do(t, h, "GET", fmt.Sprintf("/lists/%d", l.ID), u, ""); w.Code != 404 {
		t.Fatalf("after delete: %d", w.Code)
	}
	if w = do(t, h, "DELETE", fmt.Sprintf("/lists/%d", l.ID), u, ""); w.Code != 404 {
		t.Fatalf("second delete: %d", w.Code)
	}
}

func TestDefaultListFirstThenByName(t *testing.T) {
	db, h := setup(t)
	u := testutil.NewUser(t, db)
	create(t, h, u, "Zebra")
	create(t, h, u, "apple")
	var names []string
	got := myLists(t, h, u)
	for _, l := range got[1:] {
		names = append(names, l.Name)
	}
	if !got[0].IsDefault || !slices.Equal(names, []string{"apple", "Zebra"}) {
		t.Fatalf("%+v", got)
	}
}

func TestNameValidation(t *testing.T) {
	db, h := setup(t)
	u := testutil.NewUser(t, db)
	l := create(t, h, u, "ok")
	for _, name := range []string{"", "   ", strings.Repeat("x", 61), strings.Repeat("ü", 61), "two\nlines", "tab\there"} {
		for _, c := range [][2]string{{"POST", "/lists"}, {"PATCH", fmt.Sprintf("/lists/%d", l.ID)}} {
			w := do(t, h, c[0], c[1], u, nameBody(name))
			if w.Code != 400 || !strings.Contains(w.Body.String(), "invalid_name") {
				t.Errorf("%s %q: %d %s", c[0], name, w.Code, w.Body)
			}
		}
	}
	create(t, h, u, strings.Repeat("ü", 60)) // counts characters, not bytes
	for _, c := range [][2]string{{"POST", "/lists"}, {"PATCH", fmt.Sprintf("/lists/%d", l.ID)}} {
		if w := do(t, h, c[0], c[1], u, "{"); w.Code != 400 {
			t.Errorf("bad json: %d", w.Code)
		}
	}
}

func TestNamesAreUniquePerUser(t *testing.T) {
	db, h := setup(t)
	u, other := testutil.NewUser(t, db), testutil.NewUser(t, db)
	l := create(t, h, u, "Rainy days")
	second := create(t, h, u, "Summer")
	create(t, h, other, "Rainy days") // lists of others do not matter

	w := do(t, h, "POST", "/lists", u, nameBody("rainy DAYS"))
	if w.Code != 409 || !strings.Contains(w.Body.String(), "name_taken") {
		t.Fatalf("create: %d %s", w.Code, w.Body)
	}
	w = do(t, h, "PATCH", fmt.Sprintf("/lists/%d", second.ID), u, nameBody("Rainy Days"))
	if w.Code != 409 || !strings.Contains(w.Body.String(), "name_taken") {
		t.Fatalf("rename: %d %s", w.Code, w.Body)
	}
	// a list may keep its name, or change the case of it
	w = do(t, h, "PATCH", fmt.Sprintf("/lists/%d", l.ID), u, nameBody("RAINY days"))
	if w.Code != 200 || decode[list](t, w).Name != "RAINY days" {
		t.Fatalf("own name: %d %s", w.Code, w.Body)
	}
	// emoji are told apart
	create(t, h, u, "🌧")
	create(t, h, u, "🌞")
}

func TestDefaultListNamesAreReserved(t *testing.T) {
	db, h := setup(t)
	u := testutil.NewUser(t, db)
	l := create(t, h, u, "mine")
	for _, name := range []string{"Favourites", "favoriten", "FAVORITES"} {
		for _, c := range [][2]string{{"POST", "/lists"}, {"PATCH", fmt.Sprintf("/lists/%d", l.ID)}} {
			w := do(t, h, c[0], c[1], u, nameBody(name))
			if w.Code != 409 || !strings.Contains(w.Body.String(), "name_taken") {
				t.Errorf("%s %q: %d %s", c[0], name, w.Code, w.Body)
			}
		}
	}
}

func TestListLimit(t *testing.T) {
	db, h := setup(t)
	u := testutil.NewUser(t, db)
	var last list
	for i := range lists.MaxLists {
		last = create(t, h, u, fmt.Sprintf("list %d", i))
	}
	// Favourites do not use up the limit
	if got := len(myLists(t, h, u)); got != lists.MaxLists+1 {
		t.Fatalf("lists = %d", got)
	}
	w := do(t, h, "POST", "/lists", u, nameBody("one too many"))
	if w.Code != 409 || !strings.Contains(w.Body.String(), "list_limit") {
		t.Fatalf("got %d %s", w.Code, w.Body)
	}
	do(t, h, "DELETE", fmt.Sprintf("/lists/%d", last.ID), u, "")
	create(t, h, u, "room again")
}

func TestListLimitHoldsUnderConcurrentCreates(t *testing.T) {
	db, h := setup(t)
	u := testutil.NewUser(t, db)
	for i := range lists.MaxLists - 2 {
		create(t, h, u, fmt.Sprintf("list %d", i))
	}
	var wg sync.WaitGroup
	for i := range 8 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			do(t, h, "POST", "/lists", u, nameBody(fmt.Sprintf("race %d", i)))
		}()
	}
	wg.Wait()
	if n := count(t, db, `SELECT COUNT(*) FROM spot_lists WHERE user_id = ? AND is_default = 0`, u); n != lists.MaxLists {
		t.Fatalf("lists = %d", n)
	}
}

func TestFavouritesCannotBeRenamedOrDeleted(t *testing.T) {
	db, h := setup(t)
	u := testutil.NewUser(t, db)
	fav := myLists(t, h, u)[0]
	for _, w := range []*httptest.ResponseRecorder{
		do(t, h, "PATCH", fmt.Sprintf("/lists/%d", fav.ID), u, nameBody("Mine now")),
		do(t, h, "DELETE", fmt.Sprintf("/lists/%d", fav.ID), u, ""),
	} {
		if w.Code != 403 || !strings.Contains(w.Body.String(), "default_list") {
			t.Fatalf("got %d %s", w.Code, w.Body)
		}
	}
	if got := myLists(t, h, u); len(got) != 1 || got[0].Name != fav.Name {
		t.Fatalf("%+v", got)
	}
}

// Another user's list must look exactly like one that does not exist, and
// nothing may change.
func TestForeignListsAre404(t *testing.T) {
	db, h := setup(t)
	owner, stranger := testutil.NewUser(t, db), testutil.NewUser(t, db)
	s, s2 := newSpot(t, db, owner), newSpot(t, db, owner)
	mine := create(t, h, owner, "secret place")
	add(t, h, owner, mine.ID, s)
	fav := myLists(t, h, owner)[0]
	const missing = 999999

	for _, c := range []struct{ method, path, body string }{
		{"GET", "/lists/%d", ""},
		{"PATCH", "/lists/%d", nameBody("stolen")},
		{"DELETE", "/lists/%d", ""},
		{"GET", "/lists/%d/spots", ""},
		{"PUT", fmt.Sprintf("/lists/%%d/spots/%d", s2), ""},
		{"DELETE", fmt.Sprintf("/lists/%%d/spots/%d", s), ""},
	} {
		for _, id := range []uint64{mine.ID, fav.ID} {
			w := do(t, h, c.method, fmt.Sprintf(c.path, id), stranger, c.body)
			gone := do(t, h, c.method, fmt.Sprintf(c.path, missing), stranger, c.body)
			if w.Code != 404 || w.Body.String() != gone.Body.String() {
				t.Errorf("%s %s: %d %s (missing: %d %s)", c.method, c.path, w.Code, w.Body, gone.Code, gone.Body)
			}
			if strings.Contains(w.Body.String(), "secret") {
				t.Errorf("leaked: %s", w.Body)
			}
		}
	}
	if got := listByID(t, h, owner, mine.ID); got.Name != "secret place" || got.SpotCount != 1 {
		t.Fatalf("list changed: %+v", got)
	}
}

func TestListsAndMembershipShowOnlyMine(t *testing.T) {
	db, h := setup(t)
	a, b := testutil.NewUser(t, db), testutil.NewUser(t, db)
	s := newSpot(t, db, a)
	la := create(t, h, a, "of a")
	lb := create(t, h, b, "of b")
	add(t, h, a, la.ID, s)
	add(t, h, b, lb.ID, s)

	if got := membership(t, h, a, s); !slices.Equal(got, []uint64{la.ID}) {
		t.Fatalf("a: %v", got)
	}
	if got := membership(t, h, b, s); !slices.Equal(got, []uint64{lb.ID}) {
		t.Fatalf("b: %v", got)
	}
	for _, l := range myLists(t, h, b) {
		if l.ID == la.ID {
			t.Fatalf("saw a's list: %+v", l)
		}
	}
	// the list_ids a write answers with are scoped as well
	w := do(t, h, "DELETE", fmt.Sprintf("/lists/%d/spots/%d", lb.ID, s), b, "")
	if w.Code != 200 || !strings.Contains(w.Body.String(), `"list_ids":[]`) {
		t.Fatalf("got %d %s", w.Code, w.Body)
	}
}

func TestSpotInSeveralListsAndRemove(t *testing.T) {
	db, h := setup(t)
	u := testutil.NewUser(t, db)
	s := newSpot(t, db, u)
	l1, l2 := create(t, h, u, "one"), create(t, h, u, "two")
	add(t, h, u, l1.ID, s)
	add(t, h, u, l2.ID, s)
	if got := membership(t, h, u, s); !slices.Equal(got, []uint64{l1.ID, l2.ID}) {
		t.Fatalf("membership = %v", got)
	}
	for range 2 { // removing is idempotent
		w := do(t, h, "DELETE", fmt.Sprintf("/lists/%d/spots/%d", l1.ID, s), u, "")
		if w.Code != 200 || !strings.Contains(w.Body.String(), fmt.Sprintf("[%d]", l2.ID)) {
			t.Fatalf("got %d %s", w.Code, w.Body)
		}
	}
	if got := listByID(t, h, u, l1.ID); got.SpotCount != 0 {
		t.Fatalf("%+v", got)
	}
	if w := do(t, h, "PUT", fmt.Sprintf("/lists/%d/spots/9999999", l1.ID), u, ""); w.Code != 404 {
		t.Fatalf("missing spot: %d", w.Code)
	}
	if w := do(t, h, "GET", "/spots/9999999/lists", u, ""); w.Code != 404 {
		t.Fatalf("membership of missing spot: %d", w.Code)
	}
}

func TestSpotsArePagedNewestSaveFirst(t *testing.T) {
	db, h := setup(t)
	u := testutil.NewUser(t, db)
	l := create(t, h, u, "many")
	var want []uint64
	for range 5 {
		s := newSpot(t, db, u)
		add(t, h, u, l.ID, s)
		want = append([]uint64{s}, want...)
	}
	var got []uint64
	cursor := ""
	for page := 0; ; page++ {
		w := do(t, h, "GET", fmt.Sprintf("/lists/%d/spots?limit=2&cursor=%s", l.ID, cursor), u, "")
		if w.Code != 200 {
			t.Fatalf("%d %s", w.Code, w.Body)
		}
		p := decode[struct {
			Items      []spot  `json:"items"`
			NextCursor *string `json:"next_cursor"`
		}](t, w)
		for _, s := range p.Items {
			if s.Tags == nil {
				t.Fatal("tags missing")
			}
			got = append(got, s.ID)
		}
		if p.NextCursor == nil {
			break
		}
		if page > 3 {
			t.Fatal("paging does not end")
		}
		cursor = *p.NextCursor
	}
	if !slices.Equal(got, want) {
		t.Fatalf("got %v want %v", got, want)
	}
	for _, q := range []string{"limit=0", "limit=x", "cursor=%25"} {
		if w := do(t, h, "GET", fmt.Sprintf("/lists/%d/spots?%s", l.ID, q), u, ""); w.Code != 400 {
			t.Errorf("%s: %d", q, w.Code)
		}
	}
}

func TestEmptyListHasAnEmptyItemsArray(t *testing.T) {
	db, h := setup(t)
	u := testutil.NewUser(t, db)
	l := create(t, h, u, "empty")
	w := do(t, h, "GET", fmt.Sprintf("/lists/%d/spots", l.ID), u, "")
	if w.Code != 200 || !strings.Contains(w.Body.String(), `"items":[]`) {
		t.Fatalf("%d %s", w.Code, w.Body)
	}
}

func TestHiddenSpotsDisappearFromLists(t *testing.T) {
	db, h := setup(t)
	u := testutil.NewUser(t, db)
	visible, hidden := newSpot(t, db, u), newSpot(t, db, u)
	addPhoto(t, db, hidden, u, "hidden", "approved")
	l := create(t, h, u, "mixed")
	add(t, h, u, l.ID, visible)
	add(t, h, u, l.ID, hidden) // newest, so it would be the cover
	if got := listByID(t, h, u, l.ID); got.SpotCount != 2 || !strings.Contains(got.CoverURL, "hidden") {
		t.Fatalf("before: %+v", got)
	}
	if _, err := db.Exec(`UPDATE spots SET status = 'hidden' WHERE id = ?`, hidden); err != nil {
		t.Fatal(err)
	}

	got := spotsOf(t, h, u, l.ID)
	if len(got) != 1 || got[0].ID != visible {
		t.Fatalf("spots: %+v", got)
	}
	if got := listByID(t, h, u, l.ID); got.SpotCount != 1 || got.CoverURL != "" {
		t.Fatalf("after: %+v", got)
	}
	w := do(t, h, "GET", fmt.Sprintf("/spots/%d/lists", hidden), u, "")
	if w.Code != 404 {
		t.Fatalf("membership: %d %s", w.Code, w.Body)
	}
	other := create(t, h, u, "other")
	for _, path := range []string{fmt.Sprintf("/lists/%d/spots/%d", other.ID, hidden), fmt.Sprintf("/lists/default/spots/%d", hidden)} {
		if w := do(t, h, "PUT", path, u, ""); w.Code != 404 {
			t.Fatalf("add %s: %d %s", path, w.Code, w.Body)
		}
	}

	// a spot that comes back is still saved, and it can also be taken out
	if _, err := db.Exec(`UPDATE spots SET status = 'active' WHERE id = ?`, hidden); err != nil {
		t.Fatal(err)
	}
	if got := spotsOf(t, h, u, l.ID); len(got) != 2 {
		t.Fatalf("unhidden: %+v", got)
	}
	if _, err := db.Exec(`UPDATE spots SET status = 'hidden' WHERE id = ?`, hidden); err != nil {
		t.Fatal(err)
	}
	if w := do(t, h, "DELETE", fmt.Sprintf("/lists/%d/spots/%d", l.ID, hidden), u, ""); w.Code != 200 {
		t.Fatalf("remove hidden: %d %s", w.Code, w.Body)
	}
	if n := count(t, db, `SELECT COUNT(*) FROM spot_list_items WHERE spot_id = ?`, hidden); n != 0 {
		t.Fatalf("rows = %d", n)
	}
}

func TestCoverSkipsPhotosThatAreNotPublic(t *testing.T) {
	db, h := setup(t)
	u := testutil.NewUser(t, db)
	withPhoto, rejected, none := newSpot(t, db, u), newSpot(t, db, u), newSpot(t, db, u)
	addPhoto(t, db, withPhoto, u, "good", "approved")
	addPhoto(t, db, rejected, u, "bad", "rejected")
	l := create(t, h, u, "covers")
	add(t, h, u, l.ID, withPhoto)
	add(t, h, u, l.ID, rejected)
	add(t, h, u, l.ID, none)
	got := listByID(t, h, u, l.ID)
	if got.CoverURL != "http://test/api/v1/media/good_thumb.jpg" {
		t.Fatalf("cover = %q", got.CoverURL)
	}
	if got.SpotCount != 3 {
		t.Fatalf("%+v", got)
	}
}

func TestDeletingAListKeepsItsSpots(t *testing.T) {
	db, h := setup(t)
	u := testutil.NewUser(t, db)
	s := newSpot(t, db, u)
	l := create(t, h, u, "gone soon")
	add(t, h, u, l.ID, s)
	if w := do(t, h, "DELETE", fmt.Sprintf("/lists/%d", l.ID), u, ""); w.Code != 204 {
		t.Fatalf("%d", w.Code)
	}
	if n := count(t, db, `SELECT COUNT(*) FROM spot_list_items WHERE list_id = ?`, l.ID); n != 0 {
		t.Fatalf("items = %d", n)
	}
	if n := count(t, db, `SELECT COUNT(*) FROM spots WHERE id = ?`, s); n != 1 {
		t.Fatalf("spots = %d", n)
	}
}

func TestDeletingASpotOrUserCleansUp(t *testing.T) {
	db, h := setup(t)
	author, saver := testutil.NewUser(t, db), testutil.NewUser(t, db)
	s, kept := newSpot(t, db, author), newSpot(t, db, saver)
	l := create(t, h, saver, "stuff")
	add(t, h, saver, l.ID, s)
	add(t, h, saver, l.ID, kept)

	if _, err := db.Exec(`DELETE FROM spots WHERE id = ?`, s); err != nil {
		t.Fatal(err)
	}
	if n := count(t, db, `SELECT COUNT(*) FROM spot_list_items WHERE spot_id = ?`, s); n != 0 {
		t.Fatalf("items of the spot = %d", n)
	}
	if got := listByID(t, h, saver, l.ID); got.SpotCount != 1 {
		t.Fatalf("%+v", got)
	}

	if _, err := db.Exec(`DELETE FROM users WHERE id = ?`, saver); err != nil {
		t.Fatal(err)
	}
	if n := count(t, db, `SELECT COUNT(*) FROM spot_lists WHERE user_id = ?`, saver); n != 0 {
		t.Fatalf("lists = %d", n)
	}
	if n := count(t, db, `SELECT COUNT(*) FROM spot_list_items WHERE list_id = ?`, l.ID); n != 0 {
		t.Fatalf("items = %d", n)
	}
}

func TestDeletingTheAuthorRemovesTheirSpotsFromOtherLists(t *testing.T) {
	db, h := setup(t)
	author, saver := testutil.NewUser(t, db), testutil.NewUser(t, db)
	s := newSpot(t, db, author)
	l := create(t, h, saver, "stuff")
	add(t, h, saver, l.ID, s)
	if _, err := db.Exec(`DELETE FROM users WHERE id = ?`, author); err != nil {
		t.Fatal(err)
	}
	if got := spotsOf(t, h, saver, l.ID); len(got) != 0 {
		t.Fatalf("%+v", got)
	}
}

// A token can outlive its account; such a request must not fail with a 500
// or leave rows behind.
func TestDeletedUserWithLiveToken(t *testing.T) {
	db, h := setup(t)
	u := testutil.NewUser(t, db)
	if _, err := db.Exec(`DELETE FROM users WHERE id = ?`, u); err != nil {
		t.Fatal(err)
	}
	for _, c := range [][3]string{{"GET", "/lists", ""}, {"POST", "/lists", nameBody("x")}} {
		if w := do(t, h, c[0], c[1], u, c[2]); w.Code != 401 {
			t.Errorf("%s %s: %d %s", c[0], c[1], w.Code, w.Body)
		}
	}
}
