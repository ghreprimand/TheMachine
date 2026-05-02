#!/bin/sh
# Strip comments, collapse whitespace, convert hex to binary.
sed 's/#.*//' machine-dump.hex | tr -d ' \n\r' | xxd -r -p > machine-dump
chmod +x machine-dump
echo "Built machine-dump: $(wc -c < machine-dump) bytes"
