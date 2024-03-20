package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestUpdateStaticValue(t *testing.T) {
	sm := NewStaticMetrics(0)

	// Test case with valid input
	newValue := Response{Value: 5.0}
	jsonValue, _ := json.Marshal(newValue)
	req, _ := http.NewRequest("PUT", "/api/v1/update", bytes.NewBuffer(jsonValue))
	rr := httptest.NewRecorder()
	handler := http.HandlerFunc(sm.updateStaticValue)

	handler.ServeHTTP(rr, req)

	if status := rr.Code; status != http.StatusOK {
		t.Errorf("handler returned wrong status code: got %v want %v",
			status, http.StatusOK)
	}

	if sm.Value != 5.0 {
		t.Errorf("Expected value 5.0, got %f", sm.Value)
	}

	// Test case with invalid input
	req, _ = http.NewRequest("PUT", "/api/v1/update", bytes.NewBuffer([]byte("invalid")))
	rr = httptest.NewRecorder()

	handler.ServeHTTP(rr, req)

	if status := rr.Code; status != http.StatusBadRequest {
		t.Errorf("handler returned wrong status code: got %v want %v",
			status, http.StatusBadRequest)
	}
}
