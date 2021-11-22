
# Global settings
$ErrorActionPreference = "Stop"
$InformationPreference = "Continue"
Set-StrictMode -Version 2

@("Noveris.SvcProc") | ForEach-Object {
    Install-Module $_ -AcceptLicense -Force -Scope AllUsers
}

