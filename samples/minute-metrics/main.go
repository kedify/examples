package main

import (
	"flag"
	"fmt"
	"html"
	"net/http"
	"os"
	"strconv"
	"strings"
)

const (
	paramBase                = "base"
	paramMultiplier          = "multiplier"
	paramLazyStart           = "lazy-start"
	paramTimeRelativeToStart = "time-relative-to-start"
	paramInterpolateValues   = "interpolate-values"
	paramSchedule            = "schedule"
	paramCycleMinutes        = "cycle-minutes"
	paramStaticValue         = "static-value"
	paramPort                = "port"

	staticMetricPath = "/api/v1/staticmetrics"
	minuteMetricPath = "/api/v1/minutemetrics"
)

func main() {
	baseValueFlag := flag.Float64(paramBase, 0, "Initial base value for calculations. Overrides BASE if provided.")
	multiplierFlag := flag.Float64(paramMultiplier, 1, "Multiply the calculated value before returning by this constant. Overrides MULTIPLIER if provided.")
	lazyStartFlag := flag.Bool(paramLazyStart, true, "Enable lazy start. Overrides LAZY_START if provided.")
	timeRelativeToStart := flag.Bool(paramTimeRelativeToStart, true, "When enabled (default), it will use the time app is running for its calculations. Disabled takes the UTC time of a day - # of minutes since midnight. Overrides TIME_RELATIVE_TO_START if provided")
	interpolateValues := flag.Bool(paramInterpolateValues, false, "When enabled, it will interpolate the values between each schedule items. Overrides INTERPOLATE_VALUES if provided.")
	scheduleFlag := flag.String(paramSchedule, "", "Schedule configuration as 'minute:value' pairs. Overrides SCHEDULE if provided.")
	cycleMinutesFlag := flag.Int(paramCycleMinutes, 10, "Repeat provided schedule every N minutes provided by this variable.")
	staticValueFlag := flag.Float64(paramStaticValue, 0, "Static value for static metrics. Overrides STATIC_VALUE if provided.")
	helpFlag := flag.Bool("help", false, "Displays help information.")
	portFlag := flag.Int(paramPort, 8080, "Listen for HTTP requests on this port.")

	flag.Parse()

	if *helpFlag {
		printHelp()
		return
	}

	mm := NewMinuteMetrics()
	staticValue, _ := mustGetParamValue(paramStaticValue, *staticValueFlag)
	sm := NewStaticMetrics(staticValue)

	// Override app fields with flag values if provided
	mm.baseValue, _ = mustGetParamValue(paramBase, *baseValueFlag)
	mm.multiplier, _ = mustGetParamValue(paramMultiplier, *multiplierFlag)
	mm.lazyStart, _ = mustGetParamValue(paramLazyStart, *lazyStartFlag)
	mm.timeRelativeToStart, _ = mustGetParamValue(paramTimeRelativeToStart, *timeRelativeToStart)
	cycleMinutes, wasSet := mustGetParamValue(paramCycleMinutes, *cycleMinutesFlag)
	mm.cycleMinutes = cycleMinutes
	if !wasSet {
		mm.cycleMinutes = 10
		if !mm.timeRelativeToStart {
			mm.cycleMinutes = 60 * 24
		}
	}
	mm.interpolateValues, _ = mustGetParamValue(paramInterpolateValues, *interpolateValues)
	scheduleString, _ := mustGetParamValue(paramSchedule, *scheduleFlag)
	if scheduleString != "" {
		if err := mm.parseSchedule(scheduleString); err != nil {
			fmt.Printf("Failed to parse schedule from command line: %v\n", err)
			os.Exit(1)
		}
	}
	port, _ := mustGetParamValue(paramPort, *portFlag)

	if !mm.lazyStart {
		mm.StartTicking()
	}

	// Set up routing
	http.HandleFunc("/", func(writer http.ResponseWriter, request *http.Request) {
		fmt.Fprintf(writer, "Endpoints:\n - [GET] %q\n - [GET] %q\n",
			html.EscapeString(staticMetricPath), html.EscapeString(minuteMetricPath))
	})
	http.Handle(staticMetricPath, sm)
	http.HandleFunc(minuteMetricPath, mm.Handler)
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
	fmt.Printf("multiplier: %.1f\n", mm.multiplier)
	fmt.Printf("lazy-start: %t\n", mm.lazyStart)
	fmt.Printf("time-relative-to-start: %t\n", mm.timeRelativeToStart)
	fmt.Printf("interpolate-values: %t\n", mm.interpolateValues)
	fmt.Printf("static-value: %.1f\n\n", staticValue)
	fmt.Printf("Server started on :%d\n", port)
	if err := http.ListenAndServe(fmt.Sprintf(":%d", port), nil); err != nil {
		fmt.Printf("Failed to start server: %v\n", err)
	}
}

func printHelp() {
	helpContent := `MinuteMetrics Help
------------------
Usage:
  go run main.go [options]

Options:
  -base float             Set the initial base value for calculations. Overrides BASE if provided.
  -multiplier float       Multiply the calculated value before returning by this constant, if base is not 0, base is applied after this. Overrides MULTIPLIER if provided.
  -lazy-start             Enable lazy start, starting the schedule with the first request. Overrides LAZY_START if provided.
  -interpolate-values     When enabled, it will interpolate the values between each schedule items. Overrides INTERPOLATE_VALUES if provided.
  -time-relative-to-start When enabled (default), it will use the time app is running for its calculations. Disabled takes the UTC time of a day - # of minutes since midnight. Overrides TIME_RELATIVE_TO_START if provided.
  -schedule string        Schedule configuration as 'minute:value' pairs. Times are measured since the application start. Overrides SCHEDULE if provided.
  -daily-schedule string  Daily schedule configuration as 'minute:value' pairs. Overrides DAILY_SCHEDULE if provided.
  -hourly-schedule string Hourly schedule configuration as 'minute:value' pairs. Overrides HOURLY_SCHEDULE if provided.
  -cycle-minutes int      Repeat provided schedule every N minutes provided by this variable. Overrides CYCLE_MINUTES if provided.
  -static-value float     Set the initial static value for static metrics. Overrides STATIC_VALUE if provided.
  -help                   Displays this help information.

Environment Variables:
  BASE                   Sets the initial base value for calculations. Command-line option overrides this if provided.
  MULTIPLIER             Scales the value by this constant. This is applied before adding the BASE.
  LAZY_START             Enable lazy start with "true". Command-line option overrides this if provided.
  INTERPOLATE_VALUES     If enabled, it will interpolate the values between each schedule items.
  TIME_RELATIVE_TO_START If enabled, it will use the time app is running for its calculations. Otherwise time of the day in minutes (UTC).
  SCHEDULE               Defines the value update schedule. Format: 'minute:value,minute:value,...'.
  CYCLE_MINUTES          Repeat provided schedule every N minutes provided by this variable.
  STATIC_VALUE           Sets the initial static value for static metrics. Command-line option overrides this if provided.

Endpoints:
  /api/v1/minutemetrics    Returns dynamic metric data in JSON format based on the schedule.
  /api/v1/staticmetrics    GET returns the current static metric data in JSON format.
                           PUT updates the static metric value.

Examples:
  go run main.go -base 5
  go run main.go -lazy-start -schedule "0:10,5:20"
  go run main.go -static-value 100
  go run main.go -cycle-minutes 20 -schedule "0:0,1:1,2:2,3:3,4:4,5:5,6:6,7:7,8:8,9:9,10:10,11:9,12:8,13:7,14:6,15:5,16:4,17:3,18:2,19:1"
  go run main.go -cycle-minutes 60 -interpolate-values -time-relative-to-start=false -schedule "0:0,60:60" # minute clock (continuous)
  go run main.go -cycle-minutes $[24*60] -time-relative-to-start=false -schedule "0:0,1440:24" # UTC hour clock (discrete)

To update the static value via curl:
  curl -X PUT -H "Content-Type: application/json" -d '{"value":5}' http://localhost:8080/api/v1/staticmetrics

For more information or contributions, visit the repository or contact the developers.`
	fmt.Println(helpContent)
}

func mustGetParamValue[T string | int | bool | float64](name string, val T) (T, bool) {
	flagSet := false
	flag.Visit(func(f *flag.Flag) {
		if f.Name == name {
			flagSet = true
		}
	})
	envValue, envVarSet := os.LookupEnv(strings.ReplaceAll(strings.ToUpper(name), "-", "_"))
	if !flagSet && envVarSet {
		var result any
		// envValue to T
		switch fmt.Sprintf("%T", *new(T)) {
		case "string":
			result = envValue
		case "int":
			intValue, err := strconv.Atoi(envValue)
			if err != nil {
				panic(fmt.Errorf("[%s] could not parse value of '%s' to int", name, envValue))
			}
			result = intValue
		case "bool":
			result = envValue == "true"
		case "float64":
			floatValue, err := strconv.ParseFloat(envValue, 64)
			if err != nil {
				panic(fmt.Errorf("[%s] could not parse value of '%s' to float64", name, envValue))
			}
			result = floatValue
		}
		return result.(T), true
	}
	return val, flagSet
}
