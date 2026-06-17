---
name: network-monitor
description: Check network status, connectivity, IP info, and manage network settings
version: 1.0
author: Agentic Windows
---

# Network Monitor

## Description
Shows current network configuration, tests connectivity, manages DNS, and provides network diagnostics. Useful for troubleshooting connectivity issues.

## Triggers
- "Check my network"
- "Show my IP address"
- "Network status"
- "Run network-monitor"
- "Flush DNS"
- "Test internet connection"
- "What's my IP?"

## Steps

1. **Show Network Adapters**
   ```powershell
   Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | ForEach-Object {
     "$($_.Name): $($_.LinkSpeed), MAC: $($_.MacAddress)"
   }
   ```

2. **Show IP Configuration**
   ```powershell
   $ip = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch "Loopback|Teredo|isatap" }
   $ip | ForEach-Object {
     "$($_.InterfaceAlias): $($_.IPAddress)/$($_.PrefixLength)"
   }
   ```

3. **Show Default Gateway**
   ```powershell
   Get-NetRoute -DestinationPrefix "0.0.0.0/0" | ForEach-Object {
     "Gateway: $($_.NextHop) via $($_.InterfaceAlias)"
   }
   ```

4. **Show DNS Servers**
   ```powershell
   Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object { $_.ServerAddresses } |
   ForEach-Object { "$($_.InterfaceAlias): $($_.ServerAddresses -join ', ')" }
   ```

5. **Test Internet Connectivity**
   ```powershell
   $tests = @(
     @{Host="8.8.8.8"; Label="Google DNS"},
     @{Host="1.1.1.1"; Label="Cloudflare"},
     @{Host="github.com"; Label="GitHub"}
   )
   
   foreach ($t in $tests) {
     $result = Test-Connection -ComputerName $t.Host -Count 1 -Quiet -ErrorAction SilentlyContinue
     $status = if ($result) { "✅ OK" } else { "❌ FAIL" }
     "${status} — $($t.Label) ($($t.Host))"
   }
   ```

6. **Flush DNS** (optional, if user requests)
   ```powershell
   ipconfig /flushdns | Out-Null
   "✅ DNS cache flushed"
   ```

7. **Check Active Connections** (top by count)
   ```powershell
   $connections = Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue
   $foreignIPs = $connections | Group-Object RemoteAddress | Sort-Object Count -Descending | Select-Object -First 10
   "Active connections: $($connections.Count)"
   $foreignIPs | ForEach-Object { "  $($_.Name): $($_.Count) connection(s)" }
   ```

## Output Format

```
╔══════════════════════════════════════════╗
║          NETWORK MONITOR REPORT          ║
╚══════════════════════════════════════════╝

🌐 ADAPTERS:
  [adapter info]

📡 IP ADDRESSES:
  [IP info]

🚪 GATEWAY:
  [gateway info]

📖 DNS SERVERS:
  [DNS info]

🌍 CONNECTIVITY TEST:
  [test results]

🔌 ACTIVE CONNECTIONS:
  [connection info]

💡 RECOMMENDATIONS:
  • [any issues found]
```

## Notes
- Run this when experiencing network issues
- Windows Firewall may block some Test-Connection requests
- For Wi-Fi networks, consider `netsh wlan show profiles` and `netsh wlan show interfaces`
