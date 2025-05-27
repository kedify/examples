package main

import (
	"crypto/tls"
	"fmt"
	"log"
	"math/rand"
	"net/http"
	"net/http/httputil"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

type DelayConfig struct {
	FixedDelay time.Duration
	IsRange    bool
	MinDelay   float64
	MaxDelay   float64
}

var (
	requests = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "http_requests_total",
			Help: "Total number of requests to the handlers.",
		},
		[]string{"endpoint"},
	)
	delayHistogram prometheus.Histogram
	cfg            DelayConfig
	rng            = rand.New(rand.NewSource(time.Now().UnixNano()))

	defaultResponse = `<!DOCTYPE html>
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
)

func init() {
	prometheus.MustRegister(requests)

	var err error
	cfg, err = parseDelay()
	if err != nil {
		log.Printf("Error parsing delay: %v", err)
	}

	var buckets []float64
	if cfg.IsRange {
		// For a range, use 10 buckets covering the specified range.
		start := cfg.MinDelay
		width := (cfg.MaxDelay - cfg.MinDelay) / 10.0
		buckets = prometheus.LinearBuckets(start, width, 10)
	} else {
		// For a fixed delay or no delay, use just one bucket.
		// If a fixed delay is set, use its value as the boundary; otherwise default to 0.
		var boundary float64
		if cfg.FixedDelay > 0 {
			boundary = float64(cfg.FixedDelay) / float64(time.Second)
		} else {
			boundary = 0
		}
		buckets = []float64{boundary}
	}

	delayHistogram = prometheus.NewHistogram(prometheus.HistogramOpts{
		Name:    "response_delay_seconds",
		Help:    "Distribution of response delays in seconds",
		Buckets: buckets,
	})
	prometheus.MustRegister(delayHistogram)
}

func main() {
	tlsEnabled := os.Getenv("TLS_ENABLED") == "true"
	certFile := os.Getenv("TLS_CERT_FILE")
	keyFile := os.Getenv("TLS_KEY_FILE")

	mux := http.NewServeMux()
	mux.HandleFunc("/", homeHandler)
	mux.HandleFunc("/image", imageHandler)
	mux.HandleFunc("/echo", echoHandler)
	mux.HandleFunc("/info", infoHandler)
	mux.Handle("/metrics", promhttp.Handler())

	addr := ":8080"
	if tlsEnabled {
		addr = ":8443"
	}

	server := &http.Server{
		Addr:    addr,
		Handler: mux,
	}

	delayDesc := "no delay"
	if cfg.IsRange {
		delayDesc = fmt.Sprintf("random delay between %.2f and %.2f seconds", cfg.MinDelay, cfg.MaxDelay)
	} else if cfg.FixedDelay > 0 {
		delayDesc = fmt.Sprintf("fixed delay of %.2f seconds", float64(cfg.FixedDelay)/float64(time.Second))
	}
	log.Printf("Server is running on %s with %s (TLS: %v)\n", addr, delayDesc, tlsEnabled)

	if tlsEnabled {
		if certFile == "" || keyFile == "" {
			log.Fatal("TLS_ENABLED=true but TLS_CERT_FILE or TLS_KEY_FILE not set")
		}
		tlsConfig, err := loadTLSConfig(certFile, keyFile)
		if err != nil {
			log.Fatalf("Failed to load TLS config: %v", err)
		}
		server.TLSConfig = tlsConfig
		// certFile and keyFile are empty here so ListenAndServeTLS uses server.TLSConfig.Certificates
		log.Fatal(server.ListenAndServeTLS("", ""))
	} else {
		log.Fatal(server.ListenAndServe())
	}
}

func homeHandler(w http.ResponseWriter, r *http.Request) {
	log.Printf("/ received request from[%v] path[%v] host[%v]", r.RemoteAddr, r.URL.Path, r.Host)
	requests.WithLabelValues("/").Inc()
	delay := getDelay()
	delayHistogram.Observe(delay.Seconds())
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
}

func imageHandler(w http.ResponseWriter, r *http.Request) {
	log.Printf("/image received request from[%v] path[%v] host[%v]", r.RemoteAddr, r.URL.Path, r.Host)
	requests.WithLabelValues("/image").Inc()
	delay := getDelay()
	delayHistogram.Observe(delay.Seconds())
	time.Sleep(delay)
	http.ServeFile(w, r, "kedify-loves-keda.gif")
}

func echoHandler(w http.ResponseWriter, r *http.Request) {
	log.Printf("/echo received request from[%v] path[%v] host[%v]", r.RemoteAddr, r.URL.Path, r.Host)
	requests.WithLabelValues("/echo").Inc()
	delay := getDelay()
	delayHistogram.Observe(delay.Seconds())
	time.Sleep(delay)
	w.Header().Set("Content-Type", "text/plain")
	dump, err := httputil.DumpRequest(r, true)
	if err != nil {
		fmt.Fprintf(w, "Error dumping request: %v", err)
		return
	}
	w.Write(dump)
}

func infoHandler(w http.ResponseWriter, r *http.Request) {
	log.Printf("/info received request from[%v] path[%v] host[%v]", r.RemoteAddr, r.URL.Path, r.Host)
	requests.WithLabelValues("/info").Inc()
	delay := getDelay()
	delayHistogram.Observe(delay.Seconds())
	time.Sleep(delay)
	w.Header().Set("Content-Type", "text/plain")
	fmt.Fprintf(w, "delay config:  %+v\n", cfg)
	fmt.Fprintf(w, "POD_NAME:      %v\n", os.Getenv("POD_NAME"))
	fmt.Fprintf(w, "POD_NAMESPACE: %v\n", os.Getenv("POD_NAMESPACE"))
	fmt.Fprintf(w, "POD_IP:        %v\n", os.Getenv("POD_IP"))
}

func loadTLSConfig(certFile, keyFile string) (*tls.Config, error) {
	cert, err := tls.LoadX509KeyPair(certFile, keyFile)
	if err != nil {
		return nil, err
	}

	return &tls.Config{
		Certificates: []tls.Certificate{cert},
		MinVersion:   tls.VersionTLS12,
	}, nil
}

// parseDelay parses the RESPONSE_DELAY environment variable to set a fixed delay or a range of delays.
// If the variable is not set, no delay is applied.
// If the variable is set to a single value, that value is used as a fixed delay.
// If the variable is set to a range (e.g., "1-5"), a random delay within that range is applied.
// The delay is specified in seconds.
func parseDelay() (DelayConfig, error) {
	var c DelayConfig
	delayStr := os.Getenv("RESPONSE_DELAY")
	if delayStr == "" {
		return c, nil
	}
	if strings.Contains(delayStr, "-") {
		c.IsRange = true
		parts := strings.Split(delayStr, "-")
		if len(parts) != 2 {
			return c, fmt.Errorf("invalid delay range format: %s", delayStr)
		}
		minVal, err1 := strconv.ParseFloat(strings.TrimSpace(parts[0]), 64)
		maxVal, err2 := strconv.ParseFloat(strings.TrimSpace(parts[1]), 64)
		if err1 != nil || err2 != nil {
			return c, fmt.Errorf("invalid delay range values: %s", delayStr)
		}
		if minVal > maxVal {
			return c, fmt.Errorf("invalid delay range: min %v > max %v", minVal, maxVal)
		}
		c.MinDelay = minVal
		c.MaxDelay = maxVal
	} else {
		d, err := strconv.ParseFloat(delayStr, 64)
		if err != nil {
			return c, fmt.Errorf("invalid delay value: %v", err)
		}
		c.FixedDelay = time.Duration(d * float64(time.Second))
	}
	return c, nil
}

func getDelay() time.Duration {
	if cfg.IsRange {
		chosen := cfg.MinDelay + rng.Float64()*(cfg.MaxDelay-cfg.MinDelay)
		return time.Duration(chosen * float64(time.Second))
	}
	return cfg.FixedDelay
}
