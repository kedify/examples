package main

import (
	"flag"
	"fmt"
	"net/http"
	"os"
	"strings"
	"time"
)

func main() {
	baseValueFlag := flag.Float64("base", 0, "Initial base value for calculations. Overrides BASE if provided.")
	lazyStartFlag := flag.Bool("lazy-start", true, "Enable lazy start. Overrides LAZY_START if provided.")
	scheduleFlag := flag.String("schedule", "", "Schedule configuration as 'minute:value' pairs. Overrides SCHEDULE if provided.")
	cycleMinutesFlag := flag.Int("cycle-minutes", 0, "Repeat provided schedule every N minutes provided by this variable.")
	staticValueFlag := flag.Float64("static-value", 0, "Static value for static metrics. Overrides STATIC_VALUE if provided.")
	helpFlag := flag.Bool("help", false, "Displays help information.")

	flag.Parse()

	if *helpFlag {
		printHelp()
		return
	}

	mm := NewMinuteMetrics()
	sm := NewStaticMetrics(*staticValueFlag)

	// Override app fields with flag values if provided
	mm.baseValue = *baseValueFlag
	mm.lazyStart = *lazyStartFlag
	if *scheduleFlag != "" {
		if err := mm.parseSchedule(*scheduleFlag); err != nil {
			fmt.Printf("Failed to parse schedule from command line: %v\n", err)
			os.Exit(1)
		}
	}
	if *cycleMinutesFlag > 0 {
		mm.cycleMinutes = *cycleMinutesFlag
	}

	if !mm.lazyStart {
		now := time.Now()
		mm.startTime = &now
	}

	// Set up routing
	http.Handle("/api/v1/staticmetrics", sm)
	http.HandleFunc("/api/v1/minutemetrics", mm.Handler)
	fmt.Printf("schedule: %s\n", strings.Join(
		func() []string {
			out := make([]string, len(mm.schedule))
			for i, item := range mm.schedule {
				out[i] = fmt.Sprintf("%dm: %.0f", item.Minute, item.Value)
			}
			return out
		}(),
		", ",
	))
	fmt.Printf("cycle: %dm\n", mm.cycleMinutes)
	fmt.Printf("base: %.1f\n", mm.baseValue)
	fmt.Printf("lazy-start: %t\n", mm.lazyStart)
	fmt.Printf("static-value: %.1f\n\n", *staticValueFlag)
	fmt.Println("Server started on :8080")
	if err := http.ListenAndServe(":8080", nil); err != nil {
		fmt.Printf("Failed to start server: %v\n", err)
	}
}

func printHelp() {
	helpContent := `MinuteMetrics Help
------------------
Usage:
  go run main.go [options]

Options:
  -base float          Set the initial base value for calculations. Overrides BASE if provided.
  -lazy-start          Enable lazy start, starting the schedule with the first request. Overrides LAZY_START if provided.
  -schedule string     Schedule configuration as 'minute:value' pairs. Overrides SCHEDULE if provided.
	-cycle-minutes int   Repeat provided schedule every N minutes provided by this variable. Overrides CYCLE_MINUTES if provided.
  -static-value float  Set the initial static value for static metrics. Overrides STATIC_VALUE if provided.
  -help                Displays this help information.

Environment Variables:
  BASE          Sets the initial base value for calculations. Command-line option overrides this if provided.
  LAZY_START    Enable lazy start with "true". Command-line option overrides this if provided.
  SCHEDULE      Defines the value update schedule. Format: 'minute:value,minute:value,...'.
	CYCLE_MINUTES Repeat provided schedule every N minutes provided by this variable.
  STATIC_VALUE  Sets the initial static value for static metrics. Command-line option overrides this if provided.

Endpoints:
  /api/v1/minutemetrics    Returns dynamic metric data in JSON format based on the schedule.
  /api/v1/staticmetrics    GET returns the current static metric data in JSON format.
                           PUT updates the static metric value.

Examples:
  go run main.go -base 5
  go run main.go -lazy-start -schedule "0:10,5:20"
  go run main.go -static-value 100
	go run main.go -cycle-minutes 20 -schedule "0:0,1:1,2:2,3:3,4:4,5:5,6:6,7:7,8:8,9:9,10:10,11:9,12:8,13:7,14:6,15:5,16:4,17:3,18:2,19:1"

To update the static value via curl:
  curl -X PUT -H "Content-Type: application/json" -d '{"value":5}' http://localhost:8080/api/v1/staticmetrics

For more information or contributions, visit the repository or contact the developers.`
	fmt.Println(helpContent)
}
