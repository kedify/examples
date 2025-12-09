package main

import (
	"context"
	"crypto/tls"
	"fmt"
	"log"
	"math/rand"
	"net"
	"net/http"
	"net/http/httputil"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.4.0"
	"go.opentelemetry.io/otel/trace"
)

type DelayConfig struct {
	TLSAcceptDelay  time.Duration
	TLSReadDelay    time.Duration
	TLSWriteDelay   time.Duration
	TLSDelayTimeout time.Duration
	FixedDelay      time.Duration
	IsRange         bool
	MinDelay        float64
	MaxDelay        float64
	ErrorRate       float64
	ErrorRespCode   int
}

type tlsListenerWithDelay struct {
	net.Listener
	acceptDelay  time.Duration
	delayTimeout time.Duration
	readDelay    time.Duration
	writeDelay   time.Duration
}

type tlsConnWithDelay struct {
	net.Conn
	delayTimeout time.Duration
	readDelay    time.Duration
	writeDelay   time.Duration
}

func (c *tlsConnWithDelay) Read(b []byte) (n int, err error) {
	if c.readDelay > 0 && !delayExpired(c.delayTimeout) {
		log.Printf("Delaying TLS read by %v", c.readDelay)
		time.Sleep(c.readDelay)
	}
	return c.Conn.Read(b)
}

func (c *tlsConnWithDelay) Write(b []byte) (n int, err error) {
	if c.writeDelay > 0 && !delayExpired(c.delayTimeout) {
		log.Printf("Delaying TLS write by %v", c.writeDelay)
		time.Sleep(c.writeDelay)
	}
	return c.Conn.Write(b)
}

func (l *tlsListenerWithDelay) Accept() (net.Conn, error) {
	conn, err := l.Listener.Accept()
	if err != nil {
		return nil, err
	}
	if l.acceptDelay > 0 && !delayExpired(l.delayTimeout) {
		log.Printf("Delaying TLS connection acceptance by %v", l.acceptDelay)
		time.Sleep(l.acceptDelay)
	}
	delayedConn := &tlsConnWithDelay{
		Conn:         conn,
		readDelay:    l.readDelay,
		writeDelay:   l.writeDelay,
		delayTimeout: l.delayTimeout,
	}
	return delayedConn, nil
}

func delayExpired(timeout time.Duration) bool {
	if timeout <= 0 {
		return false
	}
	return time.Since(startDelayTimeout) > timeout
}

func proxyHandler(w http.ResponseWriter, r *http.Request) {
	log.Printf("/proxy received request from[%v] path[%v] host[%v]", r.RemoteAddr, r.URL.Path, r.Host)
	requests.WithLabelValues("/proxy").Inc()
	delay := getDelay()
	delayHistogram.Observe(delay.Seconds())
	time.Sleep(delay)

	targetURL := "http://" + r.PathValue("rest")
	log.Printf("Proxying request to: %s", targetURL)
	req, err := http.NewRequest(r.Method, targetURL, nil)
	if err != nil {
		http.Error(w, fmt.Sprintf("Error creating request: %v", err), http.StatusInternalServerError)
		return
	}
	req.Header["Host"] = []string{r.URL.Host}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		http.Error(w, fmt.Sprintf("Error fetching URL: %v", err), http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()

	for name, values := range resp.Header {
		for _, v := range values {
			w.Header().Add(name, v)
		}
	}
	w.WriteHeader(resp.StatusCode)
	_, err = httputil.DumpResponse(resp, true)
	if err != nil {
		http.Error(w, fmt.Sprintf("Error reading response: %v", err), http.StatusInternalServerError)
		return
	}
}

var (
	// delays
	startDelayTimeout = time.Now()

	// otel
	tracer trace.Tracer

	// prometheus
	requests = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "http_requests_total",
			Help: "Total number of requests to the handlers.",
		},
		[]string{"endpoint"},
	)
	delayHistogram prometheus.Histogram

	// response
	cfg             DelayConfig
	rng             = rand.New(rand.NewSource(time.Now().UnixNano()))
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
	if os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT") != "" {
		endpointStr := os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
		log.Println("Initializing OpenTelemetry exporter", "endpoint:", endpointStr)
		exp, err := otlptracegrpc.New(context.Background(),
			otlptracegrpc.WithEndpoint(endpointStr),
			otlptracegrpc.WithInsecure(),
		)
		if err != nil {
			log.Fatalf("failed to initialize exporter: %v", err)
		}
		bsp := sdktrace.NewBatchSpanProcessor(exp)
		tp := sdktrace.NewTracerProvider(
			sdktrace.WithSampler(sdktrace.AlwaysSample()),
			sdktrace.WithResource(resource.NewWithAttributes(
				semconv.SchemaURL,
				semconv.ServiceNameKey.String("example-http-server"),
			)),
			sdktrace.WithSpanProcessor(bsp),
		)
		tracer = tp.Tracer("example-http-server")
		otel.SetTracerProvider(tp)
		otel.SetTextMapPropagator(propagation.TraceContext{})
	}

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
	mux.HandleFunc("/error", errorHandler)
	mux.HandleFunc("/proxy/{rest...}", proxyHandler)
	mux.Handle("/metrics", promhttp.Handler())

	addr := ":8080"
	if tlsEnabled {
		addr = ":8443"
	}
	if port := os.Getenv("PORT"); port != "" {
		addr = ":" + port
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

	errorRate := os.Getenv("ERROR_RATE")
	if errorRate != "" {
		rateFloat, err := strconv.ParseFloat(errorRate, 64)
		if err != nil || rateFloat < 0 || rateFloat > 1 {
			log.Printf("Invalid ERROR_RATE value: %v", errorRate)
		}
		cfg.ErrorRate = rateFloat
		log.Printf("Simulating errors with a rate of %.2f%% on /error endpoint", cfg.ErrorRate*100)
	} else {
		log.Println("No error simulation configured")
	}

	cfg.ErrorRespCode = http.StatusServiceUnavailable
	errorRespCode := os.Getenv("ERROR_RESP_CODE")
	if errorRespCode != "" {
		code, err := strconv.Atoi(errorRespCode)
		if err != nil || code < 400 || code > 599 {
			log.Printf("Invalid ERROR_RESP_CODE value: %v, using default %d: %v", errorRespCode, cfg.ErrorRespCode, err)
		}
		cfg.ErrorRespCode = code
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
		baseListener, err := net.Listen("tcp", addr)
		if err != nil {
			log.Fatalf("Failed to listen on %s: %v", addr, err)
		}
		// Wrap the listener to add a delay on Accept
		listener := &tlsListenerWithDelay{
			Listener:     baseListener,
			acceptDelay:  cfg.TLSAcceptDelay,
			readDelay:    cfg.TLSReadDelay,
			writeDelay:   cfg.TLSWriteDelay,
			delayTimeout: cfg.TLSDelayTimeout,
		}
		log.Fatal(server.ServeTLS(listener, "", ""))
	} else {
		log.Fatal(server.ListenAndServe())
	}
}

func homeHandler(w http.ResponseWriter, r *http.Request) {
	if tracer != nil {
		ctx := otel.GetTextMapPropagator().Extract(r.Context(), propagation.HeaderCarrier(r.Header))
		_, span := tracer.Start(ctx, "homeHandler")
		defer span.End()
		span.SetAttributes(attribute.String("http.method", r.Method))
		log.Printf("Tracing enabled: %v", span.SpanContext().IsSampled())
	}

	log.Printf("/ received request from[%v] path[%v] host[%v]", r.RemoteAddr, r.URL.Path, r.Host)
	requests.WithLabelValues("/").Inc()
	delay := getDelay()
	delayHistogram.Observe(delay.Seconds())
	time.Sleep(delay)
	w.Header().Set("Content-Type", "text/html")
	if pn := os.Getenv("POD_NAME"); pn != "" {
		w.Header().Set("X-Pod-Name", pn)
	}
	if pn := os.Getenv("POD_NAMESPACE"); pn != "" {
		w.Header().Set("X-Pod-Namespace", pn)
	}
	if pi := os.Getenv("POD_IP"); pi != "" {
		w.Header().Set("X-Pod-IP", pi)
	}

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

	// Try container path first, then local path (for go run)
	imagePath := "/kedify-loves-keda.gif"
	if _, err := os.Stat(imagePath); os.IsNotExist(err) {
		imagePath = "./kedify-loves-keda.gif"
	}

	http.ServeFile(w, r, imagePath)
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

func errorHandler(w http.ResponseWriter, r *http.Request) {
	log.Printf("/error received request from[%v] path[%v] host[%v]", r.RemoteAddr, r.URL.Path, r.Host)
	requests.WithLabelValues("/error").Inc()
	delay := getDelay()
	delayHistogram.Observe(delay.Seconds())
	time.Sleep(delay)

	// Simulate an error response based on the configured error rate
	if cfg.ErrorRate > 0 && rng.Float64() < cfg.ErrorRate {
		log.Printf("Simulating error response for /error endpoint")
		http.Error(w, "Simulated error response", cfg.ErrorRespCode)
	} else {
		log.Printf("No error simulated for /error endpoint")
	}
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

	fmt.Fprintln(w, "\nRequest Headers:")
	for name, values := range r.Header {
		for _, v := range values {
			fmt.Fprintf(w, "%s: %s\n", name, v)
		}
	}
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
	tlsAcceptDelayStr := os.Getenv("TLS_ACCEPT_DELAY")
	if tlsAcceptDelayStr != "" {
		tlsDelay, err := strconv.ParseFloat(tlsAcceptDelayStr, 64)
		if err != nil {
			return c, fmt.Errorf("invalid TLS_ACCEPT_DELAY value: %v", err)
		}
		c.TLSAcceptDelay = time.Duration(tlsDelay * float64(time.Second))
	}
	tlsReadDelayStr := os.Getenv("TLS_READ_DELAY")
	if tlsReadDelayStr != "" {
		tlsDelay, err := strconv.ParseFloat(tlsReadDelayStr, 64)
		if err != nil {
			return c, fmt.Errorf("invalid TLS_READ_DELAY value: %v", err)
		}
		c.TLSReadDelay = time.Duration(tlsDelay * float64(time.Second))
	}
	tlsWriteDelayStr := os.Getenv("TLS_WRITE_DELAY")
	if tlsWriteDelayStr != "" {
		tlsDelay, err := strconv.ParseFloat(tlsWriteDelayStr, 64)
		if err != nil {
			return c, fmt.Errorf("invalid TLS_WRITE_DELAY value: %v", err)
		}
		c.TLSWriteDelay = time.Duration(tlsDelay * float64(time.Second))
	}
	tlsDelayTimeoutStr := os.Getenv("TLS_DELAY_TIMEOUT")
	if tlsDelayTimeoutStr != "" {
		tlsTimeout, err := strconv.ParseFloat(tlsDelayTimeoutStr, 64)
		if err != nil {
			return c, fmt.Errorf("invalid TLS_DELAY_TIMEOUT value: %v", err)
		}
		c.TLSDelayTimeout = time.Duration(tlsTimeout * float64(time.Second))
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
