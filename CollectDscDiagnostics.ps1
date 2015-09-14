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
    $dir = @(Get-ChildItem C:\Packages\Plugins\Microsoft.Powershell.*DSC)[0].FullName
    Write-Verbose -message "Found DSC extension at: $dir" -verbose

    $tempPath = Join-path $env:temp ([system.io.path]::GetRandomFileName())
    if(!(Test-Path $tempPath))
    {
        mkdir $tempPath > $null
    }

    $tempPath2 = Join-path $env:temp ([system.io.path]::GetRandomFileName())
    if(!(Test-Path $tempPath2))
    {
        mkdir $tempPath2 > $null
    }

    Copy-Item -Recurse $dir $tempPath\DscPackageFolder -ErrorAction SilentlyContinue
    Copy-Item -Recurse C:\WindowsAzure\Logs $tempPath\WindowsAzureLogs -ErrorAction SilentlyContinue

    Export-EventLog -Name Microsoft-Windows-DSC/Operational -Path $tempPath
    Export-EventLog -Name Application -Path $tempPath

    $zip = Get-FolderAsZip -sourceFolder $tempPath -destinationPath $tempPath2
    Start-Process $tempPath2
    Write-Verbose -message "Please upload this zip file to https://filetransfer.support.microsoft.com/#/, your support engineer should have emailed you a logon and password: $zip" -verbose
}

Get-AzureVmDscDiagnostincs