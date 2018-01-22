#!/bin/bash
#CONTAINER_MAX_MEMORY=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes)
CONTAINER_MAX_MEMORY=536870912

# 以下变量可通过环境变量的形式传入
export JAVA_OPTS="-Duser.timezone=GMT+8"
RESERVED_MEGABYTES=268435456
JAVA_INIT_MEM_RATIO=20
JAVA_MAX_MEM_RATIO=70

# Generic formula evaluation based on awk
calc() {
  local formula="$1"
  shift
  echo "$@" | awk '
    function ceil(x) {
      return x % 1 ? int(x) + 1 : x
    }
    function log2(x) {
      return log(x)/log(2)
    }
    function max2(x, y) {
      return x > y ? x : y
    }
    function round(x) {
      return int(x + 0.5)
    }
    {printf "%d\n",'"${formula}"'}
  '
}

calc_mem_opt() {
  local max_mem="$1"
  local fraction="$2"
  local mem_opt="$3"
  local val=$(calc 'round($1*$2/100/1048576)' "${max_mem}" "${fraction}")
  echo "-X${mem_opt}${val}m"
}

# Check for memory options and set initial heap size if requested
calc_init_memory() {
  # Check whether -Xms is already given in JAVA_OPTS.
  if echo "${JAVA_OPTS:-}" | grep -q -- "-Xms"; then
    return
  fi

  # Check if value set
  if [ -z "${JAVA_INIT_MEM_RATIO:-}" ] || [ -z "${available_memory_size:-}" ]; then
    return
  fi

  # Calculate Xms from the ratio given
  calc_mem_opt "${available_memory_size}" "${JAVA_INIT_MEM_RATIO}" "ms"
}

# Check for memory options and set max heap size if needed
calc_max_memory() {
  # Check whether -Xmx is already given in JAVA_OPTS
  if echo "${JAVA_OPTS:-}" | grep -q -- "-Xmx"; then
    return
  fi

  if [ -z "${available_memory_size:-}" ]; then
    return
  fi

  # Check for the 'real memory size' and calculate Xmx from the ratio
  if [ -n "${JAVA_MAX_MEM_RATIO:-}" ]; then
    calc_mem_opt "${available_memory_size}" "${JAVA_MAX_MEM_RATIO}" "mx"
  else
    if [ "${available_memory_size}" -le 314572800 ]; then
      # Restore the one-fourth default heap size instead of the one-half below 300MB threshold
      # See https://docs.oracle.com/javase/8/docs/technotes/guides/vm/gctuning/parallel.html#default_heap_size
      calc_mem_opt "${available_memory_size}" "25" "mx"
    else
      calc_mem_opt "${available_memory_size}" "50" "mx"
    fi
  fi
}

memory_options() {
  echo "$(calc_init_memory) $(calc_max_memory)"
  return
}

java_options() {
  echo "${JAVA_OPTS:-} $(memory_options) -XX:+PrintFlagsFinal"
}

# If not default limit_in_bytes in cgroup
if [ "$CONTAINER_MAX_MEMORY" -ne "9223372036854771712" ]
then
   available_memory_size=$(expr $CONTAINER_MAX_MEMORY - $RESERVED_MEGABYTES)
#   JAVA_OPTS= "${JAVA_OPTS:-} $(memory_options) -XX:+PrintFlagsFinal"
fi

exec java $(java_options) -version | grep Heap
