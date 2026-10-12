# Compacts metric series into the metrics-catalog.json {common_labels, series} format.
#
# Input: an array of {name, labels} objects, one per series, where labels maps each label key to a
# single string value. Output:
#   common_labels: the label keys present on every series (sorted), each mapped to its sorted
#                  distinct values, at most $cap per key. Listed once instead of on every entry.
#   series:        one {name, labels} entry per distinct metric name, sorted by name, whose labels
#                  holds only the remaining (metric-specific) keys, in the same key → values form.
#
# Per-pod identity labels are dropped first: they carry nothing for dashboards or METRICS.md and
# would make the catalog grow with the number of pods.
#
# Shared by bin/export-workload-metrics and any offline conversion of a full per-series export, so
# the two cannot diverge:
#   jq -L bin 'include "metrics-catalog"; ... | compact_catalog(20)'

def identity_labels: ["__name__", "instance", "k8s_pod_name", "k8s_pod_uid", "service_instance_id"];

# [{key, value}] -> {key: [sorted distinct values, at most $cap]}
def label_values($cap):
  group_by(.key)
  | map({key: .[0].key, value: ([.[].value] | unique | .[:$cap])})
  | from_entries;

# Keys present on every series of the input.
def common_keys:
  map(.labels | keys)
  | if length == 0 then [] else reduce .[1:][] as $k (.[0]; . - (. - $k)) end;

def compact_catalog($cap):
  map(.labels |= with_entries(select(.key | IN(identity_labels[]) | not))) as $series
  | ($series | common_keys) as $common
  | {
      common_labels: ([$series[].labels | to_entries[] | select(.key | IN($common[]))] | label_values($cap)),
      series: (
        $series
        | group_by(.name)
        | map({
            name: .[0].name,
            labels: ([.[].labels | to_entries[] | select(.key | IN($common[]) | not)] | label_values($cap))
          })
      )
    };
