#!/bin/sh
cd "$(dirname "$0")"
echo "=== DiskTree build ==="
pkill -x DiskTree 2>/dev/null; pkill -x DiskLens 2>/dev/null; rm -rf build/DiskLens.app; sleep 0.5
./build.sh run 2>&1 | tee build.log
echo "=== exit: $? (log: build.log) ==="
