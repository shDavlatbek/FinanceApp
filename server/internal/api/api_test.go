package api

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestHealthNoAuth(t *testing.T) {
	srv := httptest.NewServer(New("test"))
	t.Cleanup(srv.Close)

	resp, err := http.Get(srv.URL + "/api/health")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("health status = %d", resp.StatusCode)
	}
	var body map[string]string
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		t.Fatal(err)
	}
	if body["status"] != "ok" || body["version"] != "test" {
		t.Fatalf("health body = %v", body)
	}
}

// The sync endpoint is gone for good: nothing may be POSTable to this server.
func TestSyncEndpointGone(t *testing.T) {
	srv := httptest.NewServer(New("test"))
	t.Cleanup(srv.Close)

	resp, err := http.Post(srv.URL+"/api/sync", "application/json", http.NoBody)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusNotFound {
		t.Fatalf("POST /api/sync status = %d, want 404", resp.StatusCode)
	}
}
