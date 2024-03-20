package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestParseSchedule(t *testing.T) {
	// Test case with valid input
	mm := NewMinuteMetrics()
	err := mm.parseSchedule("1:2,3:4,5:6")
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}
	if len(mm.schedule) != 3 {
		t.Errorf("Expected 3 schedule items, got %d", len(mm.schedule))
	}
	if mm.schedule[0].Minute != 1 || mm.schedule[0].Value != 2 {
		t.Errorf("Unexpected first schedule item: %v", mm.schedule[0])
	}
	if mm.schedule[1].Minute != 3 || mm.schedule[1].Value != 4 {
		t.Errorf("Unexpected second schedule item: %v", mm.schedule[1])
	}
	if mm.schedule[2].Minute != 5 || mm.schedule[2].Value != 6 {
		t.Errorf("Unexpected third schedule item: %v", mm.schedule[2])
	}

	// Test case with invalid input (non-numeric minute)
	mm = NewMinuteMetrics()
	err = mm.parseSchedule("a:2,3:4,5:6")
	if err == nil {
		t.Errorf("Expected error, got nil")
	}

	// Test case with invalid input (non-numeric value)
	mm = NewMinuteMetrics()
	err = mm.parseSchedule("1:a,3:4,5:6")
	if err == nil {
		t.Errorf("Expected error, got nil")
	}

	// Test case with invalid input (missing value)
	mm = NewMinuteMetrics()
	err = mm.parseSchedule("1:,3:4,5:6")
	if err == nil {
		t.Errorf("Expected error, got nil")
	}

	// Test case with edge case input (minute 0)
	mm = NewMinuteMetrics()
	err = mm.parseSchedule("0:2,3:4,5:6")
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}
	if mm.schedule[0].Minute != 0 || mm.schedule[0].Value != 2 {
		t.Errorf("Unexpected first schedule item: %v", mm.schedule[0])
	}

	// Test case with edge case input (minute 59)
	mm = NewMinuteMetrics()
	err = mm.parseSchedule("59:2,3:4,5:6")
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}
	if mm.schedule[2].Minute != 59 || mm.schedule[2].Value != 2 {
		t.Errorf("Unexpected last schedule item: %v", mm.schedule[2])
	}
}

func TestCalculateValue(t *testing.T) {
	mm := NewMinuteMetrics()
	mm.schedule = []ScheduleItem{
		{Minute: 0, Value: 2.0},
		{Minute: 5, Value: 3.0},
	}
	now := time.Now()
	mm.startTime = &now

	value := mm.calculateValue()
	if value != 2.0 {
		t.Errorf("Expected value 2.0, got %f", value)
	}

	// Simulate 7 minutes later
	sixMinutesLater := now.Add(7 * time.Minute)
	mm.startTime = &sixMinutesLater

	value = mm.calculateValue()
	if value != 3.0 {
		t.Errorf("Expected value 3.0, got %f", value)
	}
}

func TestGetHandler(t *testing.T) {
	mm := NewMinuteMetrics()
	mm.schedule = []ScheduleItem{
		{Minute: 0, Value: 2.0},
		{Minute: 5, Value: 3.0},
	}
	req, err := http.NewRequest("GET", "/api/v1/minutemetrics", nil)
	if err != nil {
		t.Fatal(err)
	}
	rr := httptest.NewRecorder()
	handler := http.HandlerFunc(mm.Handler)

	handler.ServeHTTP(rr, req)

	if status := rr.Code; status != http.StatusOK {
		t.Errorf("handler returned wrong status code: got %v want %v",
			status, http.StatusOK)
	}

	expected := `{"name":"minute-metrics","value":2}`

	if !strings.HasPrefix(rr.Body.String(), expected) {
		t.Errorf("handler returned unexpected body: got x%vx want x%vx",
			rr.Body.String(), expected)
	}
}
