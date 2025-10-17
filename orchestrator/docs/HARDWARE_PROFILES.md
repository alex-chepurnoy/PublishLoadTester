# Hardware Profiles for Test Matrix

## Overview

Different hardware configurations have different capacity limits. Instead of modifying the test matrix, we can use **hardware profiles** that adjust connection levels based on expected system capabilities.

## Profile Definitions

### Small System Profile (4 cores, 8GB RAM)
**Use Case**: Development servers, low-end cloud instances, testing environments

```bash
CONNECTIONS=(1 5 10 20)
```

**Expected Behavior**:
- 360p: All tests complete
- 720p: Most tests complete
- 1080p: May hit limits at 20
- 4K: Stops early

**Total Tests**: 48 (3 protocols × 4 resolutions × 4 connection levels)
**Estimated Time**: 12 hours max (likely 6-8 hours with adaptive stopping)

---

### Medium System Profile (8 cores, 16GB RAM)
**Use Case**: Mid-tier servers, production evaluation

```bash
CONNECTIONS=(1 5 10 20 50)
```

**Expected Behavior**:
- 360p: All tests complete
- 720p: All tests complete
- 1080p: May hit limits at 50
- 4K: Stops at 10-20

**Total Tests**: 60 (3 protocols × 4 resolutions × 5 connection levels)
**Estimated Time**: 15 hours max (likely 10-12 hours)

---

### Large System Profile (16+ cores, 32GB+ RAM)
**Use Case**: Production servers, high-capacity testing

```bash
CONNECTIONS=(1 5 10 20 50 100)
```

**Expected Behavior**:
- 360p: All tests complete
- 720p: All tests complete  
- 1080p: Most tests complete
- 4K: May hit limits at 50-100

**Total Tests**: 72 (3 protocols × 4 resolutions × 6 connection levels)
**Estimated Time**: 18 hours max (likely 12-15 hours)

---

### Enterprise System Profile (32+ cores, 64GB+ RAM)
**Use Case**: Large-scale production validation, stress testing

```bash
CONNECTIONS=(1 5 10 20 50 100 200)
```

**Expected Behavior**:
- 360p: All tests complete
- 720p: All tests complete
- 1080p: All tests complete
- 4K: Most tests complete

**Total Tests**: 84 (3 protocols × 4 resolutions × 7 connection levels)
**Estimated Time**: 21 hours max

---

## Implementation

### Command-Line Usage

```bash
# Automatic detection (checks CPU/RAM, suggests profile)
./run_orchestration.sh --test-matrix

# Manual profile selection
./run_orchestration.sh --test-matrix --profile small
./run_orchestration.sh --test-matrix --profile medium
./run_orchestration.sh --test-matrix --profile large
./run_orchestration.sh --test-matrix --profile enterprise

# Custom connection levels
./run_orchestration.sh --test-matrix --connections "1,5,10,20"
```

### Profile Auto-Detection

```bash
function detect_hardware_profile() {
  local cpu_cores=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo "4")
  local ram_gb=$(free -g | awk '/^Mem:/{print $2}' 2>/dev/null || echo "8")
  
  log "Detected hardware: ${cpu_cores} cores, ${ram_gb}GB RAM"
  
  if (( cpu_cores >= 32 && ram_gb >= 64 )); then
    echo "enterprise"
  elif (( cpu_cores >= 16 && ram_gb >= 32 )); then
    echo "large"
  elif (( cpu_cores >= 8 && ram_gb >= 16 )); then
    echo "medium"
  else
    echo "small"
  fi
}
```

## Benefits of Hardware Profiles

### 1. **Faster Testing on Limited Hardware**
- Small system skips unrealistic connection counts
- Saves 6-10 hours on lower-end systems
- Still gets valuable capacity data

### 2. **Realistic Expectations**
- Profile matches hardware capabilities
- Users see expected behavior
- Reduces "test fatigue" from watching failures

### 3. **Consistent Methodology**
- Same test approach across all systems
- Only connection levels vary
- Easy to compare results

### 4. **Future Scalability**
- Add new profiles easily
- Custom connection levels supported
- Works with upgraded hardware

## Recommendations

### For Your Current Setup (4 cores, 8GB)

**Option A**: Use `small` profile
```bash
./run_orchestration.sh --test-matrix --profile small
# Tests: 1, 5, 10, 20 connections
# Time: ~6-8 hours
# Result: Realistic capacity data
```

**Option B**: Use default with adaptive stopping (RECOMMENDED)
```bash
./run_orchestration.sh --test-matrix
# Tests: 1, 5, 10, 20, 50, 100 connections
# Time: ~8-10 hours (stops early on higher resolutions)
# Result: Discovers exact limits, more data points
```

### Why Option B is Better

1. **Discovers Actual Limits**: Might surprise you - could handle 50x 360p streams
2. **More Data Points**: Extra connection levels provide granular capacity curve
3. **Minimal Time Waste**: Adaptive stopping means 50/100 tests only run if feasible
4. **Documentation**: Logs show "attempted 50, stopped at CPU 82%" vs "didn't try 50"

### For Future Upgraded System

Simply re-run the same command:
```bash
./run_orchestration.sh --test-matrix
# Same test matrix, better hardware, more completions
```

## Profile Comparison

| Profile | Connections | Tests | Est. Time | Best For |
|---------|-------------|-------|-----------|----------|
| Small | 1,5,10,20 | 48 | 6-8h | 4-core, 8GB |
| Medium | 1,5,10,20,50 | 60 | 10-12h | 8-core, 16GB |
| Large | 1,5,10,20,50,100 | 72 | 12-15h | 16-core, 32GB |
| Enterprise | 1,5,10,20,50,100,200 | 84 | 15-18h | 32-core, 64GB+ |

## Custom Scenarios

### Testing Specific Ranges
```bash
# Low-end capacity testing
./run_orchestration.sh --test-matrix --connections "1,2,5,10,15,20"

# High-end stress testing
./run_orchestration.sh --test-matrix --connections "50,100,150,200,250,300"

# Logarithmic scaling
./run_orchestration.sh --test-matrix --connections "1,5,25,125"
```

### Resolution-Specific Testing
```bash
# Only test low resolutions on small system
./run_orchestration.sh --test-matrix --resolutions "360p,720p" --connections "1,5,10,20,50"

# Only 4K on high-end system
./run_orchestration.sh --test-matrix --resolutions "4k" --connections "1,5,10,20,50,100,200"
```

---

## Conclusion

**For your 4-core/8GB system:**

✅ **BEST APPROACH**: Keep the full connection array (1,5,10,20,50,100)
- Let adaptive stopping do its job
- Discover actual limits
- Get maximum useful data
- Same matrix works when you upgrade

⚠️ **ALTERNATIVE**: Use small profile (1,5,10,20)
- Saves some time upfront
- Might miss capacity at higher connection counts
- Need to re-test with different matrix later

The adaptive stopping feature is **designed exactly for this scenario** - testing across different hardware capabilities without wasting time on impossible tests.

---

**Last Updated**: October 17, 2025
