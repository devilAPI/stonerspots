package hibp

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestIsBreached(t *testing.T) {
	// "password": SHA-1 5BAA61E4C9B93F3F0682250B6CF8331B7EE68FD8, sent as
	// the prefix 5BAA6; the answer lists suffixes (the other 35 characters).
	mux := http.NewServeMux()
	mux.HandleFunc("/range/5BAA6", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("1E4C9B93F3F0682250B6CF8331B7EE68FD8:12345\r\n0018A45C4D1DEF81644B54AB7F969B88D65:1\r\n"))
	})
	// "notapassword": SHA-1 0707B407EA49B96FAAA1AD126F56697DC974DCCA
	mux.HandleFunc("/range/0707B", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("0018A45C4D1DEF81644B54AB7F969B88D65:1\r\n"))
	})
	// The real API answers 400 to any prefix that is not 5 hex characters.
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		t.Errorf("unexpected request %s (only a 5-character prefix may be sent)", r.URL.Path)
		w.WriteHeader(http.StatusBadRequest)
	})
	// The client uses baseURL + prefix, so we need the full path

	server := httptest.NewServer(mux)
	defer server.Close()

	client := &Client{
		httpClient: &http.Client{Timeout: timeout},
		baseURL:    server.URL + "/range/",
	}

	t.Logf("baseURL: %s", client.baseURL)

	// Test breached password
	ctx := context.Background()
	breached, err := client.IsBreached(ctx, "password")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !breached {
		t.Fatal("expected breached=true for 'password'")
	}

	// Test non-breached password
	client2 := &Client{
		httpClient: &http.Client{Timeout: timeout},
		baseURL:    server.URL + "/range/",
	}
	breached, err = client2.IsBreached(ctx, "notapassword")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if breached {
		t.Fatal("expected breached=false for 'notapassword'")
	}
}

func TestIsBreachedTimeout(t *testing.T) {
	// Server that never responds
	mux := http.NewServeMux()
	mux.HandleFunc("/range/", func(w http.ResponseWriter, r *http.Request) {
		<-r.Context().Done() // wait forever
	})
	server := httptest.NewServer(mux)
	defer server.Close()

	client := &Client{
		httpClient: &http.Client{Timeout: 100 * time.Millisecond},
		baseURL:    server.URL + "/range/",
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	_, err := client.IsBreached(ctx, "password")
	if err == nil {
		t.Fatal("expected timeout error")
	}
}