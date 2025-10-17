# Java Heap Monitoring: jcmd vs jstat vs jmap

## Quick Comparison

| Feature | jcmd | jstat | jmap |
|---------|------|-------|------|
| **Ease of Use** | ✅ Easy | ⚠️ Medium | ⚠️ Medium |
| **Output Format** | ✅ Human-readable | ⚠️ Column-based | ⚠️ Verbose |
| **Parsing** | ✅ Simple awk | ⚠️ Complex awk | ⚠️ Complex regex |
| **Speed** | ✅ Fast | ✅ Fast | ❌ Slow |
| **Availability** | ✅ JDK 7+ | ✅ JDK 5+ | ✅ JDK 5+ |
| **Live Query** | ✅ Yes | ✅ Yes | ⚠️ Yes (heavy) |
| **Recommended** | ✅ PRIMARY | ✅ Fallback | ⚠️ Last resort |

## Implementation Strategy

We use a **cascading fallback approach**:

```
1. Try jcmd GC.heap_info     (PRIMARY - fastest, easiest)
   ↓ fails
2. Try jstat -gc             (FALLBACK 1 - widely available)
   ↓ fails  
3. Try jmap -heap            (FALLBACK 2 - slow but comprehensive)
   ↓ fails
4. Return 0.00               (graceful degradation)
```

## Method 1: jcmd GC.heap_info (PRIMARY)

### Command
```bash
jcmd <PID> GC.heap_info
```

### Example Output
```
PSYoungGen      total 76288K, used 45123K [0x00000000eab00000, 0x00000000f0000000, 0x0000000100000000)
  eden space 65536K, 68% used [0x00000000eab00000,0x00000000ed70ceb8,0x00000000eeb00000)
  from space 10752K, 0% used [0x00000000ef580000,0x00000000ef580000,0x00000000f0000000)
  to   space 10752K, 0% used [0x00000000eeb00000,0x00000000eeb00000,0x00000000ef580000)
 ParOldGen       total 174592K, used 98234K [0x00000000c0000000, 0x00000000caa80000, 0x00000000eab00000)
  object space 174592K, 56% used [0x00000000c0000000,0x00000000c5ff6930,0x00000000caa80000)
 Metaspace       used 45678K, capacity 48576K, committed 48896K, reserved 1093632K
  class space    used 5678K, capacity 6144K, committed 6272K, reserved 1048576K
```

### Parsing (Simple)
```bash
jcmd $PID GC.heap_info | awk '
  /PSYoungGen|ParOldGen|PSOldGen/ {
    # Extract "total" and "used" values
    if($0 ~ /total/) {
      for(i=1; i<=NF; i++) {
        if($i ~ /^[0-9]+K/) {
          gsub(/K/, "", $i)
          total_kb += $i
        }
      }
    }
    if($0 ~ /used/) {
      for(i=1; i<=NF; i++) {
        if($i ~ /^[0-9]+K/) {
          gsub(/K/, "", $i)
          used_kb += $i
        }
      }
    }
  }
  END {
    if(total_kb > 0) {
      printf "%.2f", (used_kb / total_kb) * 100
    } else {
      print "0.00"
    }
  }
'
```

### Result
```
57.14
```
Meaning: **57.14% heap usage** (143357K used / 250880K total)

### Advantages
- ✅ **Human-readable** - Easy to understand output
- ✅ **Clear values** - "total" and "used" explicitly labeled
- ✅ **Fast** - Minimal overhead
- ✅ **Reliable** - Consistent format across Java versions
- ✅ **Modern** - Recommended by Oracle

---

## Method 2: jstat -gc (FALLBACK)

### Command
```bash
jstat -gc <PID>
```

### Example Output
```
 S0C    S1C    S0U    S1U      EC       EU        OC         OU       MC     MU    CCSC   CCSU   YGC     YGCT    FGC    FGCT    CGC    CGCT     GCT   
10752.0 10752.0  0.0   0.0   65536.0  45123.0  174592.0   98234.0  48576.0 45678.0 6144.0 5678.0    245    1.234    12   0.567     5    0.234   2.035
```

### Column Meanings
- **S0C/S1C** - Survivor space 0/1 capacity (KB)
- **S0U/S1U** - Survivor space 0/1 used (KB)
- **EC** - Eden capacity (KB)
- **EU** - Eden used (KB)
- **OC** - Old generation capacity (KB)
- **OU** - Old generation used (KB)
- **MC** - Metaspace capacity (KB)
- **MU** - Metaspace used (KB)

### Parsing (Complex)
```bash
jstat -gc $PID | tail -n1 | awk '{
  # Column positions (may vary by Java version!)
  eden_used=$6      # EU
  s0_used=$3        # S0U
  s1_used=$5        # S1U
  old_used=$10      # OU
  
  eden_max=$1       # S0C (approximation)
  s0_max=$2         # S1C
  s1_max=$4         # EC (approximation)
  old_max=$8        # OC
  
  total_used = eden_used + s0_used + s1_used + old_used
  total_max = eden_max + s0_max + s1_max + old_max
  
  if(total_max > 0) {
    printf "%.2f", (total_used / total_max) * 100
  } else {
    print "0.00"
  }
}'
```

### Result
```
57.14
```

### Disadvantages
- ⚠️ **Column-based** - Must know exact column numbers
- ⚠️ **Calculation required** - Manual summing of multiple columns
- ⚠️ **Version-dependent** - Column order can change between Java versions
- ⚠️ **Cryptic** - Abbreviations not intuitive

### Advantages
- ✅ **Widely available** - Works on older Java versions
- ✅ **Fast** - Low overhead
- ✅ **Well-known** - More documentation/examples online

---

## Method 3: jmap -heap (LAST RESORT)

### ⚠️ WARNING: Not Suitable for Live Monitoring

**jmap -heap causes JVM pauses** and should **ONLY be used as a last resort fallback** when both jcmd and jstat fail. It is **NOT suitable for frequent polling** during tests.

**DO NOT USE jmap during active tests** - it will impact server performance!

### Command
```bash
jmap -heap <PID>
```

### Example Output
```
Attaching to process ID 12345, please wait...
Debugger attached successfully.
Server compiler detected.
JVM version is 11.0.12+7-Ubuntu-0ubuntu3

using thread-local object allocation.
Parallel GC with 8 thread(s)

Heap Configuration:
   MinHeapFreeRatio         = 0
   MaxHeapFreeRatio         = 100
   MaxHeapSize              = 4294967296 (4096.0MB)
   NewSize                  = 89128960 (85.0MB)
   MaxNewSize               = 1431306240 (1365.0MB)
   OldSize                  = 179306496 (171.0MB)
   NewRatio                 = 2
   SurvivorRatio            = 8
   MetaspaceSize            = 21807104 (20.796875MB)
   CompressedClassSpaceSize = 1073741824 (1024.0MB)
   MaxMetaspaceSize         = 17592186044415 MB
   G1HeapRegionSize         = 0 (0.0MB)

Heap Usage:
PS Young Generation
Eden Space:
   capacity = 67108864 (64.0MB)
   used     = 46206464 (44.0625MB)
   free     = 20902400 (19.9375MB)
   68.84765625% used
From Space:
   capacity = 11010048 (10.5MB)
   used     = 0 (0.0MB)
   free     = 11010048 (10.5MB)
   0.0% used
To Space:
   capacity = 11010048 (10.5MB)
   used     = 0 (0.0MB)
   free     = 11010048 (10.5MB)
   0.0% used
PS Old Generation
   capacity = 178782208 (170.5MB)
   used     = 100591616 (95.9140625MB)
   free     = 78190592 (74.5859375MB)
   56.25076611292949% used
```

### Parsing (Very Complex)
```bash
jmap -heap $PID | awk '
  /capacity =/ {
    gsub(/[^0-9]/, "", $3)
    capacity = $3
  }
  /used =/ {
    gsub(/[^0-9]/, "", $3)
    used = $3
    if(capacity > 0) {
      heap_pct = (used / capacity) * 100
    }
  }
  /% used/ {
    gsub(/%.*/, "", $1)
    total_pct += $1
    count++
  }
  END {
    if(count > 0) {
      printf "%.2f", total_pct / count
    } else if(capacity > 0) {
      printf "%.2f", (used / capacity) * 100
    } else {
      print "0.00"
    }
  }
'
```

### Disadvantages
- ❌ **Very slow** - Can take several seconds
- ❌ **Intrusive** - Causes JVM pause (Stop-The-World)
- ❌ **Not suitable for tests** - Will impact server performance
- ❌ **Verbose output** - Hundreds of lines
- ❌ **Complex parsing** - Multiple sections to aggregate
- ⚠️ **USE ONLY as emergency fallback** when jcmd and jstat both fail

### Advantages
- ✅ **Comprehensive** - Most detailed heap information
- ✅ **Diagnostic** - Good for troubleshooting (offline)
- ✅ **Widely available** - Works on all JDK versions

### When to Use jmap
- ✅ Post-test diagnostics
- ✅ One-time heap analysis
- ✅ Troubleshooting memory issues
- ❌ **NEVER during active load tests**
- ❌ **NEVER for frequent polling**

---

## Recommended Implementation

### get_server_heap() Function

```bash
function get_server_heap() {
  local heap_raw
  local wowza_pid
  
  # 1. Get Wowza PID
  wowza_pid=$(ssh ... "ps aux | grep Wowza | awk '{print $2}'")
  
  if [[ -z "$wowza_pid" ]]; then
    echo "0.00"
    return
  fi
  
  # 2. Try jcmd first (RECOMMENDED)
  heap_raw=$(ssh ... "jcmd $wowza_pid GC.heap_info" | awk '...')
  
  # 3. If jcmd fails, try jstat
  if [[ -z "$heap_raw" ]] || [[ "$heap_raw" == "0.00" ]]; then
    heap_raw=$(ssh ... "jstat -gc $wowza_pid" | awk '...')
  fi
  
  # 4. If jstat fails, try jmap (last resort, avoid if possible)
  if [[ -z "$heap_raw" ]] || [[ "$heap_raw" == "0.00" ]]; then
    heap_raw=$(ssh ... "jmap -heap $wowza_pid" | awk '...')
  fi
  
  # 5. Return result or 0.00
  echo "${heap_raw:-0.00}"
}
```

## Testing Each Method

```bash
# Get Wowza PID
PID=$(ps aux | grep -E '[Ww]owza|java.*com.wowza' | grep -v grep | awk '{print $2}' | head -n1)

# Test jcmd
echo "=== Testing jcmd ==="
time jcmd $PID GC.heap_info
# Expected: ~50ms, easy to read output

# Test jstat
echo "=== Testing jstat ==="
time jstat -gc $PID
# Expected: ~30ms, column-based output

# Test jmap
echo "=== Testing jmap ==="
time jmap -heap $PID | head -n 50
# Expected: ~500ms-2s, very verbose

# Compare parsing
echo "=== Parsing Comparison ==="

# jcmd parsing
jcmd $PID GC.heap_info | awk '/total|used/ {print}'
# Output: Clear "total 76288K, used 45123K"

# jstat parsing
jstat -gc $PID | tail -n1
# Output: Cryptic columns "10752.0 10752.0 0.0 0.0 65536.0 45123.0..."

# jmap parsing
jmap -heap $PID | grep -E "capacity|used" | head -n 10
# Output: Verbose multi-line sections
```

## Summary Recommendation

### For Live Monitoring During Tests

✅ **Use jcmd as PRIMARY method**
- Non-intrusive to JVM
- Fastest to parse
- Most reliable
- Modern best practice
- Human-readable

✅ **Use jstat as FALLBACK**
- Non-intrusive to JVM
- Widely available
- Still fast
- Good compatibility

❌ **Avoid jmap during tests**
- Causes JVM pauses
- Too slow for polling
- Impacts test accuracy
- Only use if both jcmd and jstat fail

### jmap Usage Restrictions

**ONLY use jmap when:**
- Both jcmd and jstat have failed
- Testing in pilot mode (not production)
- Acceptable to impact one test result
- Need diagnostic information

**NEVER use jmap for:**
- ❌ Frequent polling (every test)
- ❌ Production test runs
- ❌ Continuous monitoring
- ❌ Critical capacity tests

### Better Alternatives to Heap Dumps

Instead of `jcmd GC.heap_dump` or `jmap -dump`, use:
- ✅ `jcmd GC.heap_info` - Non-intrusive heap summary
- ✅ `jstat -gc` - Continuous monitoring
- ✅ `jstat -gcutil` - Utilization percentages
- ✅ JMX monitoring - Remote monitoring without SSH

---

**Last Updated**: October 17, 2025  
**Author**: Implementation Plan Phase 0
