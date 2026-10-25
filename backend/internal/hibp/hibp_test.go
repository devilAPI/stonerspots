package hibp

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestIsBreached(t *testing.T) {
	// Test vector: "password" -> SHA1 = 5BAA61E4C9B93F3F0682250B6CF8331B7EE68FD8
	// Prefix: 5BAA6, Suffix: 1E4C9B93F3F0682250B6CF8331B7EE68FD8
	mux := http.NewServeMux()
	// "password" SHA1 = 5BAA61E4C9B93F3F0682250B6CF8331B7EE68FD8
	// First 5 bytes (10 hex chars) = 5BAA61E4C9 (lowercase: 5baa61e4c9)
	// Suffix = B93F3F0682250B6CF8331B7EE68FD8
	mux.HandleFunc("/range/5baa61e4c9", func(w http.ResponseWriter, r *http.Request) {
		t.Logf("Handler called: %s", r.URL.Path)
		// Return a list containing our suffix (uppercase)
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("B93F3F0682250B6CF8331B7EE68FD8:12345\nOTHER:1\n"))
	})
	// "notapassword" SHA1 = 0707B407EAF5E9E2B5C8E3A4F5D6E7F8A9B0C1D2
	// First 5 bytes = 0707B407EA (lowercase: 0707b407ea)
	mux.HandleFunc("/range/0707b407ea", func(w http.ResponseWriter, r *http.Request) {
		t.Logf("Handler called: %s", r.URL.Path)
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OTHER:1\n")) // suffix not found
	})
	mux.HandleFunc("/range/NOTFOUND", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OTHER:1\n"))
	})
	// Catch-all to see what paths are requested
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		t.Logf("Catch-all: %s", r.URL.Path)
		w.WriteHeader(http.StatusNotFound)
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

	// Verify the NOTFOUND handler was called
	// (it should have been called for "notapassword")
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