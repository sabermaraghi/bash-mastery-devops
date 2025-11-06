#!/bin/bash
set -euo pipefail

greet() {
  local name="$1"           # local → ﻒﻘﻃ ﺩﺎﺨﻟ ﻑﺎﻨﮑﺸﻧ ﺪﯾﺪﻫ ﻢﯿﺸﻫ
  local timestamp=$(date +%F_%H:%M:%S)
  echo "[$timestamp] Hello, $name! Welcome to Bash mastery."
}
greet "DevOps Engineer"


add() {
  local a=$1
  local b=$2
  echo $((a + b))           # ﺥﺭﻮﺠﯾ ﺭﻭ echo ﻢﯾ<200c>ﮑﻨﯿﻣ
}
result=$(add 15 27)         # ﻦﺘﯿﺠﻫ ﺭﻭ capture ﻢﯾ<200c>ﮑﻨﯿﻣ
echo "15 + 27 = $result"


backup() {
  local src="${1:-/home}"   # ﺎﮔﺭ ﺁﺮﮔﻮﻣﺎﻧ ﻥﺩﺍﺩ، /home ﭗﯿﺷ<200c>ﻓﺮﺿ
  local dest="${2:-/backup}"
  echo "Backing up $src → $dest at $(date)"
}

backup                    # → ﺍﺯ ﺪﯿﻓﺎﻠﺗ ﺎﺴﺘﻓﺍﺪﻫ ﻢﯾ<200c>ﮑﻨﻫ
backup /etc /var/backup   # → ﻢﻗﺩﺍﺭ ﺪﻠﺧﻭﺎﻫ


get_system_info() {
  local info=()
  info+=("user:$(whoami)")
  info+=("host:$(hostname)")
#  info+=("uptime:$(uptime -p)")
  SYSTEM_INFO=("${info[@]}")  # global array
}
get_system_info
echo "System info collected: ${SYSTEM_INFO[@]}"

