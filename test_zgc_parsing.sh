#!/usr/bin/env bash
# Test script to verify ZGC heap parsing

# Simulate ZGC output
zgc_output="ZHeap           used 194M, capacity 496M, max capacity 5416M
 Metaspace       used 70154K, committed 70912K, reserved 1114112K
  class space    used 6055K, committed 6464K, reserved 1048576K"

echo "=== Testing ZGC Output Parsing ==="
echo "Input:"
echo "$zgc_output"
echo ""

result=$(echo "$zgc_output" | awk '
  BEGIN { total_kb=0; used_kb=0 }
  /ZHeap|Z Heap/ {
    # Check for MB format (ZGC)
    if ($0 ~ /used [0-9]+M/ || $0 ~ /capacity [0-9]+M/ || $0 ~ /total [0-9]+M/) {
      for(i=1; i<=NF; i++) {
        if ($i == "used" && $(i+1) ~ /^[0-9]+M/) {
          gsub(/[^0-9]/, "", $(i+1))
          used_kb = $(i+1) * 1024  # Convert MB to KB
          print "DEBUG: Found used=" $(i+1) "M -> " used_kb "KB" > "/dev/stderr"
        }
        if ($i == "capacity" && $(i+1) ~ /^[0-9]+M/ && $(i-1) !~ /max/) {
          gsub(/[^0-9]/, "", $(i+1))
          total_kb = $(i+1) * 1024  # Convert MB to KB
          print "DEBUG: Found capacity=" $(i+1) "M -> " total_kb "KB" > "/dev/stderr"
        }
      }
    }
  }
  END {
    print "DEBUG: Final total_kb=" total_kb ", used_kb=" used_kb > "/dev/stderr"
    if(total_kb > 0) printf "%.2f", (used_kb / total_kb) * 100
    else print "0.00"
  }
')

echo "Output: $result%"
echo ""
echo "Expected: 39.11% (194 / 496)"
