# Day 2: Loops, Functions, and Arguments in Bash

**Goal**: Master `for`, `while`, `until` loops and Bash functions with best practices.
**Senior DevOps Tips**: Always use `set -euo pipefail`, `local` variables in functions, and quote variables.

---

## 1. For Loop

### 1.1 Simple list


#!/bin/bash
set -euo pipefail

for fruit in apple banana cherry date; do
  echo "I like $fruit"
done

### 1.2 Loop over files
for file in scripts/basics/day2/*.sh; do
  echo "Found script: $file"
done

### 1.3 C-style for loop
for ((i=1; i<=5; i++)); do
  echo "Count: $i"
done

## 2. While & Until Loops
### 2.1 While loop with counter
count=1
while [ $count -le 5 ]; do
  echo "While count: $count"
  ((count++))
done

### 2.2 Read file line by line
while IFS= read -r line; do
  echo "Line: $line"
done < README.md

### 2.3 Until loop (runs until condition is true)
seconds=0
until [ $seconds -ge 3 ]; do
  echo "Waiting... $seconds seconds"
  sleep 1
  ((seconds++))
done

## 3. Functions – Best Practices
### 3.1 Basic function with local variables
greet() {
  local name="$1"           # local 
  local timestamp=$(date +%F_%H:%M:%S)
  echo "[$timestamp] Hello, $name! Welcome to Bash mastery."
}

greet "DevOps Engineer"




### 3.2 Function with return value (use echo, not return for strings)
add() {
  local a=$1
  local b=$2
  echo $((a + b))           # خروجی رو echo می‌کنیم
}

result=$(add 15 27)         # نتیجه رو capture می‌کنیم
echo "15 + 27 = $result"



### 3.3 Function with default arguments
backup() {
  local src="${1:-/home}"   # اگر آرگومان نداد، /home پیش‌فرض
  local dest="${2:-/backup}"
  echo "Backing up $src → $dest at $(date)"
}
backup                    # → از دیفالت استفاده می‌کنه
backup /etc /var/backup   # → مقدار دلخواه


### 3.4 Advanced: Return multiple values via global array
get_system_info() {
  local info=()
  info+=("user:$(whoami)")
  info+=("host:$(hostname)")
  info+=("uptime:$(uptime -p)")
  SYSTEM_INFO=("${info[@]}")  # global array
}
get_system_info
echo "System info collected: ${SYSTEM_INFO[@]}"

## 4. Advanced Argument Handling
### 4.1 getopts – Professional argument parsing
#!/bin/bash
set -euo pipefail

usage() {
  echo "Usage: $0 -n NAME -a AGE [-v]"
  exit 1
}

verbose=0
while getopts "n:a:v" opt; do
  case $opt in
    n) name="$OPTARG" ;;
    a) age="$OPTARG" ;;
    v) verbose=1 ;;
    *) usage ;;
  esac
done

[[ -z "$name" || -z "$age" ]] && usage

echo "Name: $name, Age: $age"
((verbose)) && echo "Verbose mode enabled"

### Run examples:
./args-getopts.sh -n Ali -a 30
./args-getopts.sh -n Ali -a 30 -v























