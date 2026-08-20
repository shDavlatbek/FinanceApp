// Package api exposes the container healthcheck endpoint and nothing else.
//
// v2 removed the bespoke REST sync API: the app and the bot are peers that
// exchange snapshot files through Google Drive, so the server never accepts
// inbound data. GET /api/health is unauthenticated on purpose — it reveals
// nothing and is what Docker's healthcheck calls from inside the container.
package api

import (
	"encoding/json"
	"log"
	"net/http"
)

// New builds the HTTP handler: GET /api/health only.
func New(version string) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/health", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok", "version": version})
	})
	return mux
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(v); err != nil {
		log.Printf("api: write response: %v", err)
	}
}
