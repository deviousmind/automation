function Write-Info {
  param ([string]$text)
  Write-Host $text -ForegroundColor Cyan
}

function Write-Success {
  param ([string]$text)
  Write-Host $text -ForegroundColor Green
}

function Write-Message {
  param ([string]$text)
  Write-Host $text -ForegroundColor Magenta
}

Write-Info 'Removing existing custom image....'
wsl --unregister Custom-Ubuntu
Write-Info 'Checking WSL status...'
$featureName = 'Microsoft-Windows-Subsystem-Linux'
if ( (Get-WindowsOptionalFeature -FeatureName $featureName -Online).State -eq 'Enabled' ) {
  Write-Success 'WSL is already installed. Moving on...'
} else {
  Write-Info 'Enabling WSL...'
  Enable-WindowsOptionalFeature -FeatureName $featureName -Online
}

Write-Info 'Setting default WSL version to 2...'
wsl --set-default-version 2

Write-Info 'Ensuring WSL is up-to-date...'
wsl --update --web-download

################################################
#  Import Custom Ubuntu                        #
#  Create image with default sudo user juniper #
################################################
Write-Info 'Downloading Ubuntu image...'
$ubuntuInstall = Start-Process -FilePath wsl.exe -ArgumentList '--install -d Ubuntu --no-launch --web-download' -Wait -PassThru
$ubuntuInstall.WaitForExit()

Write-Info 'Importing Ubuntu image as custom copy...'
$ubuntuImage = Get-ChildItem -Recurse 'C:\Program Files\WindowsApps\' | Where-Object { $_.Name -eq 'install.tar.gz' }
wsl --import Custom-Ubuntu 'C:\CustomUbuntu' $ubuntuImage.FullName

Write-Info 'Setting default distro to Custom-Ubuntu'
wsl --set-default Custom-Ubuntu

Write-Info 'Adding sudo user "juniper"'
wsl -- adduser --quiet --disabled-password --shell /bin/bash --home /home/juniper --gecos "User" juniper
wsl -- echo "juniper:minty1" `| chpasswd
wsl -- usermod -aG sudo juniper
wsl -- echo '[user]'`>`>/etc/wsl.conf
wsl -- echo 'default=juniper'`>`>/etc/wsl.conf
wsl --shutdown
Write-Success 'Custom-Ubuntu ready for use!'

####################
# Configure docker #
####################
Write-Info 'Configuring docker....'
wsl -u root -- ./docker/install-docker.sh
wsl --shutdown
Write-Success 'Docker is ready!'

################################
# Additional User config       #
# Setup port proxies on launch #
# Set system limits            #
################################
Write-Info 'Setting up port proxies and docker on launch...'
wsl -u juniper -- cp ./docker/proxyports.ps1 ~
wsl -u root -- cp ./docker/proxyports.ps1 ~
wsl -u root -- echo '[boot]'`>`>/etc/wsl.conf
wsl -u root -- echo 'systemd=true'`>`>/etc/wsl.conf
# Win11
#wsl -u root -- echo 'command=service docker start'`>`>/etc/wsl.conf
wsl -u juniper -- echo '# Update Port Proxies'`>`>~/.bashrc
wsl -u juniper -- echo 'powershell.exe -ExecutionPolicy Bypass -File ~/proxyports.ps1'`>`>~/.bashrc
wsl --shutdown

Write-Info 'Setting global WSL constraints...'
$logicalProcessors = ($cpuInfo = Get-CimInstance -ClassName Win32_Processor).NumberOfLogicalProcessors
$totalMemory = ((Get-CimInstance -ClassName CIM_PhysicalMemory).Capacity | Measure-Object -Sum).Sum / (1024 * 1024 * 1024)
$wslConfig = @"
[wsl2]
processors=$($logicalProcessors / 2)
memory=$($totalMemory / 4)GB
swap=0
localhostForwarding=true
"@
$wslConfig | Out-File -FilePath "$env:USERPROFILE\.wslconfig" -Force
Write-Success 'Image is ready to host containers!'


################################
# Install Windows Terminal     #
# Setup profiles               #
# Set launch settings          #
################################
Write-Info 'Checking if Windows Terminal is installed...'
try {
  Start-Process -FilePath wt.exe -PassThru | Stop-Process -PassThru
  Write-Success 'Windows Terminal is installed. Moving on...'
} catch {
  Write-Info 'Windows Terminal is not installed. Beginning install...'
  winget install --id Microsoft.WindowsTerminal -e
}
Write-Info 'Making adjustments to Windows Terminal settings...'
$wtSettings = Get-ChildItem -Recurse "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState" | Where-Object { $_.Name -eq 'settings.json' }
$json = Get-Content $wtSettings.FullName -Raw | ConvertFrom-Json
$json | Add-Member -Name "startOnUserLogin" -Value $true -MemberType NoteProperty -Force
$json.profiles.defaults | Add-Member -Name "elevate" -Value $true -MemberType NoteProperty -Force
$customUbuntu = $json.profiles.list | Where-Object { $_.name -eq 'Custom-Ubuntu' }
$customUbuntu | Add-Member -Name "colorScheme" -Value "Ubuntu-ColorScheme" -MemberType NoteProperty -Force
$json.defaultProfile = $customUbuntu.guid

# Add git bash!
$gitBashJson = @"
{
  "guid": "{00000000-0000-0000-ba54-0000000000002}",
  "commandLine": "%PROGRAMFILES%/Git/usr/bin/bash.exe -i -l"
  "icon": "%PROGRAMFILES%/Git/mingw64/share/git/git-for-windows.ico",
  "name": "Bash"
}
"@
$gitBash = (ConvertFrom-Json -InputObject $gitBashJson)
$existingBash = $json.profiles.list | Where-Object { $_.guid -eq $gitBash.guid }
if ( $existingBash -eq $null ) {
  $json.profiles.list += $gitBash
}
$json | ConvertTo-Json -depth 32 | Out-File $wtSettings.FullName
# wtSettings expects UNIX line endings
((Get-Content $wtSettings.FullName) -join "`n") + "`n" | Set-Content -NoNewline $wtSettings.FullName
Write-Success 'Windows Terminal configuration complete! Launching...'
wt

#############################
# Setup Portainer in docker #
#############################
Write-Info 'Standing up Portainer.io in docker...'
wsl docker compose -f ./docker/portainer/docker-compose.yml up -d
Write-Success 'Portainer is ready to use! Launching...'
Start-Process http://localhost:9000
Write-Message 'Please create an admin user to interact with Portainer'

Write-Success 'Configuration complete!'