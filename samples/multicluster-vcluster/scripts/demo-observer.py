#!/usr/bin/env python3
"""Read-only observer for native iTerm2 panes and the optional tmux layout.

Each member runs inside one persistent `vcluster connect -- ...` child. Only
sanitized summaries are cached locally for the host pane; no Secrets or raw
workload manifests are written. Query errors never become zero replica counts.
"""

import json
import datetime
import os
import pathlib
import re
import shutil
import signal
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
NAMESPACE = os.getenv("DEMO_NAMESPACE", "demo-scaling")
INSTALL_NAMESPACE = os.getenv("NAMESPACE", "keda")
INTERVAL = max(1, float(os.getenv("DEMO_REFRESH_SECONDS", "3")))
CACHE = pathlib.Path(os.getenv("DEMO_OBSERVER_DIR", str(ROOT / "state/observer")))
COLOR = "NO_COLOR" not in os.environ and (sys.stdout.isatty() or os.getenv("FORCE_COLOR") == "1")
STOP = False
CPU_WARMUP_SECONDS = 150
CPU_STARTUP_MESSAGES = {
    "metric 0 (Resource): get resource metric cpu: no metrics returned from resource metrics API",
    "metric 0 (Resource): no metrics for ready target pods",
}


def stop(_signum, _frame):
    global STOP
    STOP = True


signal.signal(signal.SIGINT, stop)
signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGHUP, stop)


def paint(value, code):
    return f"\033[{code}m{value}\033[0m" if COLOR else str(value)


def run(command, input_text=None):
    try:
        result = subprocess.run(command, input=input_text, text=True, capture_output=True, timeout=12)
        return result.stdout.strip() if result.returncode == 0 else None
    except (OSError, subprocess.TimeoutExpired):
        return None


def kube_get(resources, namespace=NAMESPACE, kubeconfig=None, selector=None):
    command = ["kubectl"]
    if kubeconfig:
        command += ["--kubeconfig", kubeconfig]
    command += ["--request-timeout=8s", "--namespace", namespace, "get", resources, "--output=json"]
    if selector:
        command += ["--selector", selector]
    raw = run(command)
    try:
        return json.loads(raw) if raw is not None else None
    except json.JSONDecodeError:
        return None


def condition(resource, name):
    for entry in (resource or {}).get("status", {}).get("conditions", []):
        if entry.get("type") == name:
            return entry.get("status", "Unknown")
    return "Unknown"


def timestamp(value):
    try:
        return datetime.datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
    except (AttributeError, TypeError, ValueError):
        return None


def duration_seconds(value):
    """Parse the Go duration returned by metrics.k8s.io, without rounding it."""
    if not isinstance(value, str):
        return None
    parts = re.findall(r"(\d+(?:\.\d+)?)(ns|us|µs|ms|s|m|h)", value)
    if not parts or "".join(number + unit for number, unit in parts) != value:
        return None
    units = {"ns": 1e-9, "us": 1e-6, "µs": 1e-6, "ms": .001, "s": 1, "m": 60, "h": 3600}
    return sum(float(number) * units[unit] for number, unit in parts)


def worker_pods(items):
    return [item for item in items if item.get("kind") == "Pod"
            and item.get("metadata", {}).get("labels", {}).get("app") == "worker"
            and not item.get("metadata", {}).get("deletionTimestamp")]


def cpu_startup_warmup(autoscaler, pods, now=None):
    """Only soften the two observed startup gaps, bounded by actual Pod age.

    Auth, connectivity, other metrics failures and old-Pod failures retain their
    actual KPA reason. No Kubernetes condition or replica count is changed.
    """
    now = time.time() if now is None else now
    active = next((entry for entry in (autoscaler or {}).get("status", {}).get("conditions", [])
                   if entry.get("type") == "ScalingActive"), {})
    if (active.get("status") != "False" or active.get("reason") != "FailedGetMetric"
            or active.get("message") not in CPU_STARTUP_MESSAGES):
        return False
    started = timestamp(active.get("lastTransitionTime"))
    if started is None or not 0 <= now - started <= CPU_WARMUP_SECONDS:
        return False
    return any((created := timestamp(pod.get("metadata", {}).get("creationTimestamp"))) is not None
               and 0 <= now - created <= CPU_WARMUP_SECONDS for pod in pods)


def cpu_metrics_usable(items, metrics, now=None):
    """Preflight rejects samples that top accepts but KPA sets aside at startup."""
    now = time.time() if now is None else now
    worker = next((item for item in items if item.get("kind") == "Deployment"
                   and item.get("metadata", {}).get("name") == "worker"), {})
    autoscaler = next((item for item in items if item.get("kind") == "KedifyPodAutoscaler"
                       and item.get("metadata", {}).get("name") == "worker-autoscaler"), {})
    desired = worker.get("spec", {}).get("replicas")
    status = worker.get("status", {})
    pods = worker_pods(items)
    if (not desired or len(pods) != desired or metrics is None
            or condition(autoscaler, "ScalingActive") != "True"
            or status.get("observedGeneration") != worker.get("metadata", {}).get("generation")
            or any(status.get(field) != desired for field in ("replicas", "readyReplicas", "updatedReplicas"))):
        return False
    samples = {item.get("metadata", {}).get("name"): item for item in metrics.get("items", [])}
    for pod in pods:
        sample = samples.get(pod["metadata"]["name"], {})
        sampled = timestamp(sample.get("timestamp"))
        window = duration_seconds(sample.get("window"))
        ready = next((entry for entry in pod.get("status", {}).get("conditions", [])
                      if entry.get("type") == "Ready"), {})
        ready_at = timestamp(ready.get("lastTransitionTime"))
        start = timestamp(pod.get("status", {}).get("startTime"))
        cpu = [container.get("usage", {}).get("cpu") for container in sample.get("containers", [])]
        if (pod.get("status", {}).get("phase") != "Running" or ready.get("status") != "True"
                or sampled is None or window is None or window <= 0 or ready_at is None or start is None
                or not cpu or any(value is None for value in cpu) or not 0 <= now - sampled <= CPU_WARMUP_SECONDS):
            return False
        # Live KPA uses a five-minute CPU initialization period. During it, the
        # whole measurement window must start after this Pod became Ready.
        if now < start + 300 and sampled < ready_at + window:
            return False
    return True


def wait_for_cpu_metrics():
    deadline = time.monotonic() + float(os.getenv("DEMO_WAIT_TIMEOUT_SECONDS", "300"))
    print("Waiting for CPU samples usable by KPA (including Pod readiness windows)...", flush=True)
    while not STOP and time.monotonic() < deadline:
        inventory = kube_get("deployments,kedifypodautoscalers.autoscaling.kedify.io,pods")
        raw = run(["kubectl", "--request-timeout=8s", "get", "--raw",
                   f"/apis/metrics.k8s.io/v1beta1/namespaces/{NAMESPACE}/pods"])
        try:
            metrics = json.loads(raw) if raw is not None else None
        except json.JSONDecodeError:
            metrics = None
        if inventory is not None and cpu_metrics_usable(inventory.get("items", []), metrics):
            print("CPU samples are usable; KPA ScalingActive=True", flush=True)
            return 0
        time.sleep(3)
    print("CPU metric preflight did not become ready; inspect kubectl -n " + NAMESPACE
          + " describe kpa worker-autoscaler", file=sys.stderr)
    return 1


def summarize(items, member):
    grouped = {}
    for item in items:
        grouped.setdefault(item.get("kind"), []).append(item)
    worker = next((item for item in grouped.get("Deployment", []) if item["metadata"]["name"] == "worker"), None)
    autoscaler = next((item for item in grouped.get("KedifyPodAutoscaler", []) if item["metadata"]["name"] == "worker-autoscaler"), None)
    resource = next((item for item in grouped.get("ScaledJob" if member == 2 else "ScaledObject", []) if item["metadata"]["name"] == "worker"), None)
    jobs = [item for item in grouped.get("Job", []) if item.get("metadata", {}).get("labels", {}).get("scaledjob.keda.sh/name") == "worker"]
    pods = [item for item in grouped.get("Pod", []) if item.get("metadata", {}).get("labels", {}).get("app") == "worker" or item.get("metadata", {}).get("labels", {}).get("scaledjob.keda.sh/name") == "worker"]
    # Jobs' pod templates do not necessarily carry the ScaledJob label.
    job_uids = {item.get("metadata", {}).get("uid") for item in jobs}
    for pod in grouped.get("Pod", []):
        if any(owner.get("uid") in job_uids for owner in pod.get("metadata", {}).get("ownerReferences", [])) and pod not in pods:
            pods.append(pod)
    state = {
        "member": member, "updated": time.time(), "connection": "CONNECTED",
        "registrationUID": os.getenv("DEMO_REGISTRATION_UID"),
        "resource": resource.get("kind") if resource else None,
        "ready": condition(resource, "Ready"), "active": condition(resource, "Active"),
        "paused": condition(resource, "Paused"),
        "desired": worker.get("spec", {}).get("replicas") if worker else None,
        "replicas": worker.get("status", {}).get("replicas", 0) if worker else None,
        "available": worker.get("status", {}).get("readyReplicas", 0) if worker else None,
        "kpaDesired": autoscaler.get("status", {}).get("desiredReplicas") if autoscaler else None,
        # HPA-compatible status omits currentReplicas when it is zero. Only
        # interpret that omission after the controller has observed a generation.
        "kpaCurrent": autoscaler.get("status", {}).get("currentReplicas", 0) if autoscaler and autoscaler.get("status", {}).get("observedGeneration") is not None else None,
        "ableToScale": condition(autoscaler, "AbleToScale"),
        "scalingActive": condition(autoscaler, "ScalingActive"),
        "kpaReason": next((entry.get("reason") for entry in (autoscaler or {}).get("status", {}).get("conditions", []) if entry.get("type") == "ScalingActive"), None),
        "pods": len(pods),
        "readyPods": sum(condition(pod, "Ready") == "True" for pod in pods),
        "jobsActive": sum(job.get("status", {}).get("active", 0) for job in jobs),
        "jobsSucceeded": sum(job.get("status", {}).get("succeeded", 0) for job in jobs),
        "jobsFailed": sum(job.get("status", {}).get("failed", 0) for job in jobs),
        "cpuLoad": None,
        "cpuWarmup": cpu_startup_warmup(autoscaler, worker_pods(items)) if member == 1 else False,
    }
    if worker:
        state["cpuLoad"] = worker.get("metadata", {}).get("annotations", {}).get("demo.kedify.io/cpu-load")
        # Existing fixtures remain readable until they are prepared once again.
        for container in worker.get("spec", {}).get("template", {}).get("spec", {}).get("containers", []):
            for env in container.get("env", []):
                if env.get("name") == "CPU_LOAD" and state["cpuLoad"] is None:
                    state["cpuLoad"] = env.get("value")
    return state


def queue_length(member):
    queue = os.getenv("VC2_QUEUE", "demo-vc2-scaledjob") if member == 2 else os.getenv("VC3_QUEUE", "demo-vc3-scaledobject")
    try:
        password = (ROOT / "state/redis-password").read_text().strip()
    except OSError:
        return None
    # Credentials go through stdin, never argv, cache files, or terminal output.
    raw = run([
        "kubectl", "--kubeconfig", os.getenv("REDIS_KUBECONFIG", str(ROOT / ".kube/redis.yaml")),
        "--request-timeout=8s", "--namespace", "redis", "exec", "-i", "deployment/redis", "--",
        "sh", "-c", 'IFS= read -r REDISCLI_AUTH; export REDISCLI_AUTH; exec redis-cli --no-auth-warning LLEN "$1"', "sh", queue,
    ], password + "\n")
    return int(raw) if raw and raw.isdigit() else None


def cache_state(state):
    CACHE.mkdir(parents=True, exist_ok=True, mode=0o700)
    target = CACHE / f"vc-{state['member']}.json"
    temporary = target.with_suffix(".tmp")
    temporary.write_text(json.dumps(state))
    temporary.chmod(0o600)
    temporary.replace(target)


def cached_member(member, now=None):
    try:
        value = json.loads((CACHE / f"vc-{member}.json").read_text())
    except (OSError, ValueError):
        return {"connection": "WAITING"}
    if value.get("member") != member:
        return {"connection": "UNKNOWN"}
    if (now or time.time()) - value.get("updated", 0) > max(15, INTERVAL * 4):
        return {"connection": "STALE", "registrationUID": value.get("registrationUID")}
    return value


def display(lines):
    width = shutil.get_terminal_size((110, 30)).columns
    if sys.stdout.isatty():
        sys.stdout.write("\033[H\033[2J")
    for line in lines:
        # Keep the heading color, but never wrap long text into another pane row.
        plain = re.sub(r"\x1b\[[0-9;]*m", "", line)
        if len(plain) >= width:
            first_color = re.match(r"\x1b\[[0-9;]*m", line)
            line = (first_color.group(0) if first_color else "") + plain[:max(20, width - 1)] + ("\033[0m" if first_color else "")
        print(line)
    sys.stdout.flush()


def value(state, key):
    item = state.get(key)
    return "?" if item is None else str(item)


def connection_color(connection):
    return "1;32" if connection == "CONNECTED" else "1;31" if connection in ("UNAVAILABLE", "STALE") else "1;33"


def condition_value(item, false_color="33"):
    return paint(item, "1;32" if item == "True" else false_color if item == "False" else "1;33")


def count_value(state, key, positive_color="1;36", zero_color="32"):
    item = state.get(key)
    return paint(value(state, key), "1;33" if item is None else positive_color if item > 0 else zero_color)


def replica_pair(state, desired_key, observed_key):
    desired, observed = state.get(desired_key), state.get(observed_key)
    observed_color = "1;33" if observed is None or desired != observed else "1;32"
    return f"{paint(value(state, desired_key), '1;36' if desired is not None else '1;33')} / {paint(value(state, observed_key), observed_color)}"


def member_lines(state):
    member = state["member"]
    name = {1: "CPU Deployment", 2: "Redis ScaledJob", 3: "New tenant / Redis Deployment"}[member]
    clock = time.strftime("%H:%M:%S", time.localtime(state["updated"]))
    lines = [paint(f"vc-{member}  |  {name}", {1: "1;36", 2: "1;34", 3: "1;35"}[member]), f"Updated {clock}  |  {paint(state['connection'], connection_color(state['connection']))}", ""]
    if state["connection"] != "CONNECTED":
        return lines + [paint("Waiting for a ready registration / API", "33"), paint("No replica counts inferred from errors", "90")]
    if not state.get("resource"):
        return lines + [paint("Connected; demo resource not created yet", "33"), "Control: make demo-workload" if member == 3 else "Control: make demo-baseline"]
    lines += [paint(f"{state['resource']}: worker", "1"), f"Ready={condition_value(state['ready'], '1;31')} Active={condition_value(state['active'])}", f"Paused={condition_value(state['paused'], '32') if state['paused'] != 'True' else paint('True', '1;33')}", ""]
    if member == 2:
        lines += [f"Queue items       {count_value(state, 'queue', '1;33')}", f"Jobs active       {count_value(state, 'jobsActive')}", f"Jobs succeeded    {count_value(state, 'jobsSucceeded', '1;32')}", f"Jobs failed       {count_value(state, 'jobsFailed', '1;31')}", "", paint("One item per Job; max 3 concurrent", "90")]
    else:
        lines += [f"{paint('Deployment desired / ready', '1')}  {replica_pair(state, 'desired', 'available')}", f"KPA desired / current       {replica_pair(state, 'kpaDesired', 'kpaCurrent')}", f"AbleToScale={condition_value(state['ableToScale'], '1;31')}", f"ScalingActive={condition_value(state['scalingActive'])}"]
        if state.get("cpuWarmup"):
            lines += [paint("Collecting CPU metrics… (startup)", "1;33")]
        elif state.get("kpaReason"):
            lines += [paint(f"KPA reason: {state['kpaReason']}", "90" if state['scalingActive'] == 'True' else "33")]
        if member == 1:
            lines += ["", f"CPU load requested {paint(value(state, 'cpuLoad'), '1;33' if state.get('cpuLoad') == 'true' else '32' if state.get('cpuLoad') == 'false' else '1;33')}", f"CPU usage         {paint(state.get('cpuUsage') or '?', '1;36' if state.get('cpuUsage') else '1;33')}", paint("100m request; utilization target 50%", "90"), paint("Expected: 1 -> 3 -> 1", "1;36")]
        else:
            lines += ["", f"Queue items       {count_value(state, 'queue', '1;33')}", paint("3 items per replica; 9 items -> 3", "90"), paint("Expected: 0 -> 3 -> 0", "1;35")]
    hint = {1: "Load toggles keep the worker Pod", 2: "Completed Job Pods may remain", 3: "Rollouts can temporarily add Pods"}[member]
    lines += ["", f"Pods ready / total  {paint(state['readyPods'], '1;36')} / {paint(state['pods'], '1;36')}", paint(hint, "90")]
    return lines


def observe_member(member):
    failures = 0
    while not STOP:
        inventory = kube_get("scaledobjects.keda.sh,scaledjobs.keda.sh,kedifypodautoscalers.autoscaling.kedify.io,deployments,jobs,pods")
        if inventory is None:
            state = {"member": member, "updated": time.time(), "connection": "UNAVAILABLE"}
            failures += 1
        else:
            state = summarize(inventory.get("items", []), member)
            failures = 0
            if member == 1:
                top = run(["kubectl", "--request-timeout=8s", "--namespace", NAMESPACE, "top", "pods", "--no-headers"])
                if top:
                    state["cpuUsage"] = ", ".join(row.split()[1] for row in top.splitlines() if len(row.split()) >= 3)
            else:
                state["queue"] = queue_length(member)
        cache_state(state)
        display(member_lines(state))
        if failures >= 3:
            return 1  # The outer command reconnects after a member/API lifecycle change.
        time.sleep(INTERVAL)
    return 0


def observe_host():
    main = os.getenv("MAIN_KUBECONFIG", str(ROOT / ".kube/main.yaml"))
    while not STOP:
        registrations = kube_get("clusterregistrations.multicluster.kedify.io", INSTALL_NAMESPACE, main, "multicluster.kedify.io/managed-by=vcluster-discovery")
        deployments = kube_get("deployments", INSTALL_NAMESPACE, main)
        components = []
        for deployment in (deployments or {}).get("items", []):
            name = deployment["metadata"]["name"]
            if name in ("kedify-agent", "keda-operator", "kpa"):
                ready = deployment.get('status', {}).get('readyReplicas', 0)
                desired = deployment.get('spec', {}).get('replicas', 1)
                components.append(f"{name}: {paint(f'{ready}/{desired}', '1;32' if ready == desired else '1;33')} ready")
        lines = [paint("HOST  |  shared autoscaling control plane / dedicated mode", "1;35"), f"Updated {time.strftime('%H:%M:%S')}  |  " + ("  ".join(components) if deployments is not None else "API unavailable"), ""]
        lines += [paint(f"{'MEMBER':<8} {'REG READY':<10} {'OBSERVATION':<13} {'DES/READY':<12} {'JOBS A/S/F':<13} {'QUEUE':<7} REASON", "1")]
        known = {item.get("spec", {}).get("clusterName"): item for item in (registrations or {}).get("items", [])}
        for member in (1, 2, 3):
            registration = known.get(f"vc-{member}.vcluster-{member}")
            state = cached_member(member)
            registered = condition(registration, "Ready") if registration else ("Absent" if registrations is not None else "Unknown")
            ready_condition = next((item for item in (registration or {}).get("status", {}).get("conditions", []) if item.get("type") == "Ready"), {})
            if not registration:
                state = {"connection": "WAITING" if registrations is not None else "UNKNOWN"}
            elif state.get("registrationUID") != registration.get("metadata", {}).get("uid"):
                state = {"connection": "UPDATING"}
            deployment = f"{value(state, 'desired')}/{value(state, 'available')}" if member != 2 else "n/a"
            jobs = "/".join(value(state, field) for field in ("jobsActive", "jobsSucceeded", "jobsFailed")) if member == 2 else "n/a"
            deployment_color = "90" if member == 2 else "1;33" if state.get('desired') is None or state.get('available') is None or state.get('desired') != state.get('available') else "1;32"
            jobs_color = "90" if member != 2 else "1;31" if state.get('jobsFailed', 0) else "1;36" if state.get('jobsActive', 0) else "1;32" if state.get('jobsSucceeded') is not None else "1;33"
            queue = "n/a" if member == 1 else value(state, 'queue')
            queue_color = "90" if member == 1 else "1;33" if state.get('queue') is None or state.get('queue', 0) > 0 else "32"
            lines.append(" ".join([
                paint(f"vc-{member:<5}", {1: "1;36", 2: "1;34", 3: "1;35"}[member]),
                paint(f"{registered:<10}", "1;32" if registered == "True" else "1;33"),
                paint(f"{state['connection']:<13}", connection_color(state['connection'])),
                paint(f"{deployment:<12}", deployment_color),
                paint(f"{jobs:<13}", jobs_color),
                paint(f"{queue:<7}", queue_color),
                paint(ready_condition.get('reason', '-'), "90" if registered == "True" else "33"),
            ]))
        lines += ["", paint("Native resources stay in each member. Registration Ready validates access; workload observations show reconciliation.", "90"), "Control: demo-cpu-on/off | demo-jobs | third-vcluster | demo-workload | demo-queue-on/off"]
        display(lines)
        time.sleep(INTERVAL)


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "host"
    if mode == "host":
        observe_host()
    elif mode == "member":
        sys.exit(observe_member(int(sys.argv[2])))
    elif mode == "waiting":
        waiting = {"member": int(sys.argv[2]), "updated": time.time(), "connection": "WAITING"}
        cache_state(waiting)
        display(member_lines(waiting))
    elif mode == "cpu-ready":
        sys.exit(wait_for_cpu_metrics())
    else:
        sys.exit("Expected host, member INDEX, waiting INDEX, or cpu-ready")
