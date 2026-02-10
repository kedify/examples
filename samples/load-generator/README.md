# Load Generator

`load-generator` is a small Go application meant for testing vertical scaling with
Kedify `PodResourceAutoscaler`.

It lets you drive CPU and memory usage through REST endpoints with deterministic
profiles.

## Endpoints

- `GET /healthz`
- `GET /status`
- `GET /profiles`
- `POST /set`
- `POST /profile/{idle|low|medium|high|spike}`
- `POST /reset`
- `POST /schedule`
- `POST /schedule/stop`
- `GET /metrics`

### Example payload for `POST /set`

```json
{
  "cpuMillicores": 750,
  "memoryMiB": 384
}
```

Optional query parameter: `rampSeconds` (default: `0`, immediate apply).

Example:

```bash
curl -s -X POST "localhost:8080/set?rampSeconds=30" \
  -H 'Content-Type: application/json' \
  -d '{"cpuMillicores":750,"memoryMiB":384}' | jq
```

### Example payload for `POST /profile/{name}`

The profile name comes from the URL path. No request body is needed.
Optional query parameter: `rampSeconds` (default: `0`, immediate apply).

Example:

```bash
curl -s -X POST "localhost:8080/profile/high?rampSeconds=30" | jq
```

### Example payload for `POST /schedule`

Each step selects a built-in profile and keeps it active for `durationSeconds`.
When `loop` is `true`, the schedule restarts from the first step indefinitely.
When `loop` is `false`, the schedule runs once and stops after the last step.

```json
{
  "loop": false,
  "steps": [
    {
      "profile": "low",
      "durationSeconds": 30
    },
    {
      "profile": "high",
      "durationSeconds": 45
    },
    {
      "profile": "spike",
      "durationSeconds": 20
    }
  ]
}
```

Use `POST /schedule/stop` to stop an active schedule.
Calling `POST /set`, `POST /profile/{name}`, or `POST /reset` also stops the active schedule.
`POST /reset` also supports optional `rampSeconds` query parameter (default: `0`).

### Configure schedule from env var

You can start the app with a predefined schedule using `SCHEDULE_JSON`.
The value uses the same schema as `POST /schedule`.

```bash
SCHEDULE_JSON='{"loop":true,"steps":[{"profile":"low","durationSeconds":300},{"profile":"high","durationSeconds":300}]}' go run .
```

## How load is generated

- CPU load uses duty-cycle workers (`100ms` windows) and targets millicores.
- Memory load allocates 1MiB chunks and periodically touches memory pages to keep
  the working set active.
- Profile and `/set`/`/reset` changes apply immediately by default, or ramp when
  `rampSeconds` is provided.
- Scheduled mode applies a sequence of profiles by time windows and can run once
  or loop forever.

## Built-in profiles

- `idle`: baseline from env (`BASELINE_CPU_MILLICORES`, `BASELINE_MEMORY_MIB`)
- `low`: `250m`, `128Mi`
- `medium`: `500m`, `256Mi`
- `high`: `900m`, `512Mi`
- `spike`: `1400m`, `768Mi`

## Run locally

```bash
go run .
```

Try:

```bash
curl -s localhost:8080/status | jq
curl -s -X POST localhost:8080/profile/high | jq
curl -s -X POST "localhost:8080/set?rampSeconds=30" -H 'Content-Type: application/json' -d '{"cpuMillicores":750,"memoryMiB":384}' | jq
curl -s -X POST "localhost:8080/profile/spike?rampSeconds=30" | jq
curl -s -X POST localhost:8080/schedule -H 'Content-Type: application/json' -d '{"loop":false,"steps":[{"profile":"low","durationSeconds":20},{"profile":"high","durationSeconds":20},{"profile":"spike","durationSeconds":15}]}' | jq
curl -s -X POST localhost:8080/schedule -H 'Content-Type: application/json' -d '{"loop":true,"steps":[{"profile":"medium","durationSeconds":25},{"profile":"high","durationSeconds":25}]}' | jq
curl -s localhost:8080/status | jq
curl -s -X POST localhost:8080/schedule/stop | jq
curl -s -X POST "localhost:8080/reset?rampSeconds=30" | jq
```

## Build image

```bash
make docker-build
make docker-push
```

## Deploy sample in Kubernetes

```bash
kubectl apply -f config/manifests.yaml
kubectl apply -f config/pra.yaml
```

## Generate many apps + PRAs

Use the generator script to create `N` load-generator app stacks
(Deployment + Service + PodResourceAutoscaler), each with a slightly different
schedule.

Each schedule step is guaranteed to be at least 5 minutes (`300s`).
Generated schedules alternate between `medium/high` and `idle` profiles to make
PRA repeatedly scale up and down during the run.

```bash
# Generate 10 apps into the default output file:
./scripts/generate-fleet.sh 10

# Generate 25 apps into a custom file:
./scripts/generate-fleet.sh 25 ./config/generated-25.yaml
```

Useful options via environment variables:

- `LOOP_MODE=mixed|once|loop` (default: `loop`)
- `MIN_STEP_SECONDS=300` (values lower than `300` are clamped to `300`)
- `NAMESPACE=my-namespace`

Generated Deployments include `SCHEDULE_JSON` env var, so each app boots with
its own schedule automatically.

Drive load:

```bash
(kubectl port-forward svc/load-generator 8080:8080 &> /dev/null)& pf_pid=$!
(sleep 10m && kill ${pf_pid})&

curl -s -X POST localhost:8080/profile/high | jq
curl -s -X POST localhost:8080/profile/spike | jq
curl -s -X POST localhost:8080/reset | jq
```

Watch resource updates:

```bash
watch "kubectl get pod -l app=load-generator -ojsonpath=\"{.items[*].spec.containers[?(.name=='load-generator')].resources}\" | jq"
```
