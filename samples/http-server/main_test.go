package main

import (
	"testing"
	"time"
)

func TestParseDelayFixed(t *testing.T) {
	t.Setenv("RESPONSE_DELAY", "2")
	t.Setenv("STARTUP_DELAY", "")
	cfg, err := parseDelay()
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if cfg.FixedDelay != 2*time.Second {
		t.Errorf("expected FixedDelay %v, got %v", 2*time.Second, cfg.FixedDelay)
	}
	if cfg.IsRange {
		t.Errorf("expected IsRange false, got true")
	}
}

func TestParseDelayRange(t *testing.T) {
	t.Setenv("RESPONSE_DELAY", "1-3")
	t.Setenv("STARTUP_DELAY", "")
	cfg, err := parseDelay()
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if !cfg.IsRange {
		t.Errorf("expected IsRange true, got false")
	}
	if cfg.MinDelay != 1 {
		t.Errorf("expected MinDelay 1, got %v", cfg.MinDelay)
	}
	if cfg.MaxDelay != 3 {
		t.Errorf("expected MaxDelay 3, got %v", cfg.MaxDelay)
	}
}

func TestParseDelayInvalid(t *testing.T) {
	t.Setenv("RESPONSE_DELAY", "abc")
	t.Setenv("STARTUP_DELAY", "")
	_, err := parseDelay()
	if err == nil {
		t.Errorf("expected error for invalid delay value, got nil")
	}
}

func TestParseDelayInvalidRange(t *testing.T) {
	t.Setenv("RESPONSE_DELAY", "3-1")
	t.Setenv("STARTUP_DELAY", "")
	_, err := parseDelay()
	if err == nil {
		t.Errorf("expected error for invalid delay range, got nil")
	}
}

func TestParseDelayFloatFixed(t *testing.T) {
	t.Setenv("RESPONSE_DELAY", "2.5")
	t.Setenv("STARTUP_DELAY", "")
	cfg, err := parseDelay()
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	expected := time.Duration(2.5 * float64(time.Second))
	if cfg.FixedDelay != expected {
		t.Errorf("expected FixedDelay %v, got %v", expected, cfg.FixedDelay)
	}
	if cfg.IsRange {
		t.Errorf("expected IsRange false, got true")
	}
}

func TestParseDelayFloatRange(t *testing.T) {
	t.Setenv("RESPONSE_DELAY", "1.5-3.7")
	t.Setenv("STARTUP_DELAY", "")
	cfg, err := parseDelay()
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if !cfg.IsRange {
		t.Errorf("expected IsRange true, got false")
	}
	if cfg.MinDelay != 1.5 {
		t.Errorf("expected MinDelay 1.5, got %v", cfg.MinDelay)
	}
	if cfg.MaxDelay != 3.7 {
		t.Errorf("expected MaxDelay 3.7, got %v", cfg.MaxDelay)
	}
}

func TestParseDelayStartupOnly(t *testing.T) {
	t.Setenv("RESPONSE_DELAY", "")
	t.Setenv("STARTUP_DELAY", "12.5")
	cfg, err := parseDelay()
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	expected := time.Duration(12.5 * float64(time.Second))
	if cfg.StartupDelay != expected {
		t.Errorf("expected StartupDelay %v, got %v", expected, cfg.StartupDelay)
	}
	if cfg.FixedDelay != 0 {
		t.Errorf("expected FixedDelay 0, got %v", cfg.FixedDelay)
	}
}

func TestParseDelayInvalidStartupDelay(t *testing.T) {
	t.Setenv("RESPONSE_DELAY", "")
	t.Setenv("STARTUP_DELAY", "-1")
	_, err := parseDelay()
	if err == nil {
		t.Errorf("expected error for invalid startup delay, got nil")
	}
}
