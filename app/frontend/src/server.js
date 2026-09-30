const express = require('express');
const fetch = require('node-fetch');
const promClient = require('prom-client');
const os = require('os');
const versionInfo = require('./version.json');

// Create Express app
const app = express();
const port = process.env.PORT || 3000;

// Prometheus metrics
const register = new promClient.Registry();
promClient.collectDefaultMetrics({ register });

// Custom metrics
const requestCount = new promClient.Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status_code']
});

const requestErrors = new promClient.Counter({
  name: 'http_requests_errors_total',
  help: 'Total number of HTTP requests resulting in errors',
  labelNames: ['method', 'route', 'status_code']
});

const requestLatency = new promClient.Histogram({
  name: 'http_request_duration_seconds',
  help: 'HTTP request latency in seconds',
  labelNames: ['method', 'route'],
  buckets: [0.001, 0.01, 0.1, 0.3, 0.5, 1.0, 2.0, 5.0]
});

register.registerMetric(requestCount);
register.registerMetric(requestErrors);
register.registerMetric(requestLatency);

// Middleware to capture metrics
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const duration = (Date.now() - start) / 1000;
    requestCount.inc({
      method: req.method,
      route: req.route ? req.route.path : req.path,
      status_code: res.statusCode
    });

    if (res.statusCode >= 400) {
      requestErrors.inc({
        method: req.method,
        route: req.route ? req.route.path : req.path,
        status_code: res.statusCode
      });
    }

    requestLatency.observe({
      method: req.method,
      route: req.route ? req.route.path : req.path
    }, duration);
  });
  next();
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    service: 'frontend-service',
    uptime: process.uptime()
  });
});

// Version endpoint
app.get('/version', (req, res) => {
  res.json({
    version: versionInfo.version,
    buildTime: versionInfo.buildTime,
    gitCommit: versionInfo.gitCommit,
    nodeVersion: process.version,
    platform: os.platform()
  });
});

// Metrics endpoint
app.get('/metrics', (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(register.metrics());
});

// Main endpoint
app.get('/', (req, res) => {
  res.set('Content-Type', 'text/plain');
  res.status(200).send('Frontend Service - use /health, /version, or /metrics');
});

// API proxy endpoint - calls the API service
app.get('/api/health', async (req, res) => {
  try {
    const response = await fetch('http://localhost:8080/health');
    const data = await response.json();
    res.json({
      ...data,
      source: 'frontend-proxy',
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    res.status(500).json({
      status: 'unhealthy',
      error: error.message,
      source: 'frontend-proxy',
      timestamp: new Date().toISOString()
    });
  }
});

// Error handling middleware
app.use((err, req, res, next) => {
  requestErrors.inc({
    method: req.method,
    route: req.route ? req.route.path : req.path,
    status_code: 500
  });

  res.status(500).json({
    status: 'error',
    message: err.message
  });
});

// 404 handler
app.use((req, res) => {
  requestErrors.inc({
    method: req.method,
    route: req.route ? req.route.path : req.path,
    status_code: 404
  });

  res.status(404).json({
    status: 'error',
    message: 'Not Found'
  });
});

// Start server
app.listen(port, () => {
  console.log(`Frontend service starting on port ${port}`);
  console.log(`Health check: http://localhost:${port}/health`);
  console.log(`API health check: http://localhost:${port}/api/health`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down gracefully');
  process.exit(0);
});

process.on('SIGINT', () => {
  console.log('SIGINT received, shutting down gracefully');
  process.exit(0);
});

module.exports = app;