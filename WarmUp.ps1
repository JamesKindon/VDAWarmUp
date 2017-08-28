<#

.SYNOPSIS
This script is designed to remove slow logon times for the first session of the day on a Citrix XenApp VDA by using Control Up Logon Simulator (Free)

.DESCRIPTION
This script is designed to run on a utility server or workstation. 
The Free ControlUp logon Simulator must be run under an interactive session, the script has the ability to lock the workspace for security purposes.
For large deployments, multiple iterations of this script can be spread across multiple utility servers - just split that actual launch files accordingly
Script is not Signed
Script does not use parameters by design

.NOTES
Step 1 - Active Directory Account
 - Create An Active Directory Based Account used to Complete the process
 - Create an Active Directory Group and nest the Account in it.
 - Launch Account will
   a) Be assigned to published Desktops via Entitlement policy (See below XA-CreateDesktopsFroVDAs.ps1 Script) or manually assigned for custom apps/resources
   b) Be used to login to the target machine used to run the Control Up Simulator
   c) Be defined as the logon account within the Control Up Simulator to launch the resources

Step 2 - Download and Configure Tools of Trade
 - Download Control Up Login Simulator and install it on your action machine: https://www.controlup.com/controlup-logon-simulator/
 - Download AutoLogon: Use Sysinternals AutoLogon to configure an encrypted Login session for your Launch User: https://docs.microsoft.com/en-us/sysinternals/downloads/autologon

The below is optional, however i think its the best way to manage this tool. You can always specify your own apps to use based on your specific requirements
 - Download Martin Zugec's  XA-CreateDesktopsForVDAs.ps1 Script from here: https://citrix.sharefile.com/d-s7ecf834e039425ab
 - Reference is here: https://www.citrix.com/blogs/2017/04/17/how-to-assign-desktops-to-specific-servers-in-xenapp-7/
 - Logic is to create a desktop per server in the environment with the published resource given the name of the actual server
 - Use the Active Directory group you created above as the entitlement group

Step 3 - Configure Control Up Simulator
 - Run Control Up login Sim once. Specify your Storefront or NetScaler Gateway
 - Specify the name of the first application/resource and specify user account (AutoLogon Account)
 - Set your desired time for session wait before logoff. Test and save settings file
 - Name the file something that makes sense. Eg, Settings_Server1.xml in your LaunchFileSoureDirectory.
 - Copy this file, and alter the name of the published desktop per server. Do this for each resource/server you want to warm up

Step 4 - Create Scheduled task
 - Create a Scheduled Task to start WarmUp.ps1 Script on Logon of AutoLogon Account on action machine
 - Action: powershell.exe -SetExecutionPolicy ByPass -File "PathtoFolder\WarmUp.ps1"
 - Trigger 1: On Logon of Auto Logon User
 - Trigger 2: At time of day (6am). This should align with your VDA reboot schedules

Step 5 - Set your environment Variables below
 - $LaunchFilesSource: Home location for Settings.xml files you created above
 - $RunLocked: Specify to lock the machine (Do this for obvious reasons). True or False
 - $TimeBetweenSessionLaunch: how long to leave between launch requests in Seconds
   Make sure to align this Variable with the time you configure in ControlUp Logon Sim - allow logon sim to gracefully start, sleep and log off a session before launching another request
 - $PortTest: performs a port test to make sure the server is up before testing. True or False
   This variable should only be used if you have configured the environment using the XA-CreateDesktopsForVDAs.ps1 Script above. 
   This ensures that the resource name stored in the XML matches your server name. If you have not configured using this script, you cannot use this test as your resource name wont match the server name.
 - $Port: Specify the port you wished to test. 1494 or 2598 makes sense

Step 6 - Enjoy first users of the day not whinging

.LINK

#>

#region variables

$LogonSimSource = "C:\Program Files (x86)\ControlUp Logon Simulator\ControlUpLogonSim.exe"
$LaunchFilesSource = "C:\temp\ControlUp\Automate" # See Notes Above
$RunLocked = "False" #See Notes above
[int]$TimeBetweenSessionLaunch = "45" # Time in Seconds. See Notes above
$PortTest = "True" # See Notes above
$Port = "1494" # See Notes above

#endregion

#region Functions
    
    #Define LogFile Write
    $LogTime = Get-Date -Format "MM-dd-yyyy_hh-mm-ss"
    $LogDir = "$LaunchFilesSource\Logs"
    $LogFile = "$LogDir\Log_SessionLaunch_$LogTime.log"
    
    Function Log-Write {
        param ([string]$logstring)
        add-content $logfile -value $logstring
    }

    function LockWorkstation {
        $shell = New-Object -com "Wscript.Shell"
        $shell.Run("%windir%\System32\rundll32.exe user32.dll,LockWorkStation")
        Log-Write "$(Get-Date -f o) - Interactive Session Locked"
    }

    function sleepnow {
        $x = $TimeBetweenSessionLaunch 
        $length = $x / 100
        while($x -gt 0) {
            $min = [int](([string]($x/60)).split('.')[0])
            $text = " " + $min + " minutes " + ($x % 60) + " seconds left"
            Write-Progress "Time till next Launch:" -status $text -perc ($x/$length)
            start-sleep -s 1
            $x--
        }
    }

    function ControlUpLaunch {
        Write-Host "Launching Logon Simulator with $LaunchFile"
        Log-Write "$(Get-Date -f o) - Launching Logon Simulator with $LaunchFile"
        Start-Process $LogonSimSource -ArgumentList "/noeula /s /config=""$LaunchFile""" -passthru | Out-Null
        SleepNow
        Stop-Process -name ControlUpLogonSim -Confirm:$false
        Log-Write "$(Get-Date -f o) - Stopped ControlUp Sim Process $LaunchFile"
    }

#endregion 

#region Action
    if (!(Test-Path $LogDir)) {
        Write-Warning "$LogDir Directory does not exist, creating.."
        New-Item -Path $LogDir -ItemType Directory -Verbose -Force | Out-Null
        Log-Write "$(Get-Date -f o) - $LogDir Directory does not exist. Created $LogDir"
    }

    if (!(Test-Path $LogonSimSource)) {
        Write-Host "ControlUp Logon Sim does not Exist. Please Check location of ControlUp Logon Sim" -ForegroundColor Red
        Log-Write "$(Get-Date -f o) - ControlUp Logon Sim does not Exist. Please Check location of ControlUp Logon Sim"
        Exit
    }
    elseif (Test-Path $LogonSimSource) {
        Write-Host "ControlUp Logon Sim found, Continuing" -ForegroundColor Green
        Log-Write "$(Get-Date -f o) - ControlUp Logon Sim found, Continuing"
    }

    # locate the Launchfiles
    if (Test-Path $LaunchFilesSource) {
        Write-Host "$LaunchFilesSource Found, Continuing" -ForegroundColor Green
        Log-Write "$(Get-Date -f o) - $LaunchFilesSource Found, Continuing"
        $LaunchFiles = Get-ChildItem $LaunchFilesSource\*.xml
        $LaunchFilesCount = $LaunchFiles.Count
        Write-Output "$LaunchFilesCount Launch Files Located" -Verbose
        Log-Write "$(Get-Date -f o) - $LaunchFilesCount Launch Files Located"
            if ($LaunchFilesCount -lt 1) {
                Write-Warning "There are no launch files available. Script will exit. Press any Key"
                Log-Write "$(Get-Date -f o) - There are no launch files available. Script will exit."
                $x = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                Exit
            }
    }
    elseif (!(Test-Path $LaunchFilesSource)) {
        Write-Warning "$LaunchFilesSource Directory Does not Exist"
        Log-Write "$(Get-Date -f o) - $LaunchFilesSource Directory Does not Exist. Creating"
        Write-Warning "There are no launch files available. Script will exit. Press any Key"
        Log-Write "$(Get-Date -f o) - There are no launch files available. Script will exit"
        $x = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        Exit
    }
    
    # Lock the Workstation
    if ($RunLocked -eq "True") {
        $Locked = Get-Process logonui -ErrorAction SilentlyContinue
            if ($Locked -eq $Null) {
                LockWorkstation
            }
    }

    # Launch ControlUp   
    foreach ($Launchfile in $LaunchFiles) {
        if ($PortTest -eq "True") {
            Write-Host "Port Testing Enabled using port $Port" -ForegroundColor Yellow
            Log-Write "$(Get-Date -f o) - Port Testing Enabled on port $Port"
            [xml]$xml = Get-Content $launchfile
            $ServerName = ($xml.SelectNodes("/ApplicationSettings/resourcename")).InnerXml
            $ICATest = Test-NetConnection -ComputerName $ServerName -Port $Port
                if ($ICATest.TcpTestSucceeded -match "False") {
                    write-Host "Port Test Failed on port $Port, Aborting Launch request for $ServerName" -ForegroundColor Red
                    Log-Write "$(Get-Date -f o) - Port Test failed on port $Port for $ServerName - Aborting Launch Request"
                }
                elseif ($ICATest.TcpTestSucceeded -match "True") {
                    Write-Host "Port Test Succeeded on port $Port for $ServerName - Executing Launch Request" -ForegroundColor Green
                    Log-Write "$(Get-Date -f o) - Port Test Succeeded on $Port for $ServerName - Executing Launch Request"
                    ControlUpLaunch
                }
            }
        else {
            Write-Host "Port Testing not Enabled. Executing Launch Request" -ForegroundColor Yellow
            Log-Write "$(Get-Date -f o) - Port Testing not Enabled. Executing Launch Request"
            ControlUpLaunch
        }
    
    }
#Endregion