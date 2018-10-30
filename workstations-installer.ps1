## This will install automox on a list of workstations remotely
## Modified by Bill Bednarz 10/23/2018
## Get the list of servers
$kiosk_servers = Import-Csv "C:\Code\Automox\Windows\workstations\workstations.txt"
Invoke-Command -ComputerName $workstations.name -FilePath "C:\Code\Automox\Windows\Workstations\automox-workstations.ps1"
