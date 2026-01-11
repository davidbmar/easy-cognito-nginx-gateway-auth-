#!/bin/bash

# Start all apps in the background

set -e

echo "Starting all applications..."

# Create logs directory
mkdir -p logs

# Start App 1
echo "Starting App 1 (Dashboard) on port 3001..."
cd app1
npm start > ../logs/app1.log 2>&1 &
echo $! > ../logs/app1.pid
cd ..

# Start App 2
echo "Starting App 2 (Analytics) on port 3002..."
cd app2
npm start > ../logs/app2.log 2>&1 &
echo $! > ../logs/app2.pid
cd ..

# Start App 3
echo "Starting App 3 (Settings) on port 3003..."
cd app3
npm start > ../logs/app3.log 2>&1 &
echo $! > ../logs/app3.pid
cd ..

sleep 2

echo ""
echo "✓ All apps started!"
echo ""
echo "Process IDs:"
echo "  App 1: $(cat logs/app1.pid)"
echo "  App 2: $(cat logs/app2.pid)"
echo "  App 3: $(cat logs/app3.pid)"
echo ""
echo "View logs:"
echo "  tail -f logs/app1.log"
echo "  tail -f logs/app2.log"
echo "  tail -f logs/app3.log"
echo ""
echo "Stop all apps:"
echo "  ./stop-all.sh"
echo ""
echo "Access apps:"
echo "  https://your-domain.com/app1/"
echo "  https://your-domain.com/app2/"
echo "  https://your-domain.com/app3/"
