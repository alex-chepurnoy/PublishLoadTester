#!/bin/bash

echo "Testing heap parsing AWK logic..."
echo ""

# Test input matching your jcmd output
test_input="1028:  ZHeap           used 638M, capacity 638M, max capacity 5416M"

echo "Input: $test_input"
echo ""

result=$(echo "$test_input" | awk '
BEGIN { used_kb=0; max_kb=0 }
/ZHeap.*used/ {
  for(i=1; i<=NF; i++) {
    if ($i == "used" && $(i+1) ~ /^[0-9]+M/) {
      gsub(/[^0-9]/, "", $(i+1));
      used_kb = $(i+1) * 1024;
    }
    if ($i == "max" && $(i+1) == "capacity" && $(i+2) ~ /^[0-9]+M/) {
      gsub(/[^0-9]/, "", $(i+2));
      max_kb = $(i+2) * 1024;
    }
  }
}
END {
  if (max_kb > 0) {
    pct = (used_kb / max_kb) * 100;
    printf "%.2f", pct;
  } else { print "0.00"; }
}')

echo "Result: $result%"
echo ""

# Calculate expected: 638M / 5416M * 100 = 11.78%
echo "Expected: 11.78%"
echo ""

if [ "$result" == "11.78" ]; then
  echo "✓ TEST PASSED"
  exit 0
else
  echo "✗ TEST FAILED"
  exit 1
fi
