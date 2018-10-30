<#
.SYNOPSIS
    Installs Automox agent if not previously installed
.DESCRIPTION
    Installs Automox agent if an existing installation is not detected
.NOTES
    Name: InstallAndLaunchAutomox.ps1
    Author: www.automox.com
    Date created: 2017-06-18
    Version: 1.0
.LINK
    https://support.automox.com
.PARAMETERS
    -organization YOUR-ORGANIZATION-KEY
    -group <workstations> - Assigns endpoint to a group (valid on first launch)
    -echo Echo logging to console
.EXAMPLE
    .\InstallAndLaunchAutomox.ps1 -organization YOUR-ORGANIZATION-KEY
#>

param (
     [string]$organization = "efc075d2-bbaf-4b22-9194-407b0eb9ae99",
     [string]$group = "workstations",
     [switch]$echo = $false
 )

#####################################################################
# DO NOT CHANGE ANYTHING THAT FOLLOWS
#####################################################################
$AGENT_INSTALLER_URL="https://console.automox.com/Automox_Installer-1.0-8.exe"
$AGENT_PATH="${env:ProgramFiles(x86)}\Automox"
$AGENT_BINARY_NAME="amagent.exe"
$AGENT_SERVICE_NAME="amagent"
$AGENT_INSTALLER_PATH="$env:TEMP\AutomoxInstaller.exe"
$AGENT_UNINSTALLER_NAME="unins000.exe"
$EVENT_LOGGER_KEY_NAME="hklm:\SYSTEM\CurrentControlSet\Services\EventLog\Application\amagent"
$INSTALLER_BINARY_NAMES="AutomoxInstaller.exe"
$LOGFILE = "$env:TEMP\AutomoxInstallandLaunch.log"


#########################################################################################
# Logging
#########################################################################################
Function LogWrite
{
   Param ([string]$logstring)
   Add-content $LOGFILE -value $logstring
}

Function Write-Log {
    [CmdletBinding()]
    Param(
    [Parameter(Mandatory=$False)]
    [ValidateSet("INFO","WARN","ERROR","FATAL","DEBUG")]
    [String]
    $Level = "INFO",

    [Parameter(Mandatory=$True)]
    [string]
    $Message
    )

    $Stamp = (Get-Date).toString("yyyy/MM/dd HH:mm:ss")
    $Line = "$Stamp $Level $Message"
    If($LOGFILE) {
        Add-Content $LOGFILE -Value $Line
        If($echo) {
            Write-Output $Line
        }
    }
    Else {
        Write-Output $Line
    }
}

#########################################################################################
# Agent Installer Funcs
#########################################################################################
Function DownloadAgentInstaller() {
    Write-Log INFO "DownloadAgentInstaller() starting"            
    (New-Object System.Net.WebClient).DownloadFile("${AGENT_INSTALLER_URL}", "${AGENT_INSTALLER_PATH}")
}

Function AgentInstallerExists() {
    $ret = Test-Path ${AGENT_INSTALLER_PATH}
    Write-Log INFO ("AgentInstallerExists() for " + $AGENT_INSTALLER_PATH + " is " + $ret)            
    return $ret
}

Function InstallAgent() {
    $params = "-k ${organization} /VERYSILENT /NORESTART /SUPPRESSMSGBOXES /LOG=$env:TEMP\axUpdate.log"
    $fpath = $AGENT_INSTALLER_PATH
    Write-Log INFO ("InstallAgent() executing agent installer: " + $fpath + " " + $params)
    Start-Process -FilePath $fpath -ArgumentList $params -Wait

    SetGroup($group)
}

Function SetGroup() {
    param($GroupName)
    if ($GroupName -ne '') {
        $fpath = $AGENT_PATH + "\" + $AGENT_BINARY_NAME
        $params = "--setgrp `"Default Group/${GroupName}`""
        Write-Log INFO("SetGroup() setting amagent group to: " + $GroupName)
        Write-Log INFO("fpath: " + $fpath + ", Params: " + $params)
        Start-Process -FilePath $fpath -ArgumentList $params -Wait
    }
}

Function StartAgent() {
    StartService(${AGENT_SERVICE_NAME})
}

Function KillInstaller() {
    try {
        Stop-Process -processname ${INSTALLER_BINARY_NAMES} -ErrorAction Stop
    } catch {
        Write-Error "Could not kill Automox installer processes"
    }
}

Function KillAgent() {
    if (AgentIsRunning) {
        Stop-Process -processname ${AGENT_BINARY_NAME} -ErrorAction SilentlyContinue

        WaitUntilServices $ServiceName "Stopped"

        $ret = AgentIsRunning

        if (-not $ret) {
            return $true
        } else {
            Write-Host "KillAgent(): Could not kill ${AGENT_BINARY_NAME} binary"
            return $false
        }
    }
    return $true
}

Function InstallerIsRunning() {
    try {
        Get-Process ${INSTALLER_BINARY_NAMES} -ErrorAction Stop
        $true
    } catch {
        $false
    }
}
Function AgentIsRunning() {
    if (ServiceIsRunning(${AGENT_SERVICE_NAME})) {
        return $true
    } else {
        return $false
    }
}

Function AgentIsInServiceManager() {
    if (ServiceIsInServiceManager(${AGENT_SERVICE_NAME})) {
        return $true
    } else {
        return $false
    }
}

Function AgentIsOnFileSystem() {
    $ret = Test-Path "${AGENT_PATH}/${AGENT_BINARY_NAME}"
    if ($ret) {
        return $true
    } else {
        return $false
    }
}

Function AgentIsInstalled() {
    $inServiceMgr = AgentIsInServiceManager
    $onFileSystem = AgentIsOnFileSystem

    $inServiceMgr -Or $onFileSystem
}


#########################################################################################
# Service Manager Funcs
#########################################################################################
Function ServiceIsInServiceManager{
    param($ServiceName)
    $service = Get-Service -name $ServiceName -ErrorAction SilentlyContinue
    if (-not $service) {
        return $false
    } else {
        return $true
    }
}

Function ServiceIsRunning{
    param($ServiceName)
    $arrService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

    if ($arrService.Status -ne 'Running') {
        return $false
    } else {
        return $true
    }
}

function WaitUntilServices($serviceName, $status)
{
    # Get all services where DisplayName matches $serviceName and loop through each of them.
    # Status: {Running, Stopped}
    foreach($service in (Get-Service -Name $serviceName))
    {
        # Wait for the service to reach the $status or a maximum of 20 seconds
        $service.WaitForStatus($status, '00:00:20')
    }
}

function StartService{
    param($ServiceName)

    Write-Log INFO ("StartService() starting service: " + $ServiceName)
    $serviceRunning = ServiceIsRunning($ServiceName)
    Write-Log INFO ("  Service status: " + $serviceRunning)

    if (-Not $serviceRunning ) {
        Write-Log INFO "  Service is stopped, Starting Service"
        Start-Service $ServiceName

        WaitUntilServices $ServiceName "Running"

        $ret = ServiceIsRunning($ServiceName)

        if (-not $ret) {
            Write-Log ERROR "  Service Failed to Start"
            Write-Error "StartService(s): $ServiceName service failed to start (return = $ret)"
            return $false
        } else {
            Write-Log INFO "  Service Started Successfully"
            return $true
        }
    } else {
        Write-Log INFO "  Service Already Started"
    }
    return $true
}

############################################################################################
# Do a normal agent install, and verify correct installation
############################################################################################
Function DownloadAndInstallAgent() {

    Write-Log INFO "DownloadAndInstallAgent() starting"
    $agentIsInstalled = AgentIsInstalled

    if (-Not $agentIsInstalled) {
        Write-Log INFO "  TEST: Agent is not installed"
        Write-Log INFO "  Downloading Agent"

        DownloadAgentInstaller

        if (AgentInstallerExists) {
            Write-Log INFO "  Agent Installer Downloaded Successfully"
            Write-Log INFO "  Installing Agent"

            InstallAgent
            $exitCode = $?
            
            $agentIsInstalled = AgentIsInstalled
            if ($agentIsInstalled) {
                Write-Log INFO "  agentIsInstalled() = TRUE: Agent Is Installed"

            } else {
                Write-Log ERROR "  agentIsInstalled() = FALSE: Agent Is NOT Installed"
                exit 1
            }

            if (-not $exitCode) {
                Write-Log ERROR ("  Error installing agent, Exit = " + $exitCode)
                Write-Error "Agent installation failed. Please contact support@automox.com"
                exit 1
            } else {
                Write-Log INFO ("  Agent Installed Successfully Exit = " + $exitCode)            
            }

        } else {
            Write-Log ERROR ("  Error downloading agent installer " + $exitCode)            
            Write-Error "Could not download agent installer from ${AGENT_INSTALLER_URL}. Install FAILED."
            exit 1
        }
    } else {
        Write-Log INFO "  Agent is already installed"            
    }
}

############################################################################################
# Main Execution
############################################################################################

Write-Log INFO "InstallAndLaunchAutomox.ps1 Started"
Write-Log INFO ("Organization Key: " +  $organization)
Write-Log INFO ("Group: " + $group)

# Run some tests:
$onFileSystem = AgentIsOnFileSystem
Write-Log INFO ("Test for Agent on filesystem      : " + $onFileSystem)
$inServiceMgr = AgentIsInServiceManager
Write-Log INFO ("Test for Agent in service manager : " + $inServiceMgr)
$serviceIsRunning = AgentIsRunning
Write-Log INFO ("Test for Agent service running    : " + $serviceIsRunning)

DownloadAndInstallAgent
StartAgent