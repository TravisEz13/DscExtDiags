# DscExtDiags

DSC and Azure DSC Extension Diagnostics

Gather diagnostics from the machine running DSC or DSC Extension
--------------------------------
* Copy `CollectDscDiagnostics.ps1` locally
* Open an elevated PowerShell Windows
* Run `.\CollectDscDiagnostincs.ps1`
* Email the Zip that pops up to your support contact


Gather diagnostics from a PSSession to the machine running DSC or DSC Extension
--------------------------------
* Copy `CollectDscDiagnostics.ps1` locally
* Open an PowerShell Windows
* Open the PSSession to the Azure VM
* Run `.\CollectDscDiagnostincs.ps1 -Session <SessionToVm> `
* Email the Zip that pops up to your support contact
