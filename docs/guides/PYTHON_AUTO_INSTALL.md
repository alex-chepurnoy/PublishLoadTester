# Python Auto-Install Feature

## Overview

The workspace now includes **automatic Python3 installation** with smart dependency checking throughout the toolchain.

---

## ✅ What Was Added

### 1. **Dependency Checker (`scripts/check_dependencies.sh`)**

**New Function: `check_python()`**
```bash
check_python() {
    echo -e "${BLUE}Checking Python3...${NC}"
    
    if command -v python3 >/dev/null 2>&1; then
        local version=$(python3 --version 2>&1)
        print_status "Python3" "OK" "$version"
    else
        print_status "Python3" "ERROR" "Not installed (required for orchestrator)"
        BASIC_DEPS_OK=false
        BASIC_FAILURES+=("Python3: Not installed (required for result parsing)")
        echo -e "${YELLOW}    Required for: Orchestrator result parsing and CSV generation${NC}"
        echo -e "${YELLOW}    Fix: Run ./scripts/install.sh --yes${NC}"
    fi
}
```

**Behavior:**
- ✅ Checks if `python3` command exists
- ✅ Shows version if installed
- ✅ Reports as ERROR if missing
- ✅ Provides fix command
- ✅ Integrated into main dependency check flow

---

### 2. **Installation Script (`scripts/install.sh`)**

**New Function: `install_python()`**
```bash
install_python() {
    # Checks if Python3 installed
    # Auto-detects OS (Ubuntu/Debian/Fedora/Arch/macOS)
    # Installs via package manager
    # Verifies installation success
}
```

**Supported Platforms:**
- ✅ Ubuntu/Debian → `apt-get install python3`
- ✅ Fedora/RHEL/CentOS → `dnf install python3` or `yum install python3`
- ✅ Arch/Manjaro → `pacman -S python`
- ✅ macOS → `brew install python3` (requires Homebrew)
- ⚠️ Windows → Use WSL (detected and reported)

**Interactive Mode:**
```bash
./scripts/install.sh
```
- Asks: "Install Python3? (Y/n)"
- User can skip if needed

**Non-Interactive Mode:**
```bash
./scripts/install.sh --yes
```
- Installs automatically without prompts
- Perfect for CI/CD pipelines

---

### 3. **Orchestrator (`orchestrator/run_orchestration.sh`)**

**New Startup Flow:**
```bash
# 1. Check dependencies at startup
if ! check_dependencies.sh >/dev/null 2>&1; then
  
  # 2. Offer auto-install
  read -p "Run automatic installation? (Y/n): "
  
  # 3. Run install.sh --yes
  ./scripts/install.sh --yes
  
  # 4. Re-check dependencies
  if ! check_dependencies.sh >/dev/null 2>&1; then
    warn "Some dependencies still missing"
  fi
fi
```

**User Experience:**
```
--- Stream Load Orchestrator ---
Checking local dependencies (Bash, Python3, FFmpeg)...
Some dependencies are missing or incomplete.

The orchestrator requires:
  - Python3 (for result parsing and CSV generation)
  - FFmpeg (for stream generation)

Run automatic installation? (Y/n): y
Running automatic installation...
Installing Python3...
Python3 installed successfully: Python 3.10.12
✓ All local dependencies verified
```

---

## 🎯 Use Cases

### Use Case 1: First-Time User

**Scenario:** User clones repo, runs orchestrator for first time

**Before (Old Behavior):**
```bash
./orchestrator/run_orchestration.sh
# Tests run, but CSV not generated
# User confused why no results
```

**After (New Behavior):**
```bash
./orchestrator/run_orchestration.sh
# "Python3 not found. Run automatic installation? (Y/n): y"
# Python installs automatically
# Everything works!
```

---

### Use Case 2: CI/CD Pipeline

**Scenario:** Automated testing in GitHub Actions / Jenkins

**Solution:**
```bash
# .github/workflows/test.yml
- name: Install dependencies
  run: ./scripts/install.sh --yes

- name: Run orchestrator
  run: ./orchestrator/run_orchestration.sh
```

**Benefits:**
- ✅ No manual steps
- ✅ No interactive prompts
- ✅ Idempotent (safe to run multiple times)
- ✅ Fast (skips if already installed)

---

### Use Case 3: Developer Machine

**Scenario:** Developer wants to check what's missing

**Solution:**
```bash
./scripts/check_dependencies.sh
```

**Output:**
```
=== Checking Dependencies ===

Checking Bash...
  ✓ Bash: Version 5.0.17

Checking Python3...
  ✗ Python3: Not installed (required for orchestrator)
    Required for: Orchestrator result parsing and CSV generation
    Fix: Run ./scripts/install.sh --yes

Checking FFmpeg...
  ✓ FFmpeg: ffmpeg version 4.4.2

✗ Dependencies check failed

To fix missing dependencies, run:
  ./scripts/ensure_ffmpeg_requirements.sh
```

---

## 📊 Comparison: Before vs After

| Aspect | Before | After |
|--------|--------|-------|
| **Detection** | Silent failure | Explicit check at startup |
| **User Guidance** | Generic error | Clear installation offer |
| **Installation** | Manual only | Automatic with confirmation |
| **CI/CD Support** | Manual setup | `--yes` flag for automation |
| **Error Messages** | "python3 not found" | "Run automatic installation?" |
| **Documentation** | Scattered | Comprehensive guide |
| **User Experience** | Frustrating | Smooth |

---

## 🔧 Technical Details

### Dependency Check Integration

The orchestrator now calls `check_dependencies.sh` which checks:
1. ✅ Bash 4.0+
2. ✅ Python3 (NEW)
3. ✅ FFmpeg with H.264/AAC encoders
4. ✅ FFmpeg with H.265/Opus (optional)
5. ✅ Basic system tools (grep, awk, etc.)
6. ✅ System resources (disk, CPU)

### Installation Priority

```bash
install.sh --yes
├── Make scripts executable
├── Install Python3 ← NEW (if missing)
├── Install FFmpeg (if missing)
└── Verify installation
```

### Idempotency

All scripts are safe to run multiple times:
- `check_dependencies.sh` - Always safe, reports status
- `install.sh` - Skips if already installed
- Orchestrator - Checks before every run

---

## 🧪 Testing

### Test 1: Fresh System (Python Missing)
```bash
# Simulate fresh system
docker run -it ubuntu:22.04 bash
git clone <repo>
cd PublishLoadTester

# Should auto-install Python
./orchestrator/run_orchestration.sh
```

**Expected:** Python installs automatically, orchestrator runs

---

### Test 2: Python Already Installed
```bash
# Verify no duplicate installation
python3 --version  # Already installed

./scripts/install.sh --yes
```

**Expected:** "Python3 already installed: Python 3.10.12" (skips install)

---

### Test 3: Non-Interactive Installation
```bash
# CI/CD mode
./scripts/install.sh --yes
echo $?  # Should be 0
```

**Expected:** Installs without prompts, exits 0

---

### Test 4: Dependency Check Only
```bash
./scripts/check_dependencies.sh
```

**Expected:** Shows all dependencies with status, exits 0 if all met

---

## 📚 Documentation Updates

**New Files:**
- `PYTHON_AUTO_INSTALL.md` (this file)
- `orchestrator/SETUP_REQUIREMENTS.md` (comprehensive guide)

**Updated Files:**
- `scripts/check_dependencies.sh` (added Python check)
- `scripts/install.sh` (added Python install)
- `orchestrator/run_orchestration.sh` (integrated auto-install)
- `orchestrator/PYTHON_CHECK_STATUS.md` (updated with auto-install info)

---

## 🚀 Migration Guide

### For Existing Users

**No action required!** The changes are backward compatible:
- Existing Python3 installations detected automatically
- No re-installation needed
- Scripts work as before

**To verify your setup:**
```bash
./scripts/check_dependencies.sh
```

**To ensure everything is optimal:**
```bash
./scripts/install.sh --yes
```

---

### For New Users

**Quickstart (Recommended):**
```bash
git clone <repo>
cd PublishLoadTester
./orchestrator/run_orchestration.sh
# Answer 'y' to auto-install dependencies
```

**Or pre-install everything:**
```bash
git clone <repo>
cd PublishLoadTester
./scripts/install.sh --yes
./orchestrator/run_orchestration.sh
```

---

## 🎓 Best Practices

### For Interactive Use
```bash
# Let orchestrator handle everything
./orchestrator/run_orchestration.sh
```

### For Automation/Scripts
```bash
# Pre-install dependencies
./scripts/install.sh --yes

# Run orchestrator (no prompts)
./orchestrator/run_orchestration.sh
```

### For Development
```bash
# Check what's missing first
./scripts/check_dependencies.sh

# Install only what's needed
./scripts/install.sh --yes
```

---

## ❓ FAQ

**Q: Will this break my existing Python installation?**  
A: No. It uses system package managers which handle upgrades safely.

**Q: Can I skip Python installation?**  
A: Yes. When prompted, answer 'n'. Tests will run but CSV won't be generated.

**Q: Does this work on Windows?**  
A: Use WSL (Windows Subsystem for Linux). The script detects Windows and shows instructions.

**Q: What if I have Python 2?**  
A: The script specifically installs `python3` (Python 3.x).

**Q: Can I use a virtual environment?**  
A: Yes! If `python3` is available in your PATH (from venv), it will be detected.

**Q: What about Python packages/dependencies?**  
A: The orchestrator only uses Python standard library (no pip packages needed).

---

## 🎉 Benefits Summary

✅ **Zero Manual Setup** - Everything installs automatically  
✅ **Smart Detection** - Only installs what's missing  
✅ **Clear Feedback** - User always knows what's happening  
✅ **CI/CD Ready** - `--yes` flag for automation  
✅ **Cross-Platform** - Works on Ubuntu/Debian/Fedora/Arch/macOS  
✅ **Idempotent** - Safe to run multiple times  
✅ **Well-Documented** - Comprehensive guides included  

**The orchestrator is now production-ready with minimal user effort!** 🚀
