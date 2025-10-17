# Quick Reference: Fixing jcmd Permissions

## The Problem
```
Error: Unable to open socket file: target process not responding
```
→ jcmd needs same user as Wowza process

---

## The Solution (2 minutes)

### On Your Server:
```bash
# Copy script
scp -i key.pem setup_sudo.sh ubuntu@server-ip:~/

# Run it
ssh -i key.pem ubuntu@server-ip
chmod +x setup_sudo.sh
./setup_sudo.sh ubuntu
```

### From Your Client:
```bash
# Test it works
./orchestrator/diagnose_jcmd.sh <server-ip> <key> ubuntu

# Run pilot
./orchestrator/run_orchestration.sh --pilot
```

---

## What It Does

Creates `/etc/sudoers.d/java-monitoring` allowing:
- `sudo jcmd` - Read heap info
- `sudo jstat` - Get GC stats
- `sudo jmap` - Emergency fallback

**No password required** for these commands.

---

## Scripts Now Automatically Try:

1. Regular jcmd
2. Wowza's jcmd
3. **sudo jcmd** ← NEW
4. **sudo wowza jcmd** ← NEW
5. Fallback to jstat (same pattern)

---

## Security

✅ Only allows jcmd/jstat/jmap  
✅ Read-only operations  
✅ Logged in /var/log/auth.log  
✅ Easy to revoke: `sudo rm /etc/sudoers.d/java-monitoring`

---

## Docs

- **SUDO_SETUP_GUIDE.md** - Detailed setup and security
- **SUDO_SUPPORT_SUMMARY.md** - What changed and why
- **JCMD_TROUBLESHOOTING.md** - All jcmd issues and fixes

---

## Status

✅ Scripts updated  
✅ Setup script ready  
⏳ **YOU NEED TO**: Run setup_sudo.sh on server  
⏳ **THEN TEST**: Run pilot mode
