# Self-elevate the script if required
if( -Not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')){
  $commandLine = "-ExecutionPolicy Bypass -File `"" + $MyInvocation.MyCommand.Path + "`" " + $MyInvocation.UnboundArguments
  Start-Process -FilePath Powershell.exe -Verb RunAs -ArgumentList $commandLine
  exit
}

# Run elevated script
$wsl_ip = (wsl hostname -I).split(" ")[0]
Write-Host "WSL Machine IP: " $wsl_ip
# portainer port
netsh interface portproxy add v4tov4 listenport=9000 connectport=9000 connectaddress=$wsl_ip 
# add more here if needed