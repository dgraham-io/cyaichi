#!/bin/bash

# Script to start both client and server for development
# Usage: ./dev-run.sh
# Press Ctrl+C to stop both

set -e

# Function to cleanup on exit
cleanup() {
    echo "Stopping server and client..."
    if [ ! -z "$SERVER_PID" ]; then
        kill $SERVER_PID 2>/dev/null || true
    fi
    if [ ! -z "$CLIENT_PID" ]; then
        kill $CLIENT_PID 2>/dev/null || true
    fi
    exit 0
}

# Set trap to cleanup on interrupt
trap cleanup SIGINT SIGTERM

echo "Starting cyaichi development environment..."

# Start server in background
echo "Starting server..."
cd server
go run ./cmd/cyaichi-server &
SERVER_PID=$!
cd ..

# Wait a bit for server to start
sleep 2

# Start client in background (since flutter run is interactive)
echo "Starting client..."
cd client
flutter run -d macos &
CLIENT_PID=$!
cd ..

echo "Server PID: $SERVER_PID"
echo "Client PID: $CLIENT_PID"
echo "Both services started. Press Ctrl+C to stop."

# Wait for processes
wait $CLIENT_PID $SERVER_PID