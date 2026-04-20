#!/bin/bash

# Define the build matrix
targets=(
    "x86_64-linux"
    "aarch64-linux"
    "x86_64-macos"
    "aarch64-macos"
    "x86_64-freebsd"
    "aarch64-freebsd"
)

failed=0

echo "Starting matrix build for Zig 0.15.2"

for target in "${targets[@]}"; do
    echo "-------------------------------------------"
    echo "Building for: $target"
    #echo "-------------------------------------------"

    if zig build -Dtarget="$target" -Doptimize=ReleaseFast; then
        echo "Successfully built $target"
    else
        echo "Failed to build $target"
        failed=1
    fi
done

if [ $failed -ne 0 ]; then
    echo "One or more builds failed."
    exit 1
fi

echo
echo "All builds completed successfully."
