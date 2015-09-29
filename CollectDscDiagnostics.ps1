#
# Return string representing zip file. Use set-content to create a zip file from it.
#
function Get-FolderAsZip
{
    [CmdletBinding()]
    param(

        [string]$sourceFolder,
        [string] $destinationPath
    )

    $attempts =0 
    $gotZip = $false
    while($attempts -lt 5 -and !$gotZip)
    {
        $attempts++
        $resultTable = invoke-command -ErrorAction:Continue -script {
                param($logFolder, $destinationPath)

                $tempPath = Join-path $env:temp ([system.io.path]::GetRandomFileName())
                if(!(Test-Path $tempPath))
                {
                    mkdir $tempPath > $null
                }
                $sourcePath = Join-path $logFolder '*'
                Copy-Item -Recurse $sourcePath $tempPath -ErrorAction SilentlyContinue

                $content = $null
                $caughtError = $null
                try {
                    

                    # Copy files using the Shell.  
                    # 
                    # Note, because this uses shell this will not work on core OSs
                    # But we only use this on older OSs and in test, so core OS use
                    # is unlikely
                    function Copy-ToZipFileUsingShell
                    {
                        param (
                            [string]
                            [ValidateNotNullOrEmpty()]
                            [ValidateScript({ if($_ -notlike '*.zip'){ throw 'zipFileName must be *.zip'} else {return $true}})]
                            $zipfilename,

                            [string]
                            [ValidateScript({ if(-not (Test-Path $_)){ throw 'itemToAdd must exist'} else {return $true}})]
                            $itemToAdd,

                            [switch]
                            $overWrite
                        )
                        Set-StrictMode -Version latest
                        if(-not (Test-Path $zipfilename) -or $overWrite)
                        {
                            set-content $zipfilename ('PK' + [char]5 + [char]6 + ("$([char]0)" * 18))
                        }
                        $app = New-Object -com shell.application
                        $zipFile = ( Get-Item $zipfilename ).fullname
                        $zipFolder = $app.namespace( $zipFile )
                        $itemToAdd = (Resolve-Path $itemToAdd).ProviderPath
                        $zipFolder.copyhere( $itemToAdd )
                    }
                $fileName = "$([System.IO.Path]::GetFileName($logFolder))-$((Get-Date).ToString('yyyyMMddhhmmss'))"
                if($destinationPath)
                {
                  $zipFile = Join-Path $destinationPath ('{0}.zip' -f $fileName)

                  if(!(Test-Path $destinationPath))
                  {
                    mkdir $destinationPath > $null
                  }
                }
                else
                {
                  $zipFile = Join-Path ([IO.Path]::GetTempPath()) ('{0}.zip' -f $fileName)
                }
                if ($PSVersionTable.CLRVersion.Major -lt 4)
                {
                    Copy-ToZipFileUsingShell -zipfilename $zipFile -itemToAdd $tempPath 
                    $content = Get-Content $zipFile | Out-String
                }
                else
                {
                    Add-Type -AssemblyName System.IO.Compression.FileSystem > $null
                    [IO.Compression.ZipFile]::CreateFromDirectory($tempPath, $zipFile) > $null
                    $content = Get-Content -Raw $zipFile
                }
            }
            catch [Exception]{
                $caughtError = $_
            }
                return @{
                    Content = $content
                    Error = $caughtError
                    zipFilePath = $zipFile
                }
                
            } -argumentlist @($sourceFolder,$destinationPath) -ErrorVariable zipInvokeError 
            

            if($zipInvokeError -or $resultTable.Error)
            {
                if($attempts -lt 5)
                {
                    Write-Warning "An error occured trying to zip $sourceFolder on $($VM.Name).  Will retry..."
                    Start-Sleep -Seconds $attempts
                }
                else {
                    if($resultTable.Error)
                    {
                        $lastError = $resultTable.Error
                    }
                    else {
                        $lastError = $zipInvokeError[0]    
                    }
                    
                    Write-Warning "An error occured trying to zip $sourceFolder on $($VM.Name).  Aborting."
                    Write-ErrorInfo -ErrorObject $lastError -WriteWarning

                }
            }
            else
            {
                $gotZip = $true
            }
    }
    $result = $resultTable.zipFilePath

    return $result
}
function Test-ContainerParameter
{
  [CmdletBinding()]
  param(
    [string] $Path,
    [string] $Name = 'Path'
  )

  if(!(Test-Path $Path -PathType Container))
  {
    throw "$Name parameter must be a valid container."
  }

  return $true
}

function Export-EventLog
{
  [CmdletBinding()]
  param(
    [string] $Name,
    [ValidateScript({Test-ContainerParameter $_})]
    [string] $path
  )
  $exePath = Join-Path $Env:windir 'system32\wevtutil.exe'
  $exportFileName = "$($Name -replace '/','-').evtx"

  $ExportCommand = "$exePath epl '$Name' '$Path\$exportFileName' /ow:True 2>&1"
  Invoke-expression -command $ExportCommand
}

function Get-AzureVmDscDiagnostincs
{
    [CmdletBinding(    SupportsShouldProcess=$true,        ConfirmImpact="High"    )]
    param()

$privacyConfirmation = @"
Collecting the following information, which may contain private/sensative details including:  
    1.	 Logs from the Azure VM Agent, including all extensions
    2.	 The state of the Azure DSC Extension, 
       including their configuration, configuration data (but not any decryption keys)
       and included or generated files.
    3.	 The DSC and application event logs.
    4. The WindowsUpdate, CBS and DISM logs

This tool is provided for your convience, to ensure all data is collected as quickly as possible.  

Are you sure you want to continue
"@
    if ($pscmdlet.ShouldProcess($privacyConfirmation)) 
    {
        $dir = @(Get-ChildItem C:\Packages\Plugins\Microsoft.Powershell.*DSC -ErrorAction SilentlyContinue)[0].FullName
        Write-Verbose -message "Found DSC extension at: $dir" -verbose

        $tempPath = Join-path $env:temp ([system.io.path]::GetRandomFileName())
        if(!(Test-Path $tempPath))
        {
            mkdir $tempPath > $null
            mkdir $tempPath\CBS > $null
            mkdir $tempPath\DISM > $null
        }

        $tempPath2 = Join-path $env:temp ([system.io.path]::GetRandomFileName())
        if(!(Test-Path $tempPath2))
        {
            mkdir $tempPath2 > $null
        }

        if($dir)
        {
          Copy-Item -Recurse $dir $tempPath\DscPackageFolder -ErrorAction SilentlyContinue
        }
        
        Copy-Item -Recurse C:\WindowsAzure\Logs $tempPath\WindowsAzureLogs -ErrorAction SilentlyContinue
        Copy-Item $env:windir\WindowsUpdate.log $tempPath\WindowsUpdate.log -ErrorAction SilentlyContinue
        Copy-Item $env:windir\logs\CBS\*.* $tempPath\CBS -ErrorAction SilentlyContinue
        Copy-Item $env:windir\logs\DISM\*.* $tempPath\DISM -ErrorAction SilentlyContinue
        Get-HotFix | Select-Object id >  $tempPath\HotFixIds.txt

        Export-EventLog -Name Microsoft-Windows-DSC/Operational -Path $tempPath
        Export-EventLog -Name Application -Path $tempPath

        $zip = Get-FolderAsZip -sourceFolder $tempPath -destinationPath $tempPath2
        Start-Process $tempPath2
        Write-Verbose -message "Please upload this zip file to https://filetransfer.support.microsoft.com/#/, your support engineer should have emailed you a logon and password: $zip" -verbose
    }
}

Get-AzureVmDscDiagnostincs