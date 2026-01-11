#!/bin/bash

# Stop all running apps

echo "Stopping all applications..."

# Stop App 1
if [ -f logs/app1.pid ]; then
    PID=$(cat logs/app1.pid)
    if kill -0 $PID 2>/dev/null; then
        echo "Stopping App 1 (PID: $PID)..."
        kill $PID
        rm logs/app1.pid
    else
        echo "App 1 not running"
        rm logs/app1.pid
    fi
fi

# Stop App 2
if [ -f logs/app2.pid ]; then
    PID=$(cat logs/app2.pid)
    if kill -0 $PID 2>/dev/null; then
        echo "Stopping App 2 (PID: $PID)..."
        kill $PID
        rm logs/app2.pid
    else
        echo "App 2 not running"
        rm logs/app2.pid
    fi
fi

# Stop App 3
if [ -f logs/app3.pid ]; then
    PID=$(cat logs/app3.pid)
    if kill -0 $PID 2>/dev/null; then
        echo "Stopping App 3 (PID: $PID)..."
        kill $PID
        rm logs/app3.pid
    else
        echo "App 3 not running"
        rm logs/app3.pid
    fi
fi

echo "✓ All apps stopped"
