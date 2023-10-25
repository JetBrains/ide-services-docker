#!/bin/bash

set -e

DEFAULT_RESERVED_CODE_CACHE_SIZE="240M"
DEFAULT_MAX_METASPACE_SIZE="400M"
DEFAULT_JVM_THREAD_COUNT=200

default_jvm_opts="-XX:+ExitOnOutOfMemoryError -XX:+UnlockDiagnosticVMOptions"
jvm_opts=${JAVA_TOOL_OPTIONS:-""}

if test -f /sys/fs/cgroup/memory/memory.limit_in_bytes; then
  limit=`cat /sys/fs/cgroup/memory/memory.limit_in_bytes`
else
  limit=`cat /sys/fs/cgroup/memory.max`
fi

totalMaxMemoryMb=0
if [[ "$limit" != "max" && "$limit" != "9223372036854771712" ]]; then
  totalMaxMemoryMb=$((limit/1024/1024))

  if [[ $jvm_opts != *"-XX:MaxDirectMemorySize="* ]]; then
    jvm_direct_memory=$((50 + totalMaxMemoryMb/512 * 25))
    default_jvm_opts+=" -XX:MaxDirectMemorySize=${jvm_direct_memory}M"
  fi
fi

if [[ $jvm_opts != *"-XX:MaxMetaspaceSize="* ]]; then
  default_jvm_opts+=" -XX:MaxMetaspaceSize=${DEFAULT_MAX_METASPACE_SIZE}"
fi

if [[ $jvm_opts != *"-XX:ReservedCodeCacheSize="* ]]; then
  default_jvm_opts+=" -XX:ReservedCodeCacheSize=${DEFAULT_RESERVED_CODE_CACHE_SIZE}"
fi

if [ -n "${DUMP_HEAP_ON_OOM}" ]; then
  default_jvm_opts+=" -XX:-HeapDumpOnOutOfMemoryError"
  default_jvm_opts+=" -XX:HeapDumpPath=/home/app/oom_dump.hprof"
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

jvm_nmt_enabled=${JAVA_NMT_ENABLED:-"true"}
if [[ $jvm_nmt_enabled == "true" ]]; then
  default_jvm_opts+=" -XX:+PrintNMTStatistics"

  jvm_nmt_level=${JAVA_NMT_LEVEL:-"summary"}
  default_jvm_opts+=" -XX:NativeMemoryTracking=${jvm_nmt_level}"
fi

jvm_head_room=${JVM_HEAD_ROOM:-0}
jvm_thread_count=${JVM_THREAD_COUNT:-$DEFAULT_JVM_THREAD_COUNT}

# --loaded-class-count below is passed to overwrite defaults and do not include heuristics in calculations
memory_opts=""
if [[ $totalMaxMemoryMb != 0 ]]; then
  memory_opts=`/opt/java-buildpack-memory-calculator \
    --head-room ${jvm_head_room} \
    --thread-count ${jvm_thread_count}\
    --loaded-class-count 1\
    --total-memory "${totalMaxMemoryMb}M"\
    --jvm-options "${jvm_opts} ${default_jvm_opts}"`
fi

run_opts="$default_jvm_opts $memory_opts $jvm_opts"
unset JAVA_TOOL_OPTIONS
export JAVA_OPTS=$run_opts
/app/tbe-launcher-*/bin/tbe-launcher
