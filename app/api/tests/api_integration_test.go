package api_test

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/claudcoding/api-service/src"
)

func TestIntegration_FullFlow(t *testing.T) {
	// Test health endpoint
	healthReq := httptest.NewRequest(http.MethodGet, "/health", nil)
	healthW := httptest.NewRecorder()
	src.HealthHandler(healthW, healthReq)

	if healthW.Code != http.StatusOK {
		t.Fatalf("Health check failed: %d", healthW.Code)
	}

	// Test version endpoint
	versionReq := httptest.NewRequest(http.MethodGet, "/version", nil)
	versionW := httptest.NewRecorder()
	src.VersionHandler(versionW, versionReq)

	if versionW.Code != http.StatusOK {
		t.Fatalf("Version check failed: %d", versionW.Code)
	}

	fmt.Println("Integration test passed")
}

func TestIntegration_PrometheusMetrics(t *testing.T) {
	// Simulate request to metrics endpoint
	req := httptest.NewRequest(http.MethodGet, "/metrics", nil)
	w := httptest.NewRecorder()
	src.MetricsHandler(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("Metrics endpoint failed: %d", w.Code)
	}

	fmt.Println("Prometheus metrics test passed")
}