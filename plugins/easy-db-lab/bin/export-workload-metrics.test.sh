#!/usr/bin/env bash
#
# Unit tests for bin/export-workload-metrics.
#
# The catalog must list only series that are live now. The script runs an instant query of the
# workload's selector against Mimir, which returns only series with a sample inside the lookback
# window, in the cluster's tenant.
#
# curl is stubbed: it records its arguments and prints a canned Prometheus API response. No
# cluster, no network.
#
# Run directly:  bin/export-workload-metrics.test.sh
# Or via gradle: ./gradlew testExportWorkloadMetrics

set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/export-workload-metrics"

tests_run=0
tests_failed=0
WORK=""
trap 'rm -rf "${WORK}"' EXIT

fail() {
  echo "FAIL: $1"
  tests_failed=$((tests_failed + 1))
}

# Sets up a cluster working directory with env.sh and a stub curl that prints $1 and exits $2.
setup() {
  [ -n "${WORK}" ] && rm -rf "${WORK}"
  WORK="$(mktemp -d)"
  mkdir -p "${WORK}/stubs"
  echo 'export CONTROL_HOST_PRIVATE=10.0.0.5' > "${WORK}/env.sh"
  echo '{"name":"lab","initConfig":{"tenant":"acme"}}' > "${WORK}/state.json"
  printf '%s' "$1" > "${WORK}/response.json"
  cat > "${WORK}/stubs/curl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "${WORK}/curl.args"
cat "${WORK}/response.json"
exit ${2:-0}
EOF
  chmod +x "${WORK}/stubs/curl"
}

run_script() {
  (cd "${WORK}" && PATH="${WORK}/stubs:${PATH}" "${SCRIPT}" "$@") > "${WORK}/out.txt" 2>&1
}

LIVE_RESPONSE='{"status":"success","data":{"resultType":"vector","result":[
  {"metric":{"__name__":"memcached_up","job":"memcached","instance":"memcached-abc"},"value":[1,"1"]},
  {"metric":{"__name__":"memcached_current_items","job":"memcached","instance":"memcached-abc"},"value":[1,"42"]}
]}}'

test_queries_only_series_live_in_the_window() {
  tests_run=$((tests_run + 1))
  setup "${LIVE_RESPONSE}"
  run_script memcached || { fail "script exited non-zero: $(cat "${WORK}/out.txt")"; return; }

  grep -Fqx 'http://10.0.0.5:9009/prometheus/api/v1/query' "${WORK}/curl.args" \
    || fail "expected an instant query at Mimir's /prometheus/api/v1/query, got: $(cat "${WORK}/curl.args")"
  grep -Fqx 'query={job="memcached"}' "${WORK}/curl.args" \
    || fail "expected an instant query of the workload's selector, got: $(cat "${WORK}/curl.args")"
  grep -Fqx 'X-Scope-OrgID: acme' "${WORK}/curl.args" \
    || fail "expected the cluster's tenant header, got: $(cat "${WORK}/curl.args")"
  if grep -q '/api/v1/series' "${WORK}/curl.args"; then
    fail "must not use /api/v1/series, which returns series outside the live window"
  fi
}

test_a_state_without_a_tenant_queries_the_default_tenant() {
  tests_run=$((tests_run + 1))
  setup "${LIVE_RESPONSE}"
  echo '{"name":"lab"}' > "${WORK}/state.json"
  run_script memcached || { fail "script exited non-zero: $(cat "${WORK}/out.txt")"; return; }

  grep -Fqx 'X-Scope-OrgID: default' "${WORK}/curl.args" \
    || fail "expected the default tenant header, got: $(cat "${WORK}/curl.args")"
}

test_writes_one_entry_per_metric_name_with_label_values() {
  tests_run=$((tests_run + 1))
  setup "${LIVE_RESPONSE}"
  run_script memcached || { fail "script exited non-zero: $(cat "${WORK}/out.txt")"; return; }

  local catalog="${WORK}/memcached/metrics-catalog.json"
  [ "$(jq -r '.workload' "${catalog}")" = "memcached" ] || fail "workload field is wrong"
  jq -e '.exported_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")' "${catalog}" > /dev/null \
    || fail "exported_at must be ISO-8601 UTC: $(jq -c '.exported_at' "${catalog}")"
  [ "$(jq -c '[.series[].name]' "${catalog}")" = '["memcached_current_items","memcached_up"]' ] \
    || fail "series names are wrong: $(jq -c '.series' "${catalog}")"
  [ "$(jq -c 'keys_unsorted' "${catalog}")" = '["workload","exported_at","common_labels","series"]' ] \
    || fail "expected keys workload, exported_at, common_labels, series: $(jq -c 'keys_unsorted' "${catalog}")"
  grep -q "Wrote 2 metrics" "${WORK}/out.txt" || fail "expected 'Wrote 2 metrics', got: $(cat "${WORK}/out.txt")"
}

# The same metric from three pods: one entry, the pods' label values merged, and none of the
# per-pod identity labels that make the file grow with the number of pods. ch_up has no shard, so
# shard is specific to ch_queries; job and host_name are on every series.
MULTI_POD_RESPONSE='{"status":"success","data":{"resultType":"vector","result":[
  {"metric":{"__name__":"ch_queries","job":"clickhouse","host_name":"db0","shard":"1","instance":"10.0.0.1:9363","k8s_pod_name":"ch-0","k8s_pod_uid":"u0","service_instance_id":"s0"},"value":[1,"1"]},
  {"metric":{"__name__":"ch_queries","job":"clickhouse","host_name":"db1","shard":"2","instance":"10.0.0.2:9363","k8s_pod_name":"ch-1","k8s_pod_uid":"u1","service_instance_id":"s1"},"value":[1,"1"]},
  {"metric":{"__name__":"ch_queries","job":"clickhouse","host_name":"db2","shard":"1","instance":"10.0.0.3:9363","k8s_pod_name":"ch-2","k8s_pod_uid":"u2","service_instance_id":"s2"},"value":[1,"1"]},
  {"metric":{"__name__":"ch_up","job":"clickhouse","host_name":"db0","instance":"10.0.0.1:9363","k8s_pod_name":"ch-0","k8s_pod_uid":"u0","service_instance_id":"s0"},"value":[1,"1"]}
]}}'

test_merges_pods_into_one_entry_per_metric_name() {
  tests_run=$((tests_run + 1))
  setup "${MULTI_POD_RESPONSE}"
  run_script clickhouse || { fail "script exited non-zero: $(cat "${WORK}/out.txt")"; return; }

  local catalog="${WORK}/clickhouse/metrics-catalog.json"
  [ "$(jq -c '.series' "${catalog}")" = '[{"name":"ch_queries","labels":{"shard":["1","2"]}},{"name":"ch_up","labels":{}}]' ] \
    || fail "expected one entry per name with merged values and no identity labels: $(jq -c '.series' "${catalog}")"
}

test_labels_on_every_series_are_listed_once_under_common_labels() {
  tests_run=$((tests_run + 1))
  setup "${MULTI_POD_RESPONSE}"
  run_script clickhouse || { fail "script exited non-zero: $(cat "${WORK}/out.txt")"; return; }

  local catalog="${WORK}/clickhouse/metrics-catalog.json"
  [ "$(jq -c '.common_labels' "${catalog}")" = '{"host_name":["db0","db1","db2"],"job":["clickhouse"]}' ] \
    || fail "keys on every series belong in common_labels: $(jq -c '.common_labels' "${catalog}")"
  if jq -e '[.series[].labels | has("job") or has("host_name")] | any' "${catalog}" > /dev/null; then
    fail "common keys must not repeat on entries: $(jq -c '.series' "${catalog}")"
  fi
  [ "$(jq -c '.series[] | select(.name == "ch_queries") | .labels.shard' "${catalog}")" = '["1","2"]' ] \
    || fail "a key on only some series stays on those entries: $(jq -c '.series' "${catalog}")"
}

test_drops_per_pod_identity_labels() {
  tests_run=$((tests_run + 1))
  setup "${MULTI_POD_RESPONSE}"
  run_script clickhouse || { fail "script exited non-zero: $(cat "${WORK}/out.txt")"; return; }

  local catalog="${WORK}/clickhouse/metrics-catalog.json"
  local key
  for key in k8s_pod_uid k8s_pod_name instance service_instance_id __name__; do
    if jq -e --arg k "${key}" '[.series[].labels, .common_labels | has($k)] | any' "${catalog}" > /dev/null; then
      fail "label ${key} must be dropped: $(jq -c '.series' "${catalog}")"
    fi
  done
}

# 25 distinct values each for an entry label (table, only on m) and a common label (host, on every
# series), in reverse order; only the first 20 in sorted order are kept for either.
many_values_response() {
  local i n entries=""
  for i in $(seq 25 -1 1); do
    n="$(printf '%02d' "${i}")"
    entries="${entries}${entries:+,}{\"metric\":{\"__name__\":\"m\",\"job\":\"k\",\"host\":\"h${n}\",\"table\":\"t${n}\"},\"value\":[1,\"1\"]}"
  done
  entries="${entries},{\"metric\":{\"__name__\":\"other\",\"job\":\"k\",\"host\":\"h01\"},\"value\":[1,\"1\"]}"
  printf '{"status":"success","data":{"resultType":"vector","result":[%s]}}' "${entries}"
}

test_caps_distinct_values_per_label_key() {
  tests_run=$((tests_run + 1))
  setup "$(many_values_response)"
  run_script k || { fail "script exited non-zero: $(cat "${WORK}/out.txt")"; return; }

  local catalog="${WORK}/k/metrics-catalog.json"
  local expected
  expected="$(for i in $(seq 1 20); do printf 't%02d\n' "${i}"; done | jq -R . | jq -sc .)"
  [ "$(jq -c '.series[0].labels.table' "${catalog}")" = "${expected}" ] \
    || fail "expected the first 20 sorted entry values, got: $(jq -c '.series[0].labels.table' "${catalog}")"
  expected="$(for i in $(seq 1 20); do printf 'h%02d\n' "${i}"; done | jq -R . | jq -sc .)"
  [ "$(jq -c '.common_labels.host' "${catalog}")" = "${expected}" ] \
    || fail "expected the first 20 sorted common values, got: $(jq -c '.common_labels.host' "${catalog}")"
}

# The same series in two different orders must produce identical series arrays: names, label
# keys and label values all sorted.
ORDERED_RESPONSE='{"status":"success","data":{"resultType":"vector","result":[
  {"metric":{"__name__":"a_metric","job":"k","zone":"b","role":"x"},"value":[1,"1"]},
  {"metric":{"__name__":"b_metric","job":"k"},"value":[1,"1"]},
  {"metric":{"__name__":"a_metric","role":"w","zone":"a","job":"k"},"value":[1,"1"]}
]}}'
SHUFFLED_RESPONSE='{"status":"success","data":{"resultType":"vector","result":[
  {"metric":{"__name__":"b_metric","job":"k"},"value":[1,"1"]},
  {"metric":{"role":"w","__name__":"a_metric","job":"k","zone":"a"},"value":[1,"1"]},
  {"metric":{"zone":"b","job":"k","__name__":"a_metric","role":"x"},"value":[1,"1"]}
]}}'

test_output_order_is_deterministic() {
  tests_run=$((tests_run + 1))
  local first second
  setup "${ORDERED_RESPONSE}"
  run_script k || { fail "script exited non-zero: $(cat "${WORK}/out.txt")"; return; }
  first="$(jq -c '{common_labels, series}' "${WORK}/k/metrics-catalog.json")"
  setup "${SHUFFLED_RESPONSE}"
  run_script k || { fail "script exited non-zero: $(cat "${WORK}/out.txt")"; return; }
  second="$(jq -c '{common_labels, series}' "${WORK}/k/metrics-catalog.json")"

  local expected='{"common_labels":{"job":["k"]},"series":[{"name":"a_metric","labels":{"role":["w","x"],"zone":["a","b"]}},{"name":"b_metric","labels":{}}]}'
  [ "${first}" = "${expected}" ] || fail "expected sorted names, keys and values, got: ${first}"
  [ "${first}" = "${second}" ] || fail "input order changed the output: ${first} vs ${second}"
}

test_no_live_series_fails_without_writing_a_catalog() {
  tests_run=$((tests_run + 1))
  setup '{"status":"success","data":{"resultType":"vector","result":[]}}'
  if run_script memcached; then
    fail "expected a non-zero exit when no series are live"
  fi
  [ ! -f "${WORK}/memcached/metrics-catalog.json" ] || fail "must not write an empty catalog"
}

test_error_status_fails() {
  tests_run=$((tests_run + 1))
  setup '{"status":"error","errorType":"bad_data","error":"boom"}'
  if run_script memcached; then
    fail "expected a non-zero exit on an error status"
  fi
  grep -q "status=error" "${WORK}/out.txt" || fail "expected the status in the error, got: $(cat "${WORK}/out.txt")"
}

test_workload_name_is_required() {
  tests_run=$((tests_run + 1))
  setup "${LIVE_RESPONSE}"
  if run_script; then
    fail "expected a non-zero exit with no workload name"
  fi
}

test_queries_only_series_live_in_the_window
test_a_state_without_a_tenant_queries_the_default_tenant
test_writes_one_entry_per_metric_name_with_label_values
test_merges_pods_into_one_entry_per_metric_name
test_labels_on_every_series_are_listed_once_under_common_labels
test_drops_per_pod_identity_labels
test_caps_distinct_values_per_label_key
test_output_order_is_deterministic
test_no_live_series_fails_without_writing_a_catalog
test_error_status_fails
test_workload_name_is_required

echo "${tests_run} tests, ${tests_failed} failed"
[ "${tests_failed}" -eq 0 ]
