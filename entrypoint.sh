#!/bin/bash

set -e

DEFAULT_RESERVED_CODE_CACHE_SIZE="240M"
DEFAULT_MAX_METASPACE_SIZE="400M"
DEFAULT_STACK_SIZE="1M"
DEFAULT_JVM_THREAD_COUNT=200

parse_memory_size_to_bytes() {
  local size="$1"
  local value
  local unit
  local multiplier

  if [[ ! "$size" =~ ^([0-9]+)([bBkKmMgGtT]?)$ ]]; then
    echo "Unable to parse JVM memory size: '$size'" >&2
    exit 2
  fi

  value="${BASH_REMATCH[1]}"
  unit="${BASH_REMATCH[2]}"

  case "$unit" in
    ""|B|b) multiplier=1 ;;
    K|k) multiplier=1024 ;;
    M|m) multiplier=$((1024 * 1024)) ;;
    G|g) multiplier=$((1024 * 1024 * 1024)) ;;
    T|t) multiplier=$((1024 * 1024 * 1024 * 1024)) ;;
    *)
      echo "Unable to parse JVM memory size: '$size'" >&2
      exit 2
      ;;
  esac

  echo $((value * multiplier))
}

format_memory_size() {
  local bytes="$1"
  local kib=$((1024))
  local mib=$((1024 * 1024))
  local gib=$((1024 * 1024 * 1024))
  local tib=$((1024 * 1024 * 1024 * 1024))

  if (( bytes % tib == 0 )); then
    echo "$((bytes / tib))T"
  elif (( bytes % gib == 0 )); then
    echo "$((bytes / gib))G"
  elif (( bytes % mib == 0 )); then
    echo "$((bytes / mib))M"
  else
    echo "$((bytes / kib))K"
  fi
}

find_last_jvm_option_value() {
  local prefix="$1"
  local options="$2"
  local -a option_array
  local option
  local value=""

  # Split on whitespace only. Using an array (instead of an unquoted `for`)
  # avoids pathname expansion of tokens such as `-agentlib:jdwp=...address=*:8000`.
  read -ra option_array <<< "$options"
  for option in "${option_array[@]}"; do
    if [[ "$option" == "$prefix"* ]]; then
      value="${option#"$prefix"}"
    fi
  done

  printf "%s" "$value"
}

has_jvm_option() {
  local prefix="$1"
  local options="$2"
  local -a option_array
  local option

  # Split on whitespace only, without pathname expansion (see find_last_jvm_option_value).
  read -ra option_array <<< "$options"
  for option in "${option_array[@]}"; do
    if [[ "$option" == "$prefix"* ]]; then
      return 0
    fi
  done

  return 1
}

has_max_heap() {
  has_jvm_option "-Xmx" "$1"
}

has_stack_size() {
  has_jvm_option "-Xss" "$1"
}

require_non_negative_integer() {
  local name="$1"
  local value="$2"

  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    echo "$name must be a non-negative integer: '$value'" >&2
    exit 2
  fi
}

add_default_memory_area_opts() {
  local totalMaxMemoryMb="$1"
  local jvm_opts="$2"
  local default_jvm_opts="$3"

  if [[ $totalMaxMemoryMb != 0 && $jvm_opts != *"-XX:MaxDirectMemorySize="* ]]; then
    local jvm_direct_memory=$((50 + totalMaxMemoryMb/512 * 25))
    default_jvm_opts+=" -XX:MaxDirectMemorySize=${jvm_direct_memory}M"
  fi

  if [[ $jvm_opts != *"-XX:MaxMetaspaceSize="* ]]; then
    default_jvm_opts+=" -XX:MaxMetaspaceSize=${DEFAULT_MAX_METASPACE_SIZE}"
  fi

  if [[ $jvm_opts != *"-XX:ReservedCodeCacheSize="* ]]; then
    default_jvm_opts+=" -XX:ReservedCodeCacheSize=${DEFAULT_RESERVED_CODE_CACHE_SIZE}"
  fi

  printf "%s" "$default_jvm_opts"
}

read_memory_limit() {
  if test -f /sys/fs/cgroup/memory/memory.limit_in_bytes; then
    cat /sys/fs/cgroup/memory/memory.limit_in_bytes
  else
    cat /sys/fs/cgroup/memory.max
  fi
}

exec_launcher() {
  exec /app/tbe-launcher-*/bin/tbe-launcher
}

calculate_memory_opts() {
  local totalMaxMemoryMb="$1"
  local jvm_opts="$2"
  local default_jvm_opts="$3"
  local jvm_head_room="$4"
  local jvm_thread_count="$5"
  local memory_opts=""

  if [[ $totalMaxMemoryMb == 0 ]]; then
    printf "%s" "$memory_opts"
    return 0
  fi

  require_non_negative_integer "JVM_HEAD_ROOM" "$jvm_head_room"
  require_non_negative_integer "JVM_THREAD_COUNT" "$jvm_thread_count"

  local jvm_options_for_calculation="${jvm_opts} ${default_jvm_opts}"

  local total_memory_bytes=$((totalMaxMemoryMb * 1024 * 1024))
  local headroom_bytes=$((total_memory_bytes * jvm_head_room / 100))

  local direct_memory_size
  local metaspace_size
  local code_cache_size
  local stack_size
  direct_memory_size=$(find_last_jvm_option_value "-XX:MaxDirectMemorySize=" "$jvm_options_for_calculation")
  metaspace_size=$(find_last_jvm_option_value "-XX:MaxMetaspaceSize=" "$jvm_options_for_calculation")
  code_cache_size=$(find_last_jvm_option_value "-XX:ReservedCodeCacheSize=" "$jvm_options_for_calculation")
  stack_size=$(find_last_jvm_option_value "-Xss" "$jvm_options_for_calculation")

  if [[ -z "$direct_memory_size" ]]; then
    echo "Unable to calculate JVM heap: missing -XX:MaxDirectMemorySize value" >&2
    exit 2
  fi
  if [[ -z "$metaspace_size" ]]; then
    echo "Unable to calculate JVM heap: missing -XX:MaxMetaspaceSize value" >&2
    exit 2
  fi
  if [[ -z "$code_cache_size" ]]; then
    echo "Unable to calculate JVM heap: missing -XX:ReservedCodeCacheSize value" >&2
    exit 2
  fi
  if [[ -z "$stack_size" ]]; then
    stack_size="$DEFAULT_STACK_SIZE"
  fi

  local direct_memory_bytes
  local metaspace_bytes
  local code_cache_bytes
  local stack_bytes
  direct_memory_bytes=$(parse_memory_size_to_bytes "$direct_memory_size")
  metaspace_bytes=$(parse_memory_size_to_bytes "$metaspace_size")
  code_cache_bytes=$(parse_memory_size_to_bytes "$code_cache_size")
  stack_bytes=$(parse_memory_size_to_bytes "$stack_size")

  local overhead_bytes=$((
    headroom_bytes +
    direct_memory_bytes +
    metaspace_bytes +
    code_cache_bytes +
    stack_bytes * jvm_thread_count
  ))

  if ! has_stack_size "$jvm_options_for_calculation"; then
    memory_opts+=" -Xss${DEFAULT_STACK_SIZE}"
  fi

  if ! has_max_heap "$jvm_options_for_calculation"; then
    local heap_bytes=$((total_memory_bytes - overhead_bytes))

    if (( heap_bytes <= 0 )); then
      echo "Unable to calculate JVM heap: required non-heap memory exceeds container memory limit" >&2
      exit 2
    fi
    if (( heap_bytes < 1024 )); then
      echo "Unable to calculate JVM heap: calculated heap is less than 1K" >&2
      exit 2
    fi

    memory_opts+=" -Xmx$(format_memory_size "$heap_bytes")"
  fi

  printf "%s" "$memory_opts"
}

main() {
  local default_jvm_opts="-XX:+ExitOnOutOfMemoryError -XX:+UnlockDiagnosticVMOptions"

  if [[ "$SET_ACTIVE_PROFILE_GROUP" != "none" ]]; then
    default_jvm_opts+=" -Dspring.profiles.active=${SET_ACTIVE_PROFILE_GROUP}"
  fi

  local jvm_opts=${JAVA_TOOL_OPTIONS:-""}
  local limit
  limit=$(read_memory_limit)

  local totalMaxMemoryMb=0
  if [[ "$limit" != "max" && "$limit" != "9223372036854771712" ]]; then
    totalMaxMemoryMb=$((limit/1024/1024))
  fi

  default_jvm_opts=$(add_default_memory_area_opts "$totalMaxMemoryMb" "$jvm_opts" "$default_jvm_opts")

  if [ -n "${DUMP_HEAP_ON_OOM}" ]; then
    local uid="${POD_UID:-$(date +"%Y-%m-%d_%H-%M-%S")}"
    mkdir /home/app/crash-dumps
    default_jvm_opts+=" -XX:+HeapDumpOnOutOfMemoryError"
    default_jvm_opts+=" -XX:HeapDumpPath=/home/app/crash-dumps/oom_dump_$uid.hprof"
  fi

  if [ -n "${YK_ENABLED}" ]; then
    default_jvm_opts+=" -agentpath:/home/app/libyjpagent64.so=disablealloc,listen=all"
  elif [ -n "${JMX_ENABLED}" ]; then
  default_jvm_opts+=" "
  default_jvm_opts+=$(cat << EOF
-Djava.rmi.server.hostname=127.0.0.1 \
-Dcom.sun.management.jmxremote.authenticate=false \
-Dcom.sun.management.jmxremote.ssl=false \
-Dcom.sun.management.jmxremote.port=${JMX_PORT:-5000} \
-Dcom.sun.management.jmxremote.rmi.port=${JMX_PORT:-5000}
EOF
)
  fi

  if [ -n "${DEBUG_ENABLED}" ]; then
    default_jvm_opts+=" -agentlib:jdwp=transport=dt_socket,server=y,address=*:${DEBUG_PORT:-8000},"

    if [ -n "${DEBUG_SUSPEND}" ]
    then
      default_jvm_opts+="suspend=y"
    else
      default_jvm_opts+="suspend=n"
    fi
  fi

  local jvm_nmt_enabled=${JAVA_NMT_ENABLED:-"true"}
  if [[ $jvm_nmt_enabled == "true" ]]; then
    default_jvm_opts+=" -XX:+PrintNMTStatistics"

    local jvm_nmt_level=${JAVA_NMT_LEVEL:-"summary"}
    default_jvm_opts+=" -XX:NativeMemoryTracking=${jvm_nmt_level}"
  fi

  local jvm_head_room=${JVM_HEAD_ROOM:-0}
  local jvm_thread_count=${JVM_THREAD_COUNT:-$DEFAULT_JVM_THREAD_COUNT}
  local memory_opts
  memory_opts=$(calculate_memory_opts "$totalMaxMemoryMb" "$jvm_opts" "$default_jvm_opts" "$jvm_head_room" "$jvm_thread_count")

  local run_opts="$default_jvm_opts $memory_opts $jvm_opts"
  unset JAVA_TOOL_OPTIONS
  export JAVA_OPTS=$run_opts
  exec_launcher
}

# Run the launcher only when this script is executed directly. Tests source this file to call helper functions without starting the application.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
