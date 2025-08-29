package main

import (
	"math"
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

func TestCalculateLaterValues(t *testing.T) {
	type expectedValueEventually struct {
		afterMinutes int
		value        int
	}
	type testCase struct {
		schedule       string
		cycle          int
		expectedValues []expectedValueEventually
	}
	testCases := []testCase{
		{
			schedule: "0:2,2:4,4:8,6:16",
			cycle:    10,
			expectedValues: []expectedValueEventually{
				{afterMinutes: 3, value: 4},
				{afterMinutes: 5, value: 8},
				{afterMinutes: 9, value: 16},
				{afterMinutes: 11, value: 2},
				{afterMinutes: (42 * 10) + 3, value: 4},
			},
		},
		{
			schedule: "0:1,1:2,2:3,3:4,4:0",
			cycle:    5,
			expectedValues: []expectedValueEventually{
				{afterMinutes: 1, value: 1},
				{afterMinutes: 3, value: 3},
				{afterMinutes: 5, value: 0},
				{afterMinutes: 6, value: 1},
				{afterMinutes: 2 * 3 * 4 * 5 * 6, value: (2 * 3 * 4 * 5 * 6) % 5},
			},
		},
		// longer cycle
		{
			schedule: "0:0,10:10,20:20",
			cycle:    30,
			expectedValues: []expectedValueEventually{
				{afterMinutes: 21, value: 20},
				{afterMinutes: 71, value: 10},
				{afterMinutes: (42 * 30) + 21, value: 20},
				{afterMinutes: (142 * 30) + 31, value: 0},
			},
		},
		{
			schedule: "0:0,10:10,20:20,30:30,40:40,50:50",
			cycle:    60,
			expectedValues: []expectedValueEventually{
				{afterMinutes: 51, value: 50},
				{afterMinutes: 71, value: 10},
				{afterMinutes: (42 * 60) + 21, value: 20},
				{afterMinutes: (142 * 60) + 41, value: 40},
			},
		},
		{
			schedule: "0:0,60:1,120:2,180:3,240:4,300:5,360:6,420:7",
			cycle:    60 * 8,
			expectedValues: []expectedValueEventually{
				{afterMinutes: 121, value: 2},
				{afterMinutes: 421, value: 7},
				{afterMinutes: (42 * 8 * 60) + 21, value: 0},
				{afterMinutes: (42 * 8 * 60) + 301, value: 5},
			},
		},
	}
	same := func(v1 float64, v2 int) bool {
		return math.Abs(float64(v2)-v1) < 1e-6
	}
	for _, tc := range testCases {
		mm := NewMinuteMetrics()
		if err := mm.parseSchedule(tc.schedule); err != nil {
			t.Errorf("Unexpected error: %v", err)
		}
		mm.cycleMinutes = tc.cycle
		now := time.Now()
		mm.startTime = &now
		for _, ev := range tc.expectedValues {
			// Simulate N minutes later
			nMinutesLater := now.Add(time.Duration(ev.afterMinutes) * time.Minute)
			mm.startTime = &nMinutesLater

			if value := mm.calculateValue(); !same(value, ev.value) {
				t.Errorf("Expected: %d, got: %.0f schedule: %s cycle: %d after: %d min", ev.value, value, tc.schedule, tc.cycle, ev.afterMinutes)
			}
		}
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
