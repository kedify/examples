package main

import (
	"encoding/json"
	"fmt"
	"math"
	"net/http"
	"os"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

var (
	defaultScheduleStr = "0:8,1:0,2:4,3:2,4:0,5:3,7:5,9:0"
)

// MinuteMetrics is the main application struct
type MinuteMetrics struct {
	startTime *time.Time
	baseValue float64
	lazyStart bool
	schedule  []ScheduleItem
	mutex     sync.Mutex
}

// NewMinuteMetrics initializes new MinuteMetrics struct with environment variables as defaults
func NewMinuteMetrics() *MinuteMetrics {
	baseVal, _ := strconv.ParseFloat(os.Getenv("BASE"), 64)
	lazyStrt := os.Getenv("LAZY_START") == "true"
	schStr := os.Getenv("SCHEDULE")
	if schStr == "" {
		schStr = defaultScheduleStr
	}

	app := &MinuteMetrics{
		baseValue: baseVal,
		lazyStart: lazyStrt,
	}

	if err := app.parseSchedule(schStr); err != nil {
		fmt.Printf("Failed to parse schedule from environment variable: %v\n", err)
		os.Exit(1)
	}

	return app
}

// Response is the structure for our JSON response, containing name and value fields.
type Response struct {
	Name  string  `json:"name"`  // The name field, static for this example.
	Value float64 `json:"value"` // The dynamically calculated value.
}

type ScheduleItem struct {
	Minute int
	Value  float64
}

// parseSchedule parses the schedule string and populates the schedule field.
func (mm *MinuteMetrics) parseSchedule(scheduleStr string) error {
	var tempSchedule []ScheduleItem
	pairs := strings.Split(scheduleStr, ",")
	for _, pair := range pairs {
		parts := strings.Split(pair, ":")
		if len(parts) != 2 {
			return fmt.Errorf("invalid schedule entry: %s", pair)
		}
		minute, err1 := strconv.Atoi(parts[0])
		value, err2 := strconv.ParseFloat(parts[1], 64)
		if err1 != nil || err2 != nil {
			return fmt.Errorf("error parsing schedule entry: %s", pair)
		}
		tempSchedule = append(tempSchedule, ScheduleItem{Minute: minute, Value: value})
	}

	sort.Slice(tempSchedule, func(i, j int) bool {
		return tempSchedule[i].Minute < tempSchedule[j].Minute
	})

	mm.schedule = tempSchedule
	return nil
}

// calculateValue calculates the current value based on the schedule and base value.
func (mm *MinuteMetrics) calculateValue() float64 {
	mm.mutex.Lock()
	defer mm.mutex.Unlock()

	if mm.startTime == nil {
		now := time.Now()
		mm.startTime = &now
	}

	elapsed := time.Since(*mm.startTime).Minutes()
	currentMinute := int(math.Abs(elapsed)) % 10 // Assuming a 10-minute cycle

	// Start with the base value by default
	var currentValue float64

	// Find the last schedule item that applies to the current minute
	for _, item := range mm.schedule {
		if item.Minute <= currentMinute {
			currentValue = mm.baseValue + item.Value
		} else {
			// Since the schedule is sorted, we can break once we've passed the current minute
			break
		}
	}

	return currentValue
}

// Handler handles requests to the "/api/v1/get" endpoint
// It calculates the current value and returns it in a JSON response.
func (mm *MinuteMetrics) Handler(w http.ResponseWriter, r *http.Request) {
	value := mm.calculateValue()
	response := Response{Name: "minute-metrics", Value: value}

	fmt.Println("Response:", response)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}
