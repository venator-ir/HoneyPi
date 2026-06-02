#!/bin/bash

SCRIPT_PATH="/root/honeypi/venatorhoneypot.py"
PYTHON="/usr/bin/python3"
LOG="/var/log/honeypi-watchdog.log"

if pgrep -f "$SCRIPT_PATH" > /dev/null 2>&1; then
    echo "$(date) - HoneyPi running" >> "$LOG"
else
    echo "$(date) - HoneyPi NOT running, starting it" >> "$LOG"
    nohup $PYTHON "$SCRIPT_PATH" >> /var/log/honeypi.log 2>&1 &
fi
