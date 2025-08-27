# PowerShell (Admin)
New-VMSwitch -SwitchName "vsprivate" -SwitchType Internal
New-NetIPAddress -IPAddress 10.99.64.1 -PrefixLength 24 -InterfaceAlias "vEthernet (vsprivate)"
New-NetNat -Name "vsprivate_nat" -InternalIPInterfaceAddressPrefix "10.99.64.0/24"

# Portproxy 80/443 hacia txedgevm (si piensas publicar por el host)
netsh interface portproxy add v4tov4 listenport=80 listenaddress=0.0.0.0 connectport=80 connectaddress=10.99.64.2
netsh interface portproxy add v4tov4 listenport=443 listenaddress=0.0.0.0 connectport=443 connectaddress=10.99.64.2
