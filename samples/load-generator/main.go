package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"math"
	"net/http"
	"os"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

const (
	defaultPort              = 8080
	defaultBaselineCPUMilli  = 100
	defaultBaselineMemoryMiB = 96
	defaultTouchInterval     = 2 * time.Second
	controlLoopInterval      = 500 * time.Millisecond
	memoryChunkSizeBytes     = 1 << 20
	memoryPageTouchStep      = 4096
	maxAcceptedRampSeconds   = 1800
	maxAcceptedScheduleStep  = 86400
	maxAcceptedMemoryMiB     = 8192
	maxAcceptedCPUMillicores = 16000
)

type loadTarget struct {
	CPUMillicores int `json:"cpuMillicores"`
	MemoryMiB     int `json:"memoryMiB"`
}

type setRequest struct {
	CPUMillicores *int `json:"cpuMillicores,omitempty"`
	MemoryMiB     *int `json:"memoryMiB,omitempty"`
}

type scheduleStepRequest struct {
	Profile         string `json:"profile"`
	DurationSeconds int    `json:"durationSeconds"`
}

type scheduleRequest struct {
	Steps []scheduleStepRequest `json:"steps"`
	Loop  bool                  `json:"loop,omitempty"`
}

type statusResponse struct {
	Baseline      loadTarget        `json:"baseline"`
	Desired       loadTarget        `json:"desired"`
	Current       loadTarget        `json:"current"`
	ActiveProfile string            `json:"activeProfile"`
	Schedule      scheduleStatus    `json:"schedule"`
	CPU           cpuStatusResponse `json:"cpu"`
	Memory        memoryStatus      `json:"memory"`
	UptimeSeconds int64             `json:"uptimeSeconds"`
}

type scheduleStatus struct {
	Active           bool   `json:"active"`
	Loop             bool   `json:"loop,omitempty"`
	TotalSteps       int    `json:"totalSteps,omitempty"`
	CurrentStep      int    `json:"currentStep,omitempty"`
	CurrentProfile   string `json:"currentProfile,omitempty"`
	Iteration        int    `json:"iteration,omitempty"`
	RemainingSeconds int64  `json:"remainingSeconds,omitempty"`
}

type cpuStatusResponse struct {
	Workers            int `json:"workers"`
	TargetMillicores   int `json:"targetMillicores"`
	MaxMillicores      int `json:"maxMillicores"`
	RequestedMillicore int `json:"requestedMillicores"`
}

type memoryStatus struct {
	TargetMiB    int `json:"targetMiB"`
	AllocatedMiB int `json:"allocatedMiB"`
}

type apiError struct {
	Error string `json:"error"`
}

type scheduledStep struct {
	Profile string
	Target  loadTarget
	HoldFor time.Duration
}

type scheduleRuntime struct {
	Token          uint64
	Loop           bool
	TotalSteps     int
	CurrentStep    int
	CurrentProfile string
	Iteration      int
	StepEndsAt     time.Time
}

type loadApp struct {
	mu sync.RWMutex

	baseline loadTarget
	desired  loadTarget
	current  loadTarget

	activeProfile string
	schedule      *scheduleRuntime

	profiles map[string]loadTarget

	cpu *cpuController
	mem *memoryController

	scheduleMu     sync.Mutex
	scheduleCancel context.CancelFunc
	scheduleToken  uint64
	rampMu         sync.Mutex
	rampCancel     context.CancelFunc
	rampToken      uint64

	requestMu     sync.Mutex
	requestCounts map[string]uint64

	startedAt time.Time

	stopOnce sync.Once
}

// newLoadApp creates the application state and initializes load controllers.
func newLoadApp() *loadApp {
	baseline := loadTarget{
		CPUMillicores: parseEnvInt("BASELINE_CPU_MILLICORES", defaultBaselineCPUMilli),
		MemoryMiB:     parseEnvInt("BASELINE_MEMORY_MIB", defaultBaselineMemoryMiB),
	}
	baseline = sanitizeTarget(baseline)

	workerCount := parseEnvInt("CPU_WORKERS", runtime.GOMAXPROCS(0))
	if workerCount < 1 {
		workerCount = 1
	}

	app := &loadApp{
		baseline:      baseline,
		desired:       baseline,
		current:       baseline,
		activeProfile: "idle",
		profiles:      defaultProfiles(baseline),
		cpu:           newCPUController(workerCount),
		mem:           newMemoryController(defaultTouchInterval),
		requestCounts: make(map[string]uint64),
		startedAt:     time.Now(),
	}

	app.cpu.SetTargetMillicores(baseline.CPUMillicores)
	app.mem.SetTargetMiB(baseline.MemoryMiB)

	return app
}

// Close stops background activity and releases controller resources.
func (a *loadApp) Close() {
	a.stopOnce.Do(func() {
		a.stopSchedule()
		a.stopRamp()
		a.cpu.Close()
		a.mem.Close()
	})
}

// setTarget applies the desired load target immediately.
func (a *loadApp) setTarget(target loadTarget, profile string) {
	target = sanitizeTarget(target)
	a.stopRamp()

	a.mu.Lock()
	a.desired = target
	a.activeProfile = profile
	a.current = target
	a.mu.Unlock()

	a.cpu.SetTargetMillicores(target.CPUMillicores)
	a.mem.SetTargetMiB(target.MemoryMiB)
}

// rampToTarget applies a target gradually over the requested ramp duration.
func (a *loadApp) rampToTarget(target loadTarget, profile string, rampSeconds int) {
	target = sanitizeTarget(target)
	rampSeconds = sanitizeRamp(rampSeconds)
	if rampSeconds == 0 {
		a.setTarget(target, profile)
		return
	}

	a.rampMu.Lock()
	previousCancel := a.rampCancel
	a.rampToken++
	token := a.rampToken
	ctx, cancel := context.WithCancel(context.Background())
	a.rampCancel = cancel
	a.rampMu.Unlock()

	if previousCancel != nil {
		previousCancel()
	}

	a.mu.Lock()
	fromCPU := float64(a.current.CPUMillicores)
	fromMem := float64(a.current.MemoryMiB)
	a.desired = target
	a.activeProfile = profile
	a.mu.Unlock()

	go a.runRamp(ctx, token, fromCPU, fromMem, target, time.Duration(rampSeconds)*time.Second)
}

// stopRamp cancels any active ramp transition.
func (a *loadApp) stopRamp() {
	a.rampMu.Lock()
	cancel := a.rampCancel
	a.rampCancel = nil
	a.rampMu.Unlock()

	if cancel != nil {
		cancel()
	}
}

// runRamp interpolates from current values to target values until done or canceled.
func (a *loadApp) runRamp(ctx context.Context, token uint64, fromCPU float64, fromMem float64, target loadTarget, duration time.Duration) {
	defer a.finalizeRamp(token)

	started := time.Now()
	ticker := time.NewTicker(controlLoopInterval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			if !a.isRampTokenActive(token) {
				return
			}

			progress := float64(time.Since(started)) / float64(duration)
			if progress >= 1 {
				a.mu.Lock()
				a.current = target
				a.mu.Unlock()
				a.cpu.SetTargetMillicores(target.CPUMillicores)
				a.mem.SetTargetMiB(target.MemoryMiB)
				return
			}

			currentCPU := int(math.Round(interpolate(fromCPU, float64(target.CPUMillicores), progress)))
			currentMem := int(math.Round(interpolate(fromMem, float64(target.MemoryMiB), progress)))
			current := sanitizeTarget(loadTarget{CPUMillicores: currentCPU, MemoryMiB: currentMem})

			a.mu.Lock()
			a.current = current
			a.mu.Unlock()
			a.cpu.SetTargetMillicores(current.CPUMillicores)
			a.mem.SetTargetMiB(current.MemoryMiB)
		}
	}
}

// isRampTokenActive reports whether the token still identifies the current ramp.
func (a *loadApp) isRampTokenActive(token uint64) bool {
	a.rampMu.Lock()
	active := a.rampToken == token && a.rampCancel != nil
	a.rampMu.Unlock()
	return active
}

// finalizeRamp clears ramp state if the token still matches the active run.
func (a *loadApp) finalizeRamp(token uint64) {
	a.rampMu.Lock()
	if a.rampToken == token {
		a.rampCancel = nil
	}
	a.rampMu.Unlock()
}

// startSchedule starts a new profile schedule and cancels any existing one.
func (a *loadApp) startSchedule(steps []scheduledStep, loop bool) {
	if len(steps) == 0 {
		return
	}

	a.scheduleMu.Lock()
	previousCancel := a.scheduleCancel
	a.scheduleToken++
	token := a.scheduleToken
	ctx, cancel := context.WithCancel(context.Background())
	a.scheduleCancel = cancel
	a.scheduleMu.Unlock()

	if previousCancel != nil {
		previousCancel()
	}

	now := time.Now()
	a.mu.Lock()
	a.schedule = &scheduleRuntime{
		Token:          token,
		Loop:           loop,
		TotalSteps:     len(steps),
		CurrentStep:    1,
		CurrentProfile: steps[0].Profile,
		Iteration:      1,
		StepEndsAt:     now.Add(steps[0].HoldFor),
	}
	a.mu.Unlock()

	go a.runSchedule(ctx, token, steps, loop)
}

// stopSchedule cancels the currently running schedule.
func (a *loadApp) stopSchedule() {
	a.scheduleMu.Lock()
	cancel := a.scheduleCancel
	a.scheduleCancel = nil
	a.scheduleMu.Unlock()

	if cancel != nil {
		cancel()
	}

	a.mu.Lock()
	a.schedule = nil
	a.mu.Unlock()
	a.stopRamp()
}

// runSchedule applies schedule steps until completion or cancellation.
func (a *loadApp) runSchedule(ctx context.Context, token uint64, steps []scheduledStep, loop bool) {
	defer a.finalizeSchedule(token)

	stepIdx := 0
	iteration := 1

	for {
		select {
		case <-ctx.Done():
			return
		default:
		}

		step := steps[stepIdx]
		stepEndsAt := time.Now().Add(step.HoldFor)
		if !a.updateScheduleState(token, loop, len(steps), stepIdx, iteration, step.Profile, stepEndsAt) {
			return
		}

		a.setTarget(step.Target, step.Profile)

		timer := time.NewTimer(step.HoldFor)
		select {
		case <-ctx.Done():
			timer.Stop()
			return
		case <-timer.C:
		}

		stepIdx++
		if stepIdx >= len(steps) {
			if !loop {
				return
			}
			stepIdx = 0
			iteration++
		}
	}
}

// updateScheduleState updates observable schedule progress for the active token.
func (a *loadApp) updateScheduleState(token uint64, loop bool, totalSteps int, stepIdx int, iteration int, profile string, stepEndsAt time.Time) bool {
	a.mu.Lock()
	defer a.mu.Unlock()

	if a.schedule == nil || a.schedule.Token != token {
		return false
	}

	a.schedule.Loop = loop
	a.schedule.TotalSteps = totalSteps
	a.schedule.CurrentStep = stepIdx + 1
	a.schedule.CurrentProfile = profile
	a.schedule.Iteration = iteration
	a.schedule.StepEndsAt = stepEndsAt
	return true
}

// finalizeSchedule clears schedule state if the token still matches the active run.
func (a *loadApp) finalizeSchedule(token uint64) {
	a.scheduleMu.Lock()
	if a.scheduleToken == token {
		a.scheduleCancel = nil
	}
	a.scheduleMu.Unlock()

	a.mu.Lock()
	if a.schedule != nil && a.schedule.Token == token {
		a.schedule = nil
	}
	a.mu.Unlock()
}

// getStatus returns a consistent snapshot of current load and scheduler state.
func (a *loadApp) getStatus() statusResponse {
	a.mu.RLock()
	baseline := a.baseline
	desired := a.desired
	current := a.current
	activeProfile := a.activeProfile
	var scheduleSnapshot scheduleRuntime
	hasSchedule := false
	if a.schedule != nil {
		scheduleSnapshot = *a.schedule
		hasSchedule = true
	}
	a.mu.RUnlock()

	scheduledStatus := scheduleStatus{}
	if hasSchedule {
		remaining := time.Until(scheduleSnapshot.StepEndsAt)
		if remaining < 0 {
			remaining = 0
		}
		scheduledStatus = scheduleStatus{
			Active:           true,
			Loop:             scheduleSnapshot.Loop,
			TotalSteps:       scheduleSnapshot.TotalSteps,
			CurrentStep:      scheduleSnapshot.CurrentStep,
			CurrentProfile:   scheduleSnapshot.CurrentProfile,
			Iteration:        scheduleSnapshot.Iteration,
			RemainingSeconds: int64(remaining.Seconds()),
		}
	}

	return statusResponse{
		Baseline:      baseline,
		Desired:       desired,
		Current:       current,
		ActiveProfile: activeProfile,
		Schedule:      scheduledStatus,
		CPU: cpuStatusResponse{
			Workers:            a.cpu.WorkerCount(),
			TargetMillicores:   a.cpu.TargetMillicores(),
			MaxMillicores:      a.cpu.MaxMillicores(),
			RequestedMillicore: current.CPUMillicores,
		},
		Memory: memoryStatus{
			TargetMiB:    current.MemoryMiB,
			AllocatedMiB: a.mem.AllocatedMiB(),
		},
		UptimeSeconds: int64(time.Since(a.startedAt).Seconds()),
	}
}

// routes constructs the HTTP router for the load generator API.
func (a *loadApp) routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", a.instrument("/healthz", a.handleHealthz))
	mux.HandleFunc("GET /status", a.instrument("/status", a.handleStatus))
	mux.HandleFunc("GET /profiles", a.instrument("/profiles", a.handleProfiles))
	mux.HandleFunc("POST /set", a.instrument("/set", a.handleSet))
	mux.HandleFunc("POST /profile/{name}", a.instrument("/profile", a.handleProfile))
	mux.HandleFunc("POST /reset", a.instrument("/reset", a.handleReset))
	mux.HandleFunc("POST /schedule", a.instrument("/schedule", a.handleSchedule))
	mux.HandleFunc("POST /schedule/stop", a.instrument("/schedule/stop", a.handleScheduleStop))
	mux.HandleFunc("GET /metrics", a.instrument("/metrics", a.handleMetrics))
	return mux
}

// instrument wraps handlers and increments per-endpoint request counters.
func (a *loadApp) instrument(endpoint string, next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		a.incrementRequest(endpoint)
		next(w, r)
	}
}

// incrementRequest increments the total request count for an endpoint.
func (a *loadApp) incrementRequest(endpoint string) {
	a.requestMu.Lock()
	defer a.requestMu.Unlock()
	a.requestCounts[endpoint]++
}

// snapshotRequestCounts returns a copy of endpoint request counters.
func (a *loadApp) snapshotRequestCounts() map[string]uint64 {
	a.requestMu.Lock()
	defer a.requestMu.Unlock()

	copyMap := make(map[string]uint64, len(a.requestCounts))
	for key, value := range a.requestCounts {
		copyMap[key] = value
	}
	return copyMap
}

// handleHealthz reports process health.
func (a *loadApp) handleHealthz(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

// handleStatus returns the current application status.
func (a *loadApp) handleStatus(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, a.getStatus())
}

// handleProfiles returns the built-in load profiles.
func (a *loadApp) handleProfiles(w http.ResponseWriter, _ *http.Request) {
	a.mu.RLock()
	profiles := make(map[string]loadTarget, len(a.profiles))
	for name, profile := range a.profiles {
		profiles[name] = profile
	}
	a.mu.RUnlock()

	writeJSON(w, http.StatusOK, map[string]map[string]loadTarget{"profiles": profiles})
}

// buildScheduledSteps validates a schedule request and resolves profile targets.
func (a *loadApp) buildScheduledSteps(req scheduleRequest) ([]scheduledStep, error) {
	if len(req.Steps) == 0 {
		return nil, fmt.Errorf("steps must contain at least one item")
	}

	a.mu.RLock()
	profiles := make(map[string]loadTarget, len(a.profiles))
	for name, profile := range a.profiles {
		profiles[name] = profile
	}
	a.mu.RUnlock()

	steps := make([]scheduledStep, 0, len(req.Steps))
	for i, step := range req.Steps {
		stepNum := i + 1
		profileName := strings.ToLower(strings.TrimSpace(step.Profile))
		if profileName == "" {
			return nil, fmt.Errorf("step %d profile must be set", stepNum)
		}

		target, found := profiles[profileName]
		if !found {
			return nil, fmt.Errorf("step %d profile %q is unknown", stepNum, profileName)
		}

		if step.DurationSeconds <= 0 {
			return nil, fmt.Errorf("step %d durationSeconds must be > 0", stepNum)
		}
		if step.DurationSeconds > maxAcceptedScheduleStep {
			return nil, fmt.Errorf("step %d durationSeconds must be <= %d", stepNum, maxAcceptedScheduleStep)
		}

		steps = append(steps, scheduledStep{
			Profile: profileName,
			Target:  target,
			HoldFor: time.Duration(step.DurationSeconds) * time.Second,
		})
	}

	return steps, nil
}

// applyStartupScheduleFromEnv starts a schedule from SCHEDULE_JSON when present.
func (a *loadApp) applyStartupScheduleFromEnv() error {
	raw := strings.TrimSpace(os.Getenv("SCHEDULE_JSON"))
	if raw == "" {
		return nil
	}

	var req scheduleRequest
	if err := decodeSingleJSON(strings.NewReader(raw), &req); err != nil {
		return fmt.Errorf("invalid SCHEDULE_JSON: %w", err)
	}

	steps, err := a.buildScheduledSteps(req)
	if err != nil {
		return fmt.Errorf("invalid SCHEDULE_JSON: %w", err)
	}

	a.startSchedule(steps, req.Loop)
	log.Printf("startup schedule applied from SCHEDULE_JSON: steps=%d loop=%t", len(steps), req.Loop)
	return nil
}

// handleSet applies a custom load target from the request body.
func (a *loadApp) handleSet(w http.ResponseWriter, r *http.Request) {
	var req setRequest
	if err := decodeJSON(r, &req); err != nil {
		writeJSON(w, http.StatusBadRequest, apiError{Error: err.Error()})
		return
	}

	a.mu.RLock()
	target := a.desired
	a.mu.RUnlock()

	if req.CPUMillicores == nil && req.MemoryMiB == nil {
		writeJSON(w, http.StatusBadRequest, apiError{Error: "at least one of cpuMillicores or memoryMiB must be set"})
		return
	}
	if req.CPUMillicores != nil {
		target.CPUMillicores = *req.CPUMillicores
	}
	if req.MemoryMiB != nil {
		target.MemoryMiB = *req.MemoryMiB
	}

	rampSeconds, err := parseRampSecondsQuery(r)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, apiError{Error: err.Error()})
		return
	}

	a.stopSchedule()
	a.rampToTarget(target, "custom", rampSeconds)
	writeJSON(w, http.StatusOK, a.getStatus())
}

// handleProfile applies one of the named built-in profiles.
func (a *loadApp) handleProfile(w http.ResponseWriter, r *http.Request) {
	name := strings.ToLower(strings.TrimSpace(r.PathValue("name")))

	a.mu.RLock()
	profile, found := a.profiles[name]
	a.mu.RUnlock()
	if !found {
		writeJSON(w, http.StatusNotFound, apiError{Error: "unknown profile"})
		return
	}

	rampSeconds, err := parseRampSecondsQuery(r)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, apiError{Error: err.Error()})
		return
	}

	a.stopSchedule()
	a.rampToTarget(profile, name, rampSeconds)
	writeJSON(w, http.StatusOK, a.getStatus())
}

// handleReset restores the baseline profile.
func (a *loadApp) handleReset(w http.ResponseWriter, r *http.Request) {
	rampSeconds, err := parseRampSecondsQuery(r)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, apiError{Error: err.Error()})
		return
	}

	a.stopSchedule()
	a.rampToTarget(a.baseline, "idle", rampSeconds)
	writeJSON(w, http.StatusOK, a.getStatus())
}

// handleSchedule validates and starts a schedule of profile steps.
func (a *loadApp) handleSchedule(w http.ResponseWriter, r *http.Request) {
	var req scheduleRequest
	if err := decodeJSON(r, &req); err != nil {
		writeJSON(w, http.StatusBadRequest, apiError{Error: err.Error()})
		return
	}

	steps, err := a.buildScheduledSteps(req)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, apiError{Error: err.Error()})
		return
	}

	a.startSchedule(steps, req.Loop)
	writeJSON(w, http.StatusOK, a.getStatus())
}

// handleScheduleStop stops any active schedule.
func (a *loadApp) handleScheduleStop(w http.ResponseWriter, _ *http.Request) {
	a.stopSchedule()
	writeJSON(w, http.StatusOK, a.getStatus())
}

// handleMetrics renders application metrics in Prometheus exposition format.
func (a *loadApp) handleMetrics(w http.ResponseWriter, _ *http.Request) {
	status := a.getStatus()
	counts := a.snapshotRequestCounts()

	keys := make([]string, 0, len(counts))
	for key := range counts {
		keys = append(keys, key)
	}
	sort.Strings(keys)

	w.Header().Set("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
	fmt.Fprintln(w, "# HELP load_generator_target_cpu_millicores Desired CPU target in millicores")
	fmt.Fprintln(w, "# TYPE load_generator_target_cpu_millicores gauge")
	fmt.Fprintf(w, "load_generator_target_cpu_millicores %d\n", status.Desired.CPUMillicores)

	fmt.Fprintln(w, "# HELP load_generator_current_cpu_millicores Current CPU value in millicores")
	fmt.Fprintln(w, "# TYPE load_generator_current_cpu_millicores gauge")
	fmt.Fprintf(w, "load_generator_current_cpu_millicores %d\n", status.Current.CPUMillicores)

	fmt.Fprintln(w, "# HELP load_generator_target_memory_mebibytes Desired memory target in MiB")
	fmt.Fprintln(w, "# TYPE load_generator_target_memory_mebibytes gauge")
	fmt.Fprintf(w, "load_generator_target_memory_mebibytes %d\n", status.Desired.MemoryMiB)

	fmt.Fprintln(w, "# HELP load_generator_current_memory_mebibytes Current memory value in MiB")
	fmt.Fprintln(w, "# TYPE load_generator_current_memory_mebibytes gauge")
	fmt.Fprintf(w, "load_generator_current_memory_mebibytes %d\n", status.Current.MemoryMiB)

	fmt.Fprintln(w, "# HELP load_generator_memory_allocated_mebibytes Currently allocated memory chunks in MiB")
	fmt.Fprintln(w, "# TYPE load_generator_memory_allocated_mebibytes gauge")
	fmt.Fprintf(w, "load_generator_memory_allocated_mebibytes %d\n", status.Memory.AllocatedMiB)

	fmt.Fprintln(w, "# HELP load_generator_requests_total Total HTTP requests by endpoint")
	fmt.Fprintln(w, "# TYPE load_generator_requests_total counter")
	for _, key := range keys {
		fmt.Fprintf(w, "load_generator_requests_total{endpoint=%q} %d\n", key, counts[key])
	}
}

// writeJSON writes a JSON response with the given HTTP status code.
func writeJSON(w http.ResponseWriter, statusCode int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)
	if err := json.NewEncoder(w).Encode(payload); err != nil {
		log.Printf("failed to encode JSON response: %v", err)
	}
}

// decodeSingleJSON decodes exactly one JSON object and rejects unknown fields.
func decodeSingleJSON(reader io.Reader, into any) error {
	decoder := json.NewDecoder(reader)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(into); err != nil {
		return err
	}
	if err := decoder.Decode(&struct{}{}); err == nil {
		return fmt.Errorf("only one JSON object is allowed")
	} else if err != io.EOF {
		return err
	}
	return nil
}

// decodeJSON decodes a single JSON object and rejects unknown fields.
func decodeJSON(r *http.Request, into any) error {
	if err := decodeSingleJSON(r.Body, into); err != nil {
		return fmt.Errorf("invalid json body: %w", err)
	}
	return nil
}

// parseRampSecondsQuery parses optional rampSeconds query parameter.
func parseRampSecondsQuery(r *http.Request) (int, error) {
	queryValue := strings.TrimSpace(r.URL.Query().Get("rampSeconds"))
	if queryValue == "" {
		return 0, nil
	}

	value, err := strconv.Atoi(queryValue)
	if err != nil || value < 0 {
		return 0, fmt.Errorf("query parameter rampSeconds must be >= 0")
	}
	return value, nil
}

// interpolate linearly interpolates between two values for progress in [0,1].
func interpolate(from, to, progress float64) float64 {
	if progress <= 0 {
		return from
	}
	if progress >= 1 {
		return to
	}
	return from + (to-from)*progress
}

// sanitizeTarget clamps CPU and memory values to accepted bounds.
func sanitizeTarget(target loadTarget) loadTarget {
	if target.CPUMillicores < 0 {
		target.CPUMillicores = 0
	}
	if target.MemoryMiB < 0 {
		target.MemoryMiB = 0
	}
	if target.CPUMillicores > maxAcceptedCPUMillicores {
		target.CPUMillicores = maxAcceptedCPUMillicores
	}
	if target.MemoryMiB > maxAcceptedMemoryMiB {
		target.MemoryMiB = maxAcceptedMemoryMiB
	}
	return target
}

// sanitizeRamp clamps ramp seconds to accepted bounds.
func sanitizeRamp(rampSeconds int) int {
	if rampSeconds < 0 {
		return 0
	}
	if rampSeconds > maxAcceptedRampSeconds {
		return maxAcceptedRampSeconds
	}
	return rampSeconds
}

// parseEnvInt parses an integer environment variable with a fallback value.
func parseEnvInt(envKey string, defaultValue int) int {
	value := strings.TrimSpace(os.Getenv(envKey))
	if value == "" {
		return defaultValue
	}
	parsed, err := strconv.Atoi(value)
	if err != nil {
		log.Printf("invalid %s=%q, falling back to %d", envKey, value, defaultValue)
		return defaultValue
	}
	return parsed
}

// defaultProfiles returns the predefined load profiles based on the baseline.
func defaultProfiles(baseline loadTarget) map[string]loadTarget {
	profiles := map[string]loadTarget{
		"idle": {
			CPUMillicores: baseline.CPUMillicores,
			MemoryMiB:     baseline.MemoryMiB,
		},
		"low": {
			CPUMillicores: 250,
			MemoryMiB:     128,
		},
		"medium": {
			CPUMillicores: 500,
			MemoryMiB:     256,
		},
		"high": {
			CPUMillicores: 900,
			MemoryMiB:     512,
		},
		"spike": {
			CPUMillicores: 1400,
			MemoryMiB:     768,
		},
	}
	for key, profile := range profiles {
		profiles[key] = sanitizeTarget(profile)
	}
	return profiles
}

type cpuController struct {
	workers []*cpuWorker
	target  atomic.Int64
}

// newCPUController creates a CPU controller with the requested worker count.
func newCPUController(workerCount int) *cpuController {
	if workerCount < 1 {
		workerCount = 1
	}

	controller := &cpuController{workers: make([]*cpuWorker, 0, workerCount)}
	for i := 0; i < workerCount; i++ {
		controller.workers = append(controller.workers, newCPUWorker())
	}
	return controller
}

// SetTargetMillicores distributes the requested CPU target across workers.
func (c *cpuController) SetTargetMillicores(millicores int) {
	if millicores < 0 {
		millicores = 0
	}

	maxMillicores := c.MaxMillicores()
	if millicores > maxMillicores {
		millicores = maxMillicores
	}

	c.target.Store(int64(millicores))

	targetCores := float64(millicores) / 1000.0
	fullWorkers := int(math.Floor(targetCores))
	partialDuty := targetCores - float64(fullWorkers)

	for idx, worker := range c.workers {
		switch {
		case idx < fullWorkers:
			worker.SetDuty(1)
		case idx == fullWorkers && partialDuty > 0:
			worker.SetDuty(partialDuty)
		default:
			worker.SetDuty(0)
		}
	}
}

// TargetMillicores returns the controller's current CPU target.
func (c *cpuController) TargetMillicores() int {
	return int(c.target.Load())
}

// MaxMillicores returns the maximum CPU target supported by current workers.
func (c *cpuController) MaxMillicores() int {
	return len(c.workers) * 1000
}

// WorkerCount returns the number of CPU workers.
func (c *cpuController) WorkerCount() int {
	return len(c.workers)
}

// Close stops all CPU workers.
func (c *cpuController) Close() {
	for _, worker := range c.workers {
		worker.Close()
	}
}

type cpuWorker struct {
	dutyBits atomic.Uint64
	stopCh   chan struct{}
	stopOnce sync.Once
}

// newCPUWorker creates and starts a single CPU worker.
func newCPUWorker() *cpuWorker {
	worker := &cpuWorker{stopCh: make(chan struct{})}
	worker.SetDuty(0)
	go worker.loop()
	return worker
}

// SetDuty sets the worker duty cycle between 0 and 1.
func (w *cpuWorker) SetDuty(duty float64) {
	if duty < 0 {
		duty = 0
	}
	if duty > 1 {
		duty = 1
	}
	w.dutyBits.Store(math.Float64bits(duty))
}

// Close stops the worker loop.
func (w *cpuWorker) Close() {
	w.stopOnce.Do(func() {
		close(w.stopCh)
	})
}

// loop runs CPU-bound work according to the current duty cycle.
func (w *cpuWorker) loop() {
	const window = 100 * time.Millisecond

	scratch := 1.0
	for {
		select {
		case <-w.stopCh:
			return
		default:
		}

		duty := math.Float64frombits(w.dutyBits.Load())
		if duty <= 0 {
			time.Sleep(window)
			continue
		}

		busyFor := time.Duration(float64(window) * duty)
		busyUntil := time.Now().Add(busyFor)
		for time.Now().Before(busyUntil) {
			scratch += math.Sqrt(scratch)
			if scratch > 1e12 {
				scratch = 1
			}
		}

		restFor := window - busyFor
		if restFor > 0 {
			time.Sleep(restFor)
		}
	}
}

type memoryController struct {
	mu         sync.Mutex
	chunks     [][]byte
	touchEvery time.Duration
	stopCh     chan struct{}
	stopOnce   sync.Once
	targetMiB  atomic.Int64
}

// newMemoryController creates a memory controller and starts the touch loop.
func newMemoryController(touchEvery time.Duration) *memoryController {
	if touchEvery <= 0 {
		touchEvery = defaultTouchInterval
	}
	controller := &memoryController{
		touchEvery: touchEvery,
		stopCh:     make(chan struct{}),
	}
	go controller.touchLoop()
	return controller
}

// SetTargetMiB adjusts allocated memory chunks to the requested target.
func (m *memoryController) SetTargetMiB(targetMiB int) {
	if targetMiB < 0 {
		targetMiB = 0
	}
	if targetMiB > maxAcceptedMemoryMiB {
		targetMiB = maxAcceptedMemoryMiB
	}

	m.targetMiB.Store(int64(targetMiB))

	m.mu.Lock()
	currentMiB := len(m.chunks)
	if targetMiB == currentMiB {
		m.mu.Unlock()
		return
	}

	if targetMiB > currentMiB {
		for i := currentMiB; i < targetMiB; i++ {
			chunk := make([]byte, memoryChunkSizeBytes)
			touchChunkPages(chunk)
			m.chunks = append(m.chunks, chunk)
		}
		m.mu.Unlock()
		return
	}

	for i := targetMiB; i < currentMiB; i++ {
		m.chunks[i] = nil
	}
	m.chunks = m.chunks[:targetMiB]
	m.mu.Unlock()

	runtime.GC()
}

// TargetMiB returns the configured memory target.
func (m *memoryController) TargetMiB() int {
	return int(m.targetMiB.Load())
}

// AllocatedMiB returns the current number of allocated memory chunks.
func (m *memoryController) AllocatedMiB() int {
	m.mu.Lock()
	defer m.mu.Unlock()
	return len(m.chunks)
}

// Close stops the memory touch loop.
func (m *memoryController) Close() {
	m.stopOnce.Do(func() {
		close(m.stopCh)
	})
}

// touchLoop periodically touches all allocated memory pages.
func (m *memoryController) touchLoop() {
	ticker := time.NewTicker(m.touchEvery)
	defer ticker.Stop()

	for {
		select {
		case <-m.stopCh:
			return
		case <-ticker.C:
			m.mu.Lock()
			for _, chunk := range m.chunks {
				touchChunkPages(chunk)
			}
			m.mu.Unlock()
		}
	}
}

// touchChunkPages touches one byte per page to keep memory resident.
func touchChunkPages(chunk []byte) {
	if len(chunk) == 0 {
		return
	}
	for i := 0; i < len(chunk); i += memoryPageTouchStep {
		chunk[i]++
	}
	chunk[len(chunk)-1]++
}

// main configures and starts the HTTP server.
func main() {
	app := newLoadApp()
	defer app.Close()

	if err := app.applyStartupScheduleFromEnv(); err != nil {
		log.Fatalf("failed to initialize schedule from env: %v", err)
	}

	port := parseEnvInt("PORT", defaultPort)
	if port <= 0 {
		port = defaultPort
	}

	srv := &http.Server{
		Addr:              fmt.Sprintf(":%d", port),
		Handler:           app.routes(),
		ReadHeaderTimeout: 5 * time.Second,
	}

	log.Printf("load-generator started on :%d", port)
	log.Printf("available profiles: idle, low, medium, high, spike")
	log.Printf("baseline load: cpu=%dm memory=%dMi", app.baseline.CPUMillicores, app.baseline.MemoryMiB)

	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatalf("server failed: %v", err)
	}
}
