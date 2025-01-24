package main

import (
    "fmt"
    "log"
    "math/rand"
    "net/http"
    "os"
    "strconv"
    "time"

    "github.com/prometheus/client_golang/prometheus"
    "github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
    // Counter: total number of /work requests
    requestsTotal = prometheus.NewCounter(prometheus.CounterOpts{
        Name: "work_simulator_requests_total",
        Help: "Total number of /work requests received by work-simulator",
    })

    // Gauge: number of tasks currently in progress
    inProgressTasks = prometheus.NewGauge(prometheus.GaugeOpts{
        Name: "work_simulator_inprogress_tasks",
        Help: "Number of tasks currently being processed by work-simulator",
    })
)

// Default min/max if env variables aren't set or are invalid
const (
    defaultMinSleep = 100
    defaultMaxSleep = 600
)

func init() {
    prometheus.MustRegister(requestsTotal, inProgressTasks)
}

func main() {
    rand.Seed(time.Now().UnixNano())

    minSleepMS, maxSleepMS := getSleepRange()
    log.Printf("Using min sleep: %dms, max sleep: %dms\n", minSleepMS, maxSleepMS)

    http.HandleFunc("/work", func(w http.ResponseWriter, r *http.Request) {
        requestsTotal.Inc()
        inProgressTasks.Inc()
        defer inProgressTasks.Dec()

        // Simulate dummy work: random sleep between minSleepMS and maxSleepMS
        durationMS := minSleepMS + rand.Intn(maxSleepMS-minSleepMS+1)
        time.Sleep(time.Duration(durationMS) * time.Millisecond)

        fmt.Fprintf(w, "Completed work in %d ms\n", durationMS)
    })

    // Expose metrics endpoint
    http.Handle("/metrics", promhttp.Handler())

    log.Println("work-simulator running on port 8080")
    log.Fatal(http.ListenAndServe(":8080", nil))
}

// getSleepRange returns [minSleepMS, maxSleepMS], with fallbacks on invalid or unset env vars
func getSleepRange() (int, int) {
    minEnv := os.Getenv("MIN_SLEEP_MS")
    maxEnv := os.Getenv("MAX_SLEEP_MS")

    minSleep := parseEnvOrDefault(minEnv, defaultMinSleep)
    maxSleep := parseEnvOrDefault(maxEnv, defaultMaxSleep)

    if maxSleep < minSleep {
        // If misconfigured (max < min), just swap them
        minSleep, maxSleep = maxSleep, minSleep
    }
    return minSleep, maxSleep
}

// parseEnvOrDefault tries to parse an integer from envVal, returns defaultVal on failure
func parseEnvOrDefault(envVal string, defaultVal int) int {
    if envVal == "" {
        return defaultVal
    }
    parsed, err := strconv.Atoi(envVal)
    if err != nil || parsed < 0 {
        return defaultVal
    }
    return parsed
}