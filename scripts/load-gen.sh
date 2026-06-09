#!/usr/bin/env bash

set -euo pipefail

APP_URL="${APP_URL:-http://192.168.200.240}"
WORKERS="${WORKERS:-10}"

case "${1:-}" in
  start)
    echo "Starting load against ${APP_URL} with ${WORKERS} workers..."
    for i in $(seq 1 "${WORKERS}"); do
      while true; do
        curl -s -o /dev/null "${APP_URL}/"
      done &
      echo $! >> /tmp/sample-webapp-load.pids
    done
    echo "Load started. PID file: /tmp/sample-webapp-load.pids"
    ;;

  stop)
    if [ -f /tmp/sample-webapp-load.pids ]; then
      xargs -r kill < /tmp/sample-webapp-load.pids || true
      rm -f /tmp/sample-webapp-load.pids
      echo "Load stopped."
    else
      echo "No PID file found."
    fi
    ;;

  status)
    if [ -f /tmp/sample-webapp-load.pids ]; then
      echo "Load generator PIDs:"
      cat /tmp/sample-webapp-load.pids
    else
      echo "Load generator is not running."
    fi
    ;;

  *)
    echo "Usage: $0 {start|stop|status}"
    echo "Example:"
    echo "  WORKERS=20 APP_URL=http://192.168.200.240 $0 start"
    exit 1
    ;;
esac