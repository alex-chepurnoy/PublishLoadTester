# Documentation Structure

This document outlines the organization of all documentation in the PublishLoadTester project.

## Root Level

### Main Entry Points
- **README.md** - Project overview, quick start guide, main documentation hub
- **DOCUMENTATION_STRUCTURE.md** - This file - documentation organization guide

### Setup Scripts
- **setup_sudo.sh** - Configure passwordless sudo for Java monitoring tools

---

## Root Docs (`docs/`)

Main project-level documentation.

### Core Documentation
- **README.md** - Docs overview
- **CHANGELOG.md** - Detailed project changelog
- **CHANGES_SUMMARY.md** - High-level summary of recent changes

### Fixes (`docs/fixes/`)
Historical fixes and patches applied to the project:
- **CPU_CHECK_FIX.md** - CPU detection and validation fixes
- **H264_WOWZA_FIX.md** - H264 codec compatibility fix for Wowza
- **ORCHESTRATOR_HANG_FIX.md** - Fix for orchestrator hanging during tests
- **ORCHESTRATOR_FIXES.md** - Detailed orchestrator fix documentation
- **ORCHESTRATOR_FIXES_SUMMARY.md** - Summary of all orchestrator fixes
- **SSH_WARNING_FIX.md** - SSH warning suppression (legacy)
- **TIMEOUT_REGRESSION_FIX.md** - Timeout regression fixes
- **WOWZA_FIX_SUMMARY.md** - Summary of Wowza-specific fixes

### Guides (`docs/guides/`)
User guides and how-tos:
- **JAVA_HEAP_MONITORING.md** - Java heap monitoring setup and usage
- **PYTHON_AUTO_INSTALL.md** - Automatic Python dependency installation
- **SAVED_CONFIGS_GUIDE.md** - Using saved test configurations
- **SCRIPT_PERMISSIONS.md** - Setting up script execution permissions

---

## Orchestrator Documentation (`orchestrator/docs/`)

Core load testing orchestrator documentation.

### Main Documentation
- **README.md** - Orchestrator overview, usage, and architecture
- **SETUP_REQUIREMENTS.md** - Python dependencies and setup
- **TEST_MATRIX.md** - Comprehensive test matrix planning (Phase 1+)
- **PILOT_MODE.md** - Single-connection pilot testing mode

### Architecture & Design
- **CLIENT_SERVER_STRATEGY.md** - Client/server architecture design
- **DATA_ANALYSIS.md** - How test data is collected and analyzed
- **HARDWARE_PROFILES.md** - EC2 and hardware configuration profiles
- **IMPLEMENTATION_PLAN.md** - Overall implementation roadmap
- **IMPLEMENTATION_SUMMARY.md** - Summary of implementation decisions
- **PYTHON_CHECK_STATUS.md** - Python dependency checking implementation
- **PYTHON_DEPENDENCY_FLOW.md** - Python dependency flow and installation
- **REVIEW.md** - Code review and design decisions

### Phase 0 (`orchestrator/docs/phase0/`)
Phase 0 monitoring infrastructure documentation:
- **PHASE_0_CHECKLIST.md** - Phase 0 implementation checklist
- **PHASE_0_COMPLETE.md** - Phase 0 completion status
- **PHASE_0_DONE.md** - Phase 0 finalization and sign-off
- **PHASE_0_IMPLEMENTATION_SUMMARY.md** - Implementation details
- **PHASE_0_QUICKREF.md** - Quick reference for Phase 0 features
- **PHASE_0_SUMMARY.md** - Phase 0 overview and goals
- **PHASE_0_TESTING_GUIDE.md** - Testing guide for Phase 0
- **READY_TO_TEST.md** - Pre-testing validation checklist

### Fixes (`orchestrator/docs/fixes/`)
Orchestrator-specific fixes and enhancements:
- **FIXES_SUMMARY.md** - Summary of orchestrator fixes
- **HEAP_MB_LOGGING_FIX.md** - Fixed heap logging to use MB instead of percentage
- **SSH_WARNING_SUPPRESSION.md** - SSH warning suppression implementation
- **SUDO_SUPPORT_SUMMARY.md** - Passwordless sudo implementation summary
- **WOWZA_ENGINE_PID_FIX.md** - Fixed PID detection (Manager vs Engine process)
- **WOWZA_JAVA_PATH_FIX.md** - Java tools path detection for Wowza's bundled JDK
- **ZGC_G1GC_SUPPORT.md** - Multi-GC support (Parallel, G1, ZGC, Shenandoah)

### Troubleshooting (`orchestrator/docs/troubleshooting/`)
Troubleshooting guides and common issues:
- **JCMD_TROUBLESHOOTING.md** - Complete jcmd troubleshooting guide
- **JCMD_VS_JSTAT.md** - jcmd vs jstat comparison and usage
- **SUDO_QUICKSTART.md** - Quick sudo setup guide
- **SUDO_SETUP_GUIDE.md** - Complete sudo configuration guide

---

## Navigation Guide

### Getting Started
1. **README.md** (root) - Start here for project overview
2. **orchestrator/docs/README.md** - Orchestrator architecture and usage
3. **orchestrator/docs/SETUP_REQUIREMENTS.md** - Setup dependencies

### Running Tests
1. **orchestrator/docs/PILOT_MODE.md** - Run single-connection tests
2. **docs/guides/SAVED_CONFIGS_GUIDE.md** - Use pre-configured tests
3. **orchestrator/docs/TEST_MATRIX.md** - Plan comprehensive test matrix

### Phase 0 Monitoring
1. **orchestrator/docs/phase0/PHASE_0_QUICKREF.md** - Quick reference
2. **orchestrator/docs/phase0/READY_TO_TEST.md** - Pre-flight checks
3. **orchestrator/docs/phase0/PHASE_0_TESTING_GUIDE.md** - Testing guide

### Troubleshooting
1. **orchestrator/docs/troubleshooting/JCMD_TROUBLESHOOTING.md** - Java monitoring issues
2. **orchestrator/docs/troubleshooting/SUDO_SETUP_GUIDE.md** - Sudo configuration
3. **docs/fixes/** - Browse historical fixes

### Latest Enhancements (Phase 0)
- **orchestrator/docs/fixes/HEAP_MB_LOGGING_FIX.md** - Heap logging in MB
- **orchestrator/docs/fixes/WOWZA_ENGINE_PID_FIX.md** - Correct process monitoring
- **orchestrator/docs/fixes/ZGC_G1GC_SUPPORT.md** - Multi-GC collector support

---

## Documentation Conventions

### File Naming
- `README.md` - Overview/index files
- `*_GUIDE.md` - User guides and how-tos
- `*_FIX.md` - Problem/solution documentation
- `*_SUMMARY.md` - Summaries of larger topics
- `PHASE_*` - Phase-specific documentation

### Content Standards
- All documentation uses Markdown format
- Code examples include language hints (```bash, ```python, etc.)
- File paths use forward slashes for cross-platform compatibility
- Commands show both input and expected output when relevant
- Each doc includes a "Summary" or "TL;DR" section at the top

### Organization Principles
- **Root**: Main README and project-wide references
- **docs/**: Project-level documentation, guides, historical fixes
- **orchestrator/docs/**: Orchestrator-specific architecture, implementation, and Phase 0
- **Subdirectories**: Group related docs (fixes/, guides/, phase0/, troubleshooting/)

---

## Quick Reference by Topic

| Topic | Documentation |
|-------|--------------|
| **Getting Started** | README.md |
| **Setup** | orchestrator/docs/SETUP_REQUIREMENTS.md |
| **Pilot Testing** | orchestrator/docs/PILOT_MODE.md |
| **Phase 0 Monitoring** | orchestrator/docs/phase0/PHASE_0_QUICKREF.md |
| **Java Monitoring** | orchestrator/docs/troubleshooting/JCMD_TROUBLESHOOTING.md |
| **Sudo Setup** | orchestrator/docs/troubleshooting/SUDO_SETUP_GUIDE.md |
| **Test Matrix** | orchestrator/docs/TEST_MATRIX.md |
| **Configuration** | docs/guides/SAVED_CONFIGS_GUIDE.md |
| **Troubleshooting** | orchestrator/docs/troubleshooting/ |
| **Latest Fixes** | orchestrator/docs/fixes/ |
| **Changelog** | docs/CHANGELOG.md |
