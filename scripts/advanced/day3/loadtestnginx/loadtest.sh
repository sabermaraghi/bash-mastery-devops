#!/bin/bash

# This script performs a simple load test on an Nginx server using Apache Bench (ab).
# Ensure 'ab' is installed on your system (e.g., via 'sudo apt install apache2-utils' on Ubuntu).
# Usage: ./load_test_nginx.sh <url> <total_requests> <concurrent_requests>
# Example: ./load_test_nginx.sh http://localhost/ 10 10

if [ $# -ne 3 ]; then
    echo "Usage: $0 <url> <total_requests> <concurrent_requests>"
    exit 1
fi

URL=$1
REQUESTS=$2
CONCURRENCY=$3

echo "Starting load test on $URL with $REQUESTS requests and $CONCURRENCY concurrent users..."

ab -n $REQUESTS -c $CONCURRENCY $URL

echo "Load test completed."
