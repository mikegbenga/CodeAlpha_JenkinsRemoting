<#
  Install a Jenkins Remoting agent on a remote Windows machine.
  Runs agent.jar at startup as a Scheduled Task under a dedicated local account.

  .\install-agent.ps1 -JenkinsUrl https://jenkins.example.com -AgentName remote-win-01 -Secret <secret>

  Create the matching node in Jenkins first (Manage Jenkins -> Nodes -> New node,
  "Launch agent by connecting it to the controller", label e.g. "windows remote").
#>
param(
  [Parameter(Mandatory)] [string] $JenkinsUrl,
  [Parameter(Mandatory)] [string] $AgentName,
  [Parameter(Mandatory)] [string] $Secret,
  [string] $WorkDir = 'C:\jenkins-agent'
)
$ErrorActionPreference = 'Stop'

if (-not (Get-Command java -ErrorAction SilentlyContinue)) {
  throw 'Java 17+ is required (e.g. winget install EclipseAdoptium.Temurin.17.JRE)'
}

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$jar = Join-Path $WorkDir 'agent.jar'
Invoke-WebRequest -UseBasicParsing -Uri ("{0}/jnlpJars/agent.jar" -f $JenkinsUrl.TrimEnd('/')) -OutFile $jar

$secretFile = Join-Path $WorkDir 'secret'
Set-Content -Path $secretFile -Value $Secret -NoNewline
# Restrict the secret to SYSTEM + Administrators
icacls $secretFile /inheritance:r /grant:r 'SYSTEM:R' 'Administrators:R' | Out-Null

$java = (Get-Command java).Source
$arguments = "-jar `"$jar`" -url $JenkinsUrl -name $AgentName -secret @`"$secretFile`" -workDir `"$WorkDir`" -webSocket"

$action    = New-ScheduledTaskAction -Execute $java -Argument $arguments -WorkingDirectory $WorkDir
$trigger   = New-ScheduledTaskTrigger -AtStartup
$settings  = New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero)
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Limited

Register-ScheduledTask -TaskName 'JenkinsAgent' -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
Start-ScheduledTask -TaskName 'JenkinsAgent'
Write-Host "Jenkins agent '$AgentName' installed and started. Check the node page in Jenkins."
