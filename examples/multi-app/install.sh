#!/bin/bash

# Install dependencies for all apps in the multi-app example

set -e

echo "Installing dependencies for multi-app example..."

# Create logs directory
mkdir -p logs

# Install App 1
echo "Installing App 1 (Dashboard)..."
cd app1
npm install
cd ..

# Install App 2
echo "Installing App 2 (Analytics)..."
cd app2
npm install
cd ..

# Install App 3
echo "Installing App 3 (Settings)..."
cd app3
npm install
cd ..

echo "✓ All dependencies installed!"
echo ""
echo "Next steps:"
echo "  1. Configure nginx with the multi-app configuration"
echo "  2. Start all apps: ./start-all.sh"
echo "  3. Visit: https://your-domain.com/app1/"
