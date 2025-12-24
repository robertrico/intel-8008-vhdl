#!/bin/bash
# Assemble all test programs in this directory
# Usage: ./assemble_all.sh

cd "$(dirname "$0")/.." || exit 1

for asm in test_programs/*_as.asm; do
    prog=$(basename "$asm" .asm)
    echo "Assembling $prog..."
    make assemble PROG="$prog" 2>&1 | grep -E "error|warning|Converted" || true
done

echo ""
echo "Done assembling all test programs."
