package main

import (
	"encoding/json"
	"fmt"
	"math/rand"
	"net/http"
	"os"
	"sync"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

const (
	ServiceName       = "api-service"
	HealthEndpoint    = "/health"
	VersionEndpoint   = "/version"
	MetricsEndpoint   = "/metrics"
	FailRateEnvVar    = "FAIL_RATE"
	DefaultFailRate   = 0.0
	MethodNotAllowed  = "Method not allowed"
	ContentTypeHeader = "Content-Type"
	JsonContentType   = "application/json"
)

type HealthResponse struct {
	Status    string `json:"status"`
	Timestamp string `json:"timestamp"`
	Service   string `json:"service"`
}

type VersionResponse struct {
	Version   string `json:"version"`
	BuildTime string `json:"buildTime"`
	GitCommit string `json:"gitCommit"`
}

var (
	RequestCount = prometheus.NewCounter(prometheus.CounterOpts{
		Name:        "http_requests_total",
		Help:        "Total number of HTTP requests",
		ConstLabels: prometheus.Labels{"service": ServiceName},
	})
	RequestErrors = prometheus.NewCounter(prometheus.CounterOpts{
		Name:        "http_requests_errors_total",
		Help:        "Total number of HTTP requests resulting in errors",
		ConstLabels: prometheus.Labels{"service": ServiceName},
	})
	RequestLatency = prometheus.NewHistogram(prometheus.HistogramOpts{
		Name:        "http_request_duration_seconds",
		Help:        "HTTP request latency in seconds",
		ConstLabels: prometheus.Labels{"service": ServiceName},
		Buckets:     []float64{0.001, 0.01, 0.1, 0.3, 0.5, 1.0, 2.0, 5.0},
	})
)

func init() {
	prometheus.MustRegister(RequestCount, RequestErrors, RequestLatency)
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, MethodNotAllowed, http.StatusMethodNotAllowed)
		return
	}

	// Simulate processing time
	time.Sleep(time.Duration(rand.Intn(100)) * time.Millisecond)

	response := HealthResponse{
		Status:    "healthy",
		Timestamp: time.Now().UTC().Format(time.RFC3339),
		Service:   ServiceName,
	}

	w.Header().Set(ContentTypeHeader, JsonContentType)
	w.WriteHeader(http.StatusOK)
	if err := json.NewEncoder(w).Encode(response); err != nil {
		RequestErrors.Inc()
	}
}

func versionHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, MethodNotAllowed, http.StatusMethodNotAllowed)
		return
	}

	response := VersionResponse{
		Version:   "1.0.0",
		BuildTime: "2024-01-01T00:00:00Z",
		GitCommit: "abc1234",
	}

	w.Header().Set(ContentTypeHeader, JsonContentType)
	w.WriteHeader(http.StatusOK)
	if err := json.NewEncoder(w).Encode(response); err != nil {
		RequestErrors.Inc()
	}
}

func metricsHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, MethodNotAllowed, http.StatusMethodNotAllowed)
		return
	}

	// Handle Prometheus metrics
	promhttp.Handler().ServeHTTP(w, r)
}

func fallbackHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodGet && r.URL.Path == "/" {
		w.Header().Set("Content-Type", "text/plain")
		w.WriteHeader(http.StatusOK)
		fmt.Fprintln(w, "API Service - use /health, /version, or /metrics")
		return
	}

	http.NotFound(w, r)
}

type loggingResponseWriter struct {
	http.ResponseWriter
	statusCode int
	mu         sync.Mutex
}

func (lrw *loggingResponseWriter) Header() http.Header {
	return lrw.ResponseWriter.Header()
}

func (lrw *loggingResponseWriter) WriteHeader(code int) {
	lrw.mu.Lock()
	defer lrw.mu.Unlock()
	lrw.statusCode = code
	lrw.ResponseWriter.WriteHeader(code)
}

func requestMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		RequestCount.Inc()

		// Determine if this request should fail based on FAIL_RATE environment variable
		failRateStr := os.Getenv(FailRateEnvVar)
		failRate := DefaultFailRate
		if failRateStr != "" {
			if parsedRate, err := fmt.Sscanf(failRateStr, "%f", &failRate); err == nil && parsedRate == 1 {
				// Generate random number to determine if request fails
				if rand.Float64() < failRate {
					RequestErrors.Inc()
					w.WriteHeader(http.StatusInternalServerError)
					fmt.Fprintln(w, "Service Unavailable: Simulated failure")
					return
				}
			}
		}

		// Create response writer to capture status code
		lrw := &loggingResponseWriter{ResponseWriter: w, statusCode: http.StatusOK}
		next(lrw, r)

		// Record latency
		latency := time.Since(start).Seconds()
		RequestLatency.Observe(latency)
	}
}

func main() {
	// Set up handlers with middleware
	http.HandleFunc(HealthEndpoint, requestMiddleware(healthHandler))
	http.HandleFunc(VersionEndpoint, requestMiddleware(versionHandler))
	http.HandleFunc(MetricsEndpoint, requestMiddleware(metricsHandler))
	http.HandleFunc("/", fallbackHandler)

	// Parse fail rate from environment
	failRate := os.Getenv(FailRateEnvVar)
	if failRate != "" {
		fmt.Printf("Starting %s with FAIL_RATE=%s\n", ServiceName, failRate)
	} else {
		fmt.Printf("Starting %s with default fail rate (0.0)\n", ServiceName)
	}

	// Start server
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	addr := ":" + port
	fmt.Printf("Server starting on %s\n", addr)

	if err := http.ListenAndServe(addr, nil); err != nil {
		fmt.Printf("Server error: %v\n", err)
		os.Exit(1)
	}
}
