package main

import (
	"fmt"
	"log"
	"log/slog"
	"math/rand"
	"net/http"
	"os"
	"strconv"
	"sync/atomic"
	"time"

	"github.com/labstack/echo/v4"
)

var (
	// Concurrency counter
	currentRequests int32
	// Threshold for starting to return HTTP 500
	requestThreshold int32 = 10 // Example threshold
)

var projectID = ""
var requestDelayTime int = 1
var metricType = "custom.googleapis.com/500_error_rate"

func main() {
	projectID = os.Getenv("PROJECT_ID")
	if projectID == "" {
		log.Fatal("PROJECT_ID environment variable is required")
	}
	fmt.Println("PROJECT_ID", projectID)

	rdt := os.Getenv("REQUEST_DELAY_TIME")
	if rdt != "" {
		rdtInt, err := strconv.Atoi(rdt)
		if err != nil {
			log.Fatalf("Invalid value provided for REQUEST_DELAY_TIME %s", rdt)
		}
		requestDelayTime = rdtInt
	}
	fmt.Println("REQUEST_DELAY_TIME", requestDelayTime)

	rt := os.Getenv("REQUEST_THRESHOLD")
	if rt != "" {
		rtInt, _ := strconv.Atoi(rt)
		requestThreshold = int32(rtInt)
		slog.Info("Request threshold set to", slog.Any("value", requestThreshold))
	}
	fmt.Println("REQUEST_THRESHOLD", requestThreshold)
	e := echo.New()

	// Middleware to simulate load
	e.Use(ErrorRateMiddleware)
	e.Use(simulateLoadMiddleware)

	// Routes
	e.GET("/", getUserData)

	// Start server
	e.Logger.Fatal(e.Start(":1323"))
}

// Handler
// Handler
func getUserData(c echo.Context) error {
	// Simulate database retrieval time
	// v := rand.Intn(10)
	slog.Info("Processing request...")
	time.Sleep(time.Duration(requestDelayTime) * time.Second)

	// Construct a response simulating user data retrieval
	userData := struct {
		ID    int
		Name  string
		Email string
	}{
		ID:    rand.Intn(1000),
		Name:  "John Doe",
		Email: "john.doe@example.com",
	}

	return c.JSON(http.StatusOK, userData)
}

// Middleware to simulate server load and conditionally trigger HTTP 500 errors
func simulateLoadMiddleware(next echo.HandlerFunc) echo.HandlerFunc {
	return func(c echo.Context) error {
		// Increment current requests
		if atomic.AddInt32(&currentRequests, 1) > requestThreshold {
			// return c.String(http.StatusInternalServerError, "Server is overloaded")
			c.String(http.StatusInternalServerError, "Server is overloaded")
			atomic.AddInt32(&currentRequests, -1) // Decrement the request count immediately
			return nil                            // Stop processing here
		}
		defer atomic.AddInt32(&currentRequests, -1) // Decrement on request completion

		return next(c)
	}
}
