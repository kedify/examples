package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	// Define a counter metric for the root and image handlers
	requests = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "http_requests_total",
			Help: "Total number of requests to the handlers.",
		},
		[]string{"endpoint"},
	)
)

func init() {
	// Register custom metrics with Prometheus
	prometheus.MustRegister(requests)
}

func main() {
	delay := getDelay()

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		requests.WithLabelValues("/").Inc() // Increment the counter for root endpoint
		fmt.Println("Received request from", r.RemoteAddr)
		time.Sleep(delay)
		w.Header().Set("Content-Type", "text/html")
		htmlContent := `
			<!DOCTYPE html>
			<html>
			<head>
				<title>Kedify <3 KEDA!</title>
				<style>
					body, html {
						height: 100%;
						margin: 0;
						display: flex;
						justify-content: center;
						align-items: center;
					}
				</style>
			</head>
			<body>
				<div><img src='/image'></div>
			</body>
			</html>
		`
		fmt.Fprint(w, htmlContent)
	})

	http.HandleFunc("/image", func(w http.ResponseWriter, r *http.Request) {
		requests.WithLabelValues("/image").Inc() // Increment the counter for image endpoint
		time.Sleep(delay)
		http.ServeFile(w, r, "kedify-loves-keda.gif")
	})

	// Expose the default Prometheus metrics at `/metrics` endpoint
	http.Handle("/metrics", promhttp.Handler())

	fmt.Println("Server is running on http://localhost:8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}

func getDelay() time.Duration {
	delayStr := os.Getenv("RESPONSE_DELAY")
	if delayStr == "" {
		return 0
	}
	delay, err := strconv.ParseFloat(delayStr, 64)
	if err != nil {
		log.Printf("Invalid delay value: %v", err)
		return 0
	}
	return time.Duration(delay * float64(time.Second))
}