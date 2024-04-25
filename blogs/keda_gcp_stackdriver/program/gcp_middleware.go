package main

import (
	"context"
	"log"
	"net/http"
	"sync/atomic"
	"time"

	monitoring "cloud.google.com/go/monitoring/apiv3/v2"
	monitoringpb "cloud.google.com/go/monitoring/apiv3/v2/monitoringpb"
	"github.com/labstack/echo/v4"
	metricpb "google.golang.org/genproto/googleapis/api/metric"
	monitoredres "google.golang.org/genproto/googleapis/api/monitoredres"
	"google.golang.org/protobuf/types/known/timestamppb"
)

var (
	errorCount int64
)

func init() {
	// Start a goroutine to send metrics every minute
	go func() {
		ticker := time.NewTicker(30 * time.Second)
		for _ = range ticker.C {
			sendMetric()
		}
	}()
}

// ErrorRateMiddleware checks if the response status is 500 and logs it to Google Cloud Monitoring
func ErrorRateMiddleware(next echo.HandlerFunc) echo.HandlerFunc {
	return func(c echo.Context) error {
		response := next(c)
		// Check if response status code is 500
		if c.Response().Status == http.StatusInternalServerError {
			atomic.AddInt64(&errorCount, 1) // Increment error count atomically
			// if err := writeTimeSeriesValue(); err != nil {
			// 	log.Printf("Error writing time series value: %v", err)
			// }
		}
		return response
	}
}

func sendMetric() {
	// Swap the current error count with zero atomically and get the old value
	count := atomic.SwapInt64(&errorCount, 0)
	if count == 0 {
		return // No errors to report
	}

	ctx := context.Background()
	client, err := monitoring.NewMetricClient(ctx)
	if err != nil {
		log.Printf("Error creating Metric client: %v", err)
		return
	}
	defer client.Close()

	now := timestamppb.Now()
	req := &monitoringpb.CreateTimeSeriesRequest{
		Name: "projects/" + projectID,
		TimeSeries: []*monitoringpb.TimeSeries{{
			Metric: &metricpb.Metric{
				Type: metricType,
				Labels: map[string]string{
					"environment": "dev",
				},
			},
			Resource: &monitoredres.MonitoredResource{
				Type: "generic_node",
				Labels: map[string]string{
					"project_id": projectID,
					"location":   "us-central1-a",
					"namespace":  "default",
					"node_id":    "192.168.0.1",
				},
			},
			Points: []*monitoringpb.Point{{
				Interval: &monitoringpb.TimeInterval{
					StartTime: now,
					EndTime:   now,
				},
				Value: &monitoringpb.TypedValue{
					Value: &monitoringpb.TypedValue_Int64Value{
						Int64Value: count,
					},
				},
			}},
		}},
	}

	if err := client.CreateTimeSeries(ctx, req); err != nil {
		log.Printf("Error writing time series value: %v", err)
	} else {
		log.Println("Metric successfully sent with count:", count)
	}
}

// writeTimeSeriesValue writes a value for the custom metric created
// func writeTimeSeriesValue() error {
// 	ctx := context.Background()
// 	client, err := monitoring.NewMetricClient(ctx)
// 	if err != nil {
// 		return err
// 	}
// 	defer client.Close()

// 	now := timestamppb.Now()
// 	req := &monitoringpb.CreateTimeSeriesRequest{
// 		Name: "projects/" + projectID,
// 		TimeSeries: []*monitoringpb.TimeSeries{{
// 			Metric: &metricpb.Metric{
// 				Type: metricType,
// 				Labels: map[string]string{
// 					"environment": "dev",
// 				},
// 			},
// 			Resource: &monitoredres.MonitoredResource{
// 				Type: "generic_node",
// 				Labels: map[string]string{
// 					"project_id": projectID,
// 					"location":   "us-central1-a",
// 					"namespace":  "default",
// 					"node_id":    "192.168.0.1",
// 				},
// 			},
// 			Points: []*monitoringpb.Point{{
// 				Interval: &monitoringpb.TimeInterval{
// 					StartTime: now,
// 					EndTime:   now,
// 				},
// 				Value: &monitoringpb.TypedValue{
// 					Value: &monitoringpb.TypedValue_Int64Value{
// 						Int64Value: 1, // Reporting a count of one error occurrence
// 					},
// 				},
// 			}},
// 		}},
// 	}

// 	if err := client.CreateTimeSeries(ctx, req); err != nil {
// 		return err
// 	}

// 	slog.Info("Metric successfully sent")
// 	return nil
// }
