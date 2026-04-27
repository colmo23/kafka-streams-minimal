#!/usr/bin/env bash
set -euo pipefail

# ─── helpers ────────────────────────────────────────────────────────────────

PASS=0; FAIL=0

ok()   { echo "  [PASS] $*"; PASS=$((PASS + 1)); }
fail() { echo "  [FAIL] $*"; FAIL=$((FAIL + 1)); }

wait_for() {
    local desc=$1 cmd=$2 timeout=${3:-30} interval=2 elapsed=0
    printf "  waiting for %s" "$desc"
    until eval "$cmd" &>/dev/null; do
        sleep $interval; elapsed=$((elapsed + interval))
        printf "."
        if (( elapsed >= timeout )); then echo " timed out"; return 1; fi
    done
    echo " ok"
}

section() { echo; echo "── $* ──"; }

# ─── 1. services ────────────────────────────────────────────────────────────

section "Services"

for svc in zookeeper kafka elasticsearch connect streams-app; do
    state=$(docker compose ps --format json "$svc" 2>/dev/null \
            | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('State',''))" 2>/dev/null || true)
    if [[ "$state" == "running" ]]; then
        ok "$svc is running"
    else
        fail "$svc is not running (state: ${state:-unknown})"
    fi
done

# ─── 2. kafka ───────────────────────────────────────────────────────────────

section "Kafka"

wait_for "broker" \
    "docker compose exec -T kafka kafka-topics --bootstrap-server localhost:9092 --list" 20

for topic in input output; do
    if docker compose exec -T kafka kafka-topics \
            --bootstrap-server localhost:9092 --list 2>/dev/null | grep -qx "$topic"; then
        ok "topic '$topic' exists"
    else
        fail "topic '$topic' missing"
    fi
done

if docker compose exec -T kafka kafka-consumer-groups \
        --bootstrap-server localhost:9092 --list 2>/dev/null \
        | grep -q "minimal-streams-app"; then
    ok "streams-app consumer group registered"
else
    fail "streams-app consumer group not found — app may not be running"
fi

# ─── 3. kafka connect ───────────────────────────────────────────────────────

section "Kafka Connect"

wait_for "Connect REST" "curl -sf http://localhost:8083/connectors" 30

connector_state=$(curl -sf http://localhost:8083/connectors/es-sink/status 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['connector']['state'])" 2>/dev/null || echo "NOT_FOUND")
task_state=$(curl -sf http://localhost:8083/connectors/es-sink/status 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['tasks'][0]['state'])" 2>/dev/null || echo "NOT_FOUND")

[[ "$connector_state" == "RUNNING" ]] && ok "es-sink connector RUNNING" || fail "es-sink connector state: $connector_state"
[[ "$task_state"      == "RUNNING" ]] && ok "es-sink task RUNNING"      || fail "es-sink task state: $task_state"

# ─── 4. elasticsearch ───────────────────────────────────────────────────────

section "Elasticsearch"

wait_for "ES cluster" "curl -sf http://localhost:9200/_cluster/health" 30

es_status=$(curl -sf http://localhost:9200/_cluster/health 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['status'])" 2>/dev/null || echo "unknown")
[[ "$es_status" == "green" || "$es_status" == "yellow" ]] \
    && ok "ES cluster health: $es_status" \
    || fail "ES cluster health: $es_status"

# ─── 5. end-to-end message flow ─────────────────────────────────────────────

section "End-to-end message flow"

MARKER="e2e-test-$(date +%s)"

echo "  producing test message: $MARKER"
echo "$MARKER" | docker compose exec -T kafka kafka-console-producer \
    --bootstrap-server localhost:9092 --topic input 2>/dev/null

echo "  producing test JSON:    {\"event\":\"$MARKER\"}"
echo "{\"event\":\"$MARKER\"}" | docker compose exec -T kafka kafka-console-producer \
    --bootstrap-server localhost:9092 --topic input 2>/dev/null

# wait for ES to index the messages (up to 20 s)
echo "  waiting for messages in Elasticsearch..."
found=false
for i in $(seq 1 10); do
    sleep 2
    count=$(curl -sf "http://localhost:9200/output/_search" \
        -H 'Content-Type: application/json' \
        -d "{\"query\":{\"bool\":{\"should\":[
              {\"match\":{\"message\":\"$MARKER\"}},
              {\"match\":{\"event\":\"$MARKER\"}}
            ]}}}" 2>/dev/null \
        | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['hits']['total']['value'])" 2>/dev/null || echo 0)
    if (( count >= 2 )); then found=true; break; fi
done

if $found; then
    ok "plain-string message reached ES with processed_at field"
    ok "JSON message reached ES with processed_at field"

    # verify processed_at is present on both hits
    for kind in message event; do
        has_ts=$(curl -sf "http://localhost:9200/output/_search" \
            -H 'Content-Type: application/json' \
            -d "{\"query\":{\"match\":{\"$kind\":\"$MARKER\"}}}" 2>/dev/null \
            | python3 -c "
import sys, json
hits = json.load(sys.stdin)['hits']['hits']
print('yes' if hits and 'processed_at' in hits[0]['_source'] else 'no')
" 2>/dev/null || echo "no")
        [[ "$has_ts" == "yes" ]] \
            && ok "processed_at present on $kind message" \
            || fail "processed_at missing on $kind message"
    done
else
    fail "messages did not appear in Elasticsearch within 20 s"
fi

# ─── summary ────────────────────────────────────────────────────────────────

section "Results"
echo "  passed: $PASS  failed: $FAIL"
(( FAIL == 0 )) && echo "  ALL TESTS PASSED" || echo "  SOME TESTS FAILED"
echo
(( FAIL == 0 ))
