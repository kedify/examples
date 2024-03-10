package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strconv"
	"sync"
)

// StaticMetrics handles serving and updating a static metric value.
type StaticMetrics struct {
	Value float64
	mutex sync.Mutex
}

// NewStaticMetrics initializes a StaticMetrics struct with a default value from an environment variable or flag.
func NewStaticMetrics(defaultValue float64) *StaticMetrics {
	// Check if an environment variable is set for the static value
	envVal, err := strconv.ParseFloat(os.Getenv("STATIC_VALUE"), 64)
	if err == nil {
		defaultValue = envVal
	}

	return &StaticMetrics{Value: defaultValue}
}

// ServeHTTP to implement http.Handler for StaticMetrics.
func (sm *StaticMetrics) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case "GET":
		sm.serveStaticValue(w, r)
	case "PUT":
		sm.updateStaticValue(w, r)
	default:
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
	}
}

// serveStaticValue handles GET requests and serves the static metric value.
func (sm *StaticMetrics) serveStaticValue(w http.ResponseWriter, r *http.Request) {
	sm.mutex.Lock()
	defer sm.mutex.Unlock()

	response := Response{Name: "static-metrics", Value: sm.Value}

	fmt.Println("Response:", response)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

// updateStaticValue handles PUT requests to update the static metric value.
func (sm *StaticMetrics) updateStaticValue(w http.ResponseWriter, r *http.Request) {
	sm.mutex.Lock()
	defer sm.mutex.Unlock()

	var newValue Response
	if err := json.NewDecoder(r.Body).Decode(&newValue); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	sm.Value = newValue.Value
	fmt.Fprintf(w, "Static value updated to: %f", sm.Value)
	fmt.Printf("Static value updated to: %f\n", sm.Value)
}
