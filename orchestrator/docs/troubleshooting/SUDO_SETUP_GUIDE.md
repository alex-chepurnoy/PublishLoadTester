# Passwordless Sudo Setup for Java Monitoring

## Overview

Since `jcmd`, `jstat`, and `jmap` require running as the same user that owns the Java process, we need to configure passwordless sudo to allow the monitoring scripts to work.

---

## Option 1: Configure Passwordless Sudo (RECOMMENDED)

This allows your SSH user to run Java monitoring tools without a password prompt.

### Step 1: SSH to your server

```bash
ssh -i your-key.pem ubuntu@your-server-ip
```

### Step 2: Create sudoers configuration

```bash
# Create a new sudoers file for Java monitoring
sudo visudo -f /etc/sudoers.d/java-monitoring
```

### Step 3: Add these lines

Replace `ubuntu` with your actual SSH username:

```sudoers
# Allow ubuntu user to run Java monitoring tools without password
ubuntu ALL=(ALL) NOPASSWD: /usr/bin/jcmd
ubuntu ALL=(ALL) NOPASSWD: /usr/bin/jstat
ubuntu ALL=(ALL) NOPASSWD: /usr/bin/jmap
ubuntu ALL=(ALL) NOPASSWD: /usr/local/WowzaStreamingEngine/java/bin/jcmd
ubuntu ALL=(ALL) NOPASSWD: /usr/local/WowzaStreamingEngine/java/bin/jstat
ubuntu ALL=(ALL) NOPASSWD: /usr/local/WowzaStreamingEngine/java/bin/jmap
```

### Step 4: Save and verify

```bash
# Verify syntax (should show no errors)
sudo visudo -c -f /etc/sudoers.d/java-monitoring

# Test it works
sudo jcmd
```

### Step 5: Test from orchestrator

```bash
# From your client machine
./orchestrator/diagnose_jcmd.sh <server-ip> <key> <user>
```

---

## Option 2: Run Wowza as SSH User (NOT RECOMMENDED)

This changes which user runs Wowza - generally not recommended for production.

```bash
# Stop Wowza
sudo systemctl stop wowzastreamingengine

# Change ownership
sudo chown -R ubuntu:ubuntu /usr/local/WowzaStreamingEngine

# Restart as ubuntu user
# (depends on your Wowza setup)
```

---

## Option 3: Use the Same User for SSH

If Wowza runs as user `wowza`, configure SSH to allow that user:

```bash
# On server, as root or via sudo
sudo su

# Create SSH authorized_keys for wowza user
mkdir -p /home/wowza/.ssh
chmod 700 /home/wowza/.ssh

# Copy your public key
cp /home/ubuntu/.ssh/authorized_keys /home/wowza/.ssh/
chown -R wowza:wowza /home/wowza/.ssh
chmod 600 /home/wowza/.ssh/authorized_keys

# Allow wowza user SSH login (edit /etc/ssh/sshd_config if needed)
systemctl restart sshd
```

Then SSH as wowza:
```bash
ssh -i your-key.pem wowza@your-server-ip
```

And update your orchestrator config to use `wowza` as SSH_USER.

---

## Security Considerations

### Option 1 (Passwordless Sudo) - SAFEST
- ✅ Only grants access to specific Java tools
- ✅ No password needed (scripts can automate)
- ✅ Audit trail via sudo logs
- ✅ Can revoke easily
- ⚠️ User can monitor any Java process on system

### Option 2 (Run Wowza as SSH user)
- ⚠️ SSH user has full control of Wowza
- ⚠️ Security risk if SSH key compromised
- ⚠️ Not recommended for production
- ❌ Violates principle of least privilege

### Option 3 (SSH as Wowza user)
- ✅ Direct access, no sudo needed
- ⚠️ SSH user has full control of Wowza
- ⚠️ May need to allow shell for service account
- ⚠️ Audit trail shows actions as wowza user

**RECOMMENDATION**: Use Option 1 (passwordless sudo) for production systems.

---

## Verification

After setup, test with the diagnostic script:

```bash
./orchestrator/diagnose_jcmd.sh <server-ip> <key> <user>
```

Expected output:
```
3. Testing jcmd access with current user (ubuntu)...
Output:
----------------------------------------
PSYoungGen      total 76288K, used 45123K
ParOldGen       total 174592K, used 98234K
Metaspace       used 45678K, capacity 48576K
----------------------------------------

  ✓ SUCCESS! jcmd returned heap data

4. Testing AWK parsing...
  Total: 250880 KB, Used: 143357 KB
  Percentage: 57.14%
```

---

## Updated Scripts

The following scripts now automatically try `sudo` if regular commands fail:

1. **orchestrator/run_orchestration.sh** - `get_server_heap()` function
2. **orchestrator/remote_monitor.sh** - `get_heap()` function
3. **orchestrator/validate_server.sh** - heap monitoring tests

### Execution order:
1. Try `jcmd` from PATH
2. Try `jcmd` from Wowza's bin directory
3. Try `sudo jcmd` from PATH
4. Try `sudo jcmd` from Wowza's bin directory
5. Fallback to `jstat` (same pattern)
6. Fallback to `jmap` (emergency only)

---

## Troubleshooting

### "sudo: no tty present and no askpass program specified"

This means sudo requires a password. You need to set up passwordless sudo (Option 1 above).

### "sudo: jcmd: command not found"

The sudo environment doesn't have the PATH set. Use full path:

```sudoers
ubuntu ALL=(ALL) NOPASSWD: /usr/local/WowzaStreamingEngine/java/bin/jcmd
```

### Still not working?

Run the diagnostic:
```bash
./orchestrator/diagnose_jcmd.sh <server-ip> <key> <user>
```

Check the output for specific error messages.

---

## Quick Setup Script

Save this as `setup_sudo.sh` and run on your server:

```bash
#!/bin/bash
# Run this on the EC2 server as ubuntu user

USER="${1:-ubuntu}"

echo "Setting up passwordless sudo for Java monitoring..."
echo "User: $USER"

sudo tee /etc/sudoers.d/java-monitoring > /dev/null <<EOF
# Java monitoring tools - passwordless sudo
$USER ALL=(ALL) NOPASSWD: /usr/bin/jcmd
$USER ALL=(ALL) NOPASSWD: /usr/bin/jstat
$USER ALL=(ALL) NOPASSWD: /usr/bin/jmap
$USER ALL=(ALL) NOPASSWD: /usr/local/WowzaStreamingEngine/java/bin/jcmd
$USER ALL=(ALL) NOPASSWD: /usr/local/WowzaStreamingEngine/java/bin/jstat
$USER ALL=(ALL) NOPASSWD: /usr/local/WowzaStreamingEngine/java/bin/jmap
EOF

sudo chmod 440 /etc/sudoers.d/java-monitoring
sudo visudo -c -f /etc/sudoers.d/java-monitoring

if [ $? -eq 0 ]; then
  echo "✓ Setup complete!"
  echo "Testing sudo jcmd..."
  sudo jcmd > /dev/null 2>&1 && echo "✓ sudo jcmd works" || echo "✗ sudo jcmd failed"
else
  echo "✗ Setup failed - syntax error in sudoers file"
fi
```

Usage:
```bash
# Copy to server
scp -i key.pem setup_sudo.sh ubuntu@server-ip:~/

# SSH and run
ssh -i key.pem ubuntu@server-ip
chmod +x setup_sudo.sh
./setup_sudo.sh ubuntu
```

---

**Status**: Scripts updated to use sudo. Server configuration required (Option 1 recommended).
