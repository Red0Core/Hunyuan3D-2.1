# Return the active sing-box TUN interface, including the alias used by Karing.
foreach ($Alias in 'singbox_tun', 'Karing TUN Network Adapter') {
    $Adapter = Get-NetIPAddress -InterfaceAlias $Alias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object AddressState -eq 'Preferred' | Select-Object -First 1
    if ($Adapter) { return $Adapter }
}
throw 'Start sing-box or Karing in TUN mode before downloading.'
