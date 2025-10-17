#!/usr/bin/env python3
"""
Simple parser for run directories produced by run_orchestration.sh

It parses pidstat.log, ifstat.log, jstat_gc.log and sar_cpu.log (if present) and writes/appends a results CSV
with basic aggregated metrics for the steady-state window.

Usage:
  python3 parse_run.py --run-dir <path> --run-id <id> --protocol rtmp --resolution 1080p --video-codec h264 --audio-codec aac --connections 10

"""
import argparse
import csv
import os
import re
from datetime import datetime, timezone

def parse_pidstat(path):
    # Return list of tuples (timestamp, pid, %cpu, mem_kb)
    results = []
    if not os.path.isfile(path):
        return results
    with open(path, 'r', errors='ignore') as f:
        for line in f:
            # pidstat -h output contains lines like:
            # 08:05:01      PID   %usr %system  %guest    %CPU   CPU  minflt/s  majflt/s     VSZ    RSS   %MEM  Command
            # We want to capture: timestamp, PID, %CPU (total), RSS
            parts = line.strip().split()
            if len(parts) >= 8 and re.match(r"^\d{2}:\d{2}:\d{2}$", parts[0]):
                try:
                    ts = parts[0]
                    pid = int(parts[1])
                    # Try to find %CPU column (usually column with just digits and decimal)
                    cpu_val = 0.0
                    rss_val = 0
                    
                    # Look for %CPU - typically after %system
                    for i in range(2, min(len(parts), 8)):
                        if re.match(r"^\d+\.\d+$", parts[i]):
                            cpu_val = float(parts[i])
                            break
                    
                    # Look for RSS (usually near end, large number)
                    for i in range(len(parts)-5, len(parts)):
                        if i > 0 and re.match(r"^\d{4,}$", parts[i]):
                            rss_val = int(parts[i])
                            break
                    
                    results.append((ts, pid, cpu_val, rss_val))
                except (ValueError, IndexError):
                    pass
    return results

def parse_ifstat(path):
    # Simple parsing: look for lines with timestamp and two numbers per iface
    tx_vals = []
    if not os.path.isfile(path):
        return tx_vals
    with open(path, 'r', errors='ignore') as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) >= 3 and re.match(r"^\d{2}:\d{2}:\d{2}$", parts[0]):
                # Gather numeric columns (likely rx tx pairs). We'll try to infer units later.
                nums = [p for p in parts[1:] if re.match(r"^[0-9.]+$", p)]
                for n in nums:
                    try:
                        tx_vals.append(float(n))
                    except:
                        pass
    return tx_vals

def parse_sar_cpu(path):
    vals = []
    if not os.path.isfile(path):
        return vals
    with open(path, 'r', errors='ignore') as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) >= 8 and re.match(r"^\d{2}:\d{2}:\d{2}$", parts[0]):
                # sar -u: %user %nice %system %iowait %steal %idle
                try:
                    user = float(parts[2])
                    system = float(parts[4])
                    idle = float(parts[-1])
                    cpu_used = 100.0 - idle
                    vals.append(cpu_used)
                except:
                    pass
    return vals

def parse_sar_net(path):
    """Parse sar -n DEV output for network interface stats"""
    tx_vals = []
    if not os.path.isfile(path):
        return tx_vals
    
    with open(path, 'r', errors='ignore') as f:
        for line in f:
            parts = line.strip().split()
            # Look for lines with timestamp and interface name (excluding lo)
            # Format: HH:MM:SS  IFACE  rxpck/s  txpck/s  rxkB/s  txkB/s ...
            if len(parts) >= 6 and re.match(r"^\d{2}:\d{2}:\d{2}$", parts[0]):
                iface = parts[1]
                if iface not in ['lo', 'IFACE']:  # Skip loopback and header
                    try:
                        # txkB/s is typically column 5 (0-indexed: parts[5])
                        tx_kbps = float(parts[5])
                        tx_vals.append(tx_kbps)
                    except (ValueError, IndexError):
                        pass
    return tx_vals

def parse_jstat_gc(path):
    """Parse jstat -gc output for Java heap statistics
    
    jstat -gc output columns (approximate):
    Timestamp S0C S1C S0U S1U EC EU OC OU MC MU CCSC CCSU YGC YGCT FGC FGCT CGC CGCT GCT
    
    We'll extract:
    - EU (Eden Used) + OU (Old Gen Used) = Total heap used
    - EC (Eden Capacity) + OC (Old Gen Capacity) = Total heap capacity
    """
    heap_used_vals = []
    heap_capacity_vals = []
    
    if not os.path.isfile(path):
        return heap_used_vals, heap_capacity_vals
    
    with open(path, 'r', errors='ignore') as f:
        lines = f.readlines()
        
        # First line is typically the header
        header_idx = -1
        for i, line in enumerate(lines):
            if 'S0C' in line and 'S1C' in line:
                header_idx = i
                break
        
        if header_idx == -1:
            return heap_used_vals, heap_capacity_vals
        
        # Parse data lines after header
        for line in lines[header_idx+1:]:
            parts = line.strip().split()
            if len(parts) >= 11:  # Need at least timestamp + 10 heap columns
                try:
                    # Skip timestamp (parts[0])
                    # S0C, S1C, S0U, S1U, EC, EU, OC, OU, MC, MU, ...
                    # Indices: 1   2    3    4    5   6   7   8   9   10
                    ec = float(parts[5])  # Eden Capacity (KB)
                    eu = float(parts[6])  # Eden Used (KB)
                    oc = float(parts[7])  # Old Gen Capacity (KB)
                    ou = float(parts[8])  # Old Gen Used (KB)
                    
                    heap_capacity = ec + oc  # Total heap capacity (KB)
                    heap_used = eu + ou      # Total heap used (KB)
                    
                    heap_capacity_vals.append(heap_capacity)
                    heap_used_vals.append(heap_used)
                except (ValueError, IndexError):
                    pass
    
    return heap_used_vals, heap_capacity_vals

def parse_remote_monitor(path):
    """Parse remote_monitor.sh CSV output for heap statistics
    
    Format: TIMESTAMP,CPU_PCT,HEAP_USED_MB,HEAP_CAPACITY_MB,HEAP_PCT,MEM_PCT,NET_MBPS,WOWZA_PID
    
    Returns: (heap_used_mb_list, heap_capacity_mb_list)
    """
    heap_used_vals = []
    heap_capacity_vals = []
    
    if not os.path.isfile(path):
        return heap_used_vals, heap_capacity_vals
    
    with open(path, 'r', errors='ignore') as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                heap_used = row.get('HEAP_USED_MB', '').strip()
                heap_capacity = row.get('HEAP_CAPACITY_MB', '').strip()
                
                # Skip N/A values
                if heap_used and heap_used != 'N/A' and heap_capacity and heap_capacity != 'N/A':
                    heap_used_vals.append(float(heap_used))
                    heap_capacity_vals.append(float(heap_capacity))
            except (ValueError, KeyError):
                pass
    
    return heap_used_vals, heap_capacity_vals

def aggregate(vals):
    if not vals:
        return 0.0, 0.0
    return sum(vals)/len(vals), max(vals)

def kbps_to_mbps(x):
    # if x is in KB/s or kB/s we try to convert heuristically; user should verify units
    # assume x in KB/s -> KB/s * 8 / 1000 = Mbps approx
    try:
        return (float(x) * 8.0) / 1000.0
    except:
        return 0.0

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--run-dir', required=True)
    p.add_argument('--run-id', required=True)
    p.add_argument('--protocol', required=True)
    p.add_argument('--resolution', required=True)
    p.add_argument('--video-codec', required=True)
    p.add_argument('--audio-codec', required=True)
    p.add_argument('--connections', required=True, type=int)
    p.add_argument('--wowza-pid', required=False)
    args = p.parse_args()

    run_dir = args.run_dir
    server_logs = os.path.join(run_dir, 'server_logs')

    pidstat_path = os.path.join(server_logs, 'pidstat.log')
    ifstat_path = os.path.join(server_logs, 'ifstat.log')
    sar_path = os.path.join(server_logs, 'sar_cpu.log')
    sar_net_path = os.path.join(server_logs, 'sar_net.log')
    jstat_gc_path = os.path.join(server_logs, 'jstat_gc.log')
    
    # Check for remote_monitor.sh CSV files in monitors/ subdirectory
    remote_monitor_paths = []
    monitors_dir = os.path.join(server_logs, 'monitors')
    if os.path.isdir(monitors_dir):
        for fname in os.listdir(monitors_dir):
            if fname.startswith('monitor_') and fname.endswith('.log'):
                remote_monitor_paths.append(os.path.join(monitors_dir, fname))

    pidstat = parse_pidstat(pidstat_path)
    # If wowza PID provided, filter pidstat entries to that pid
    if getattr(args, 'wowza_pid', None):
        try:
            wpid = int(args.wowza_pid)
            pidstat = [t for t in pidstat if t[1] == wpid]
        except Exception:
            pass
    
    ifstat = parse_ifstat(ifstat_path)
    sar = parse_sar_cpu(sar_path)
    sar_net = parse_sar_net(sar_net_path)
    
    # Try to get heap data from remote_monitor.sh first (preferred), then jstat_gc.log (fallback)
    jstat_heap_used = []
    jstat_heap_capacity = []
    
    if remote_monitor_paths:
        # Parse all remote monitor CSV files and combine results
        for rmon_path in remote_monitor_paths:
            used, capacity = parse_remote_monitor(rmon_path)
            jstat_heap_used.extend(used)
            jstat_heap_capacity.extend(capacity)
    
    # Fallback to jstat_gc.log if remote monitor didn't provide data
    if not jstat_heap_used and os.path.isfile(jstat_gc_path):
        jstat_heap_used, jstat_heap_capacity = parse_jstat_gc(jstat_gc_path)
        # jstat_gc returns KB, convert to MB for consistency
        jstat_heap_used = [x / 1024 for x in jstat_heap_used]
        jstat_heap_capacity = [x / 1024 for x in jstat_heap_capacity]

    # Simple aggregates - pidstat now includes RSS in tuple[3]
    pidstat_cpus = [x[2] for x in pidstat]
    pidstat_mem = [x[3] for x in pidstat if x[3] > 0]
    
    # Note: We no longer calculate avg_pid_cpu or max_pid_cpu
    avg_pid_mem, max_pid_mem = aggregate(pidstat_mem)
    
    # Java heap statistics (now in MB from remote_monitor, or converted from jstat KB)
    avg_heap_used_mb, max_heap_used_mb = aggregate(jstat_heap_used)
    avg_heap_capacity_mb, max_heap_capacity_mb = aggregate(jstat_heap_capacity)
    
    # Network: try sar_net first, then ifstat
    if sar_net:
        avg_net_tx_kbps, max_net_tx_kbps = aggregate(sar_net)
        avg_if_tx_mbps = kbps_to_mbps(avg_net_tx_kbps)
        max_if_tx_mbps = kbps_to_mbps(max_net_tx_kbps)
    else:
        avg_if_val, max_if_val = aggregate(ifstat)
        avg_if_tx_mbps = kbps_to_mbps(avg_if_val)
        max_if_tx_mbps = kbps_to_mbps(max_if_val)

    avg_sar_cpu, max_sar_cpu = aggregate(sar)

    # Per-stream derived metrics
    cpu_per_stream = 0.0
    mem_rss_kb = None
    heap_used_mb = None
    heap_capacity_mb = None
    
    if args.connections and args.connections > 0:
        cpu_per_stream = (avg_sar_cpu / float(args.connections)) if avg_sar_cpu else 0.0
    
    # Use Java heap statistics if available (now in MB)
    if avg_heap_used_mb > 0:
        heap_used_mb = int(avg_heap_used_mb)
    if avg_heap_capacity_mb > 0:
        heap_capacity_mb = int(avg_heap_capacity_mb)
    
    # Try to get memory from pidstat first, then fall back to wowza_proc.txt
    if avg_pid_mem > 0:
        mem_rss_kb = int(avg_pid_mem)
    else:
        # Try to read wowza_proc.txt for RSS (remote captured snapshot)
        wowza_proc = os.path.join(server_logs, 'wowza_proc.txt')
        if os.path.isfile(wowza_proc):
            try:
                with open(wowza_proc, 'r') as wf:
                    line = wf.read().strip()
                    parts = line.split()
                    # ps -p pid -o pid,rss,vsz,pmem,pcpu,cmd -> pid rss vsz pmem pcpu cmd
                    if len(parts) >= 2:
                        mem_rss_kb = int(parts[1])
            except Exception:
                mem_rss_kb = None

    # results CSV
    results_csv = os.path.join(run_dir, '..', 'results.csv')
    header = [
        'run_id','timestamp','protocol','resolution','video_codec','audio_codec','connections',
        'avg_sys_cpu_percent','max_sys_cpu_percent',
        'cpu_per_stream_percent','mem_rss_kb','heap_used_mb','heap_capacity_mb'
    ]

    timestamp = datetime.now(timezone.utc).isoformat()
    row = [
        args.run_id,
        timestamp,
        args.protocol,
        args.resolution,
        args.video_codec,
        args.audio_codec,
        args.connections,
        f"{avg_sar_cpu:.2f}",
        f"{max_sar_cpu:.2f}",
        f"{cpu_per_stream:.4f}",
        f"{mem_rss_kb if mem_rss_kb is not None else ''}",
        f"{heap_used_mb if heap_used_mb is not None else ''}",
        f"{heap_capacity_mb if heap_capacity_mb is not None else ''}"
    ]

    write_header = not os.path.isfile(results_csv)
    with open(results_csv, 'a', newline='') as f:
        w = csv.writer(f)
        if write_header:
            w.writerow(header)
        w.writerow(row)

    print('Parsed results written to', results_csv)

if __name__ == '__main__':
    main()
