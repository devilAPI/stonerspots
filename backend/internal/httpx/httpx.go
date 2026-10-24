// Package httpx has small JSON response helpers shared by all handlers.
package httpx

import (
	"encoding/json"
	"net/http"
)

// JSON writes v as a JSON response with the given status.
func JSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

type errBody struct {
	Error errDetail `json:"error"`
}

type errDetail struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

// Error writes {"error": {"code": ..., "message": ...}} with the given status.
func Error(w http.ResponseWriter, status int, code, msg string) {
	JSON(w, status, errBody{Error: errDetail{Code: code, Message: msg}})
}
