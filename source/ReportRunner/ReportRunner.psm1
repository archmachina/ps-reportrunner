<#
#>

########
# Global settings
$ErrorActionPreference = "Stop"
$InformationPreference = "Continue"
Set-StrictMode -Version 2

########
# Add types
Add-Type -AssemblyName 'System.Web'

# List of library items that can be referenced in Add-ReportRunnerContextSection
$Script:Definitions = New-Object 'System.Collections.Generic.Dictionary[string, ScriptBlock]'

Class ReportRunnerSection
{
    [string]$Name
    [string]$Description
    [ScriptBlock[]]$Scripts
    [string[]]$LibraryMatches
    [HashTable]$Data

    ReportRunnerSection([string]$name, [string]$description, [ScriptBlock[]]$scripts,
        [string[]]$libraryMatches, [HashTable]$data)
    {
        $this.Name = $name
        $this.Description = $description
        $this.Scripts = $scripts
        $this.LibraryMatches = $libraryMatches
        $this.Data = $data
    }
}

class ReportRunnerSectionContent
{
    [string]$Name
    [string]$Description
    [System.Collections.ArrayList]$Content

    ReportRunnerSectionContent([string]$Name, [string]$Description)
    {
        $this.Name = $name
        $this.Description = $description
        $this.Content = New-Object 'System.Collections.ArrayList'
    }
}

Class ReportRunnerFormatTable
{
    $Content
}

Class ReportRunnerContext
{
    [System.Collections.Generic.List[ReportRunnerSection]]$Entries

    ReportRunnerContext()
    {
        $this.Entries = New-Object 'System.Collections.Generic.List[ReportRunnerSection]'
    }
}

enum ReportRunnerStatus
{
    None = 0
    Info
    Warning
    Error
    InternalError
}

<#
#>
Class ReportRunnerNotice
{
    [ReportRunnerStatus]$Status
    [string]$Description

    ReportRunnerNotice([ReportRunnerStatus]$status, [string]$description)
    {
        $this.Status = $status
        $this.Description = $description
    }

    [string] ToString()
    {
        return ("{0}: {1}" -f $this.Status.ToString().ToUpper(), $this.Description)
    }
}

<#
#>
Function New-ReportRunnerNotice
{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param(
        [Parameter(mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Description,

        [Parameter(mandatory=$false)]
        [ValidateNotNull()]
        [ReportRunnerStatus]$Status = [ReportRunnerStatus]::None
    )

    process
    {
        $notice = New-Object ReportRunnerNotice -ArgumentList $Status, $Description

        $notice
    }
}

<#
#>
Function New-ReportRunnerFormatTable
{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param(
        [Parameter(mandatory=$true)]
        [ValidateNotNull()]
        $Content
    )

    process
    {
        $format = New-Object 'ReportRunnerFormatTable'
        $format.Content = $Content

        $format
    }
}

<#
#>
Function New-ReportRunnerContext
{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType('ReportRunnerContext')]
    param(
    )

    process
    {
        $obj = New-Object ReportRunnerContext

        $obj
    }
}

<#
#>
Function Add-ReportRunnerDefinition
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [ScriptBlock]$Script
    )

    process
    {
        $script:Definitions[$Name] = $Script
    }
}

<#
#>
Function Add-ReportRunnerContextSection
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline)]
        [ValidateNotNull()]
        [ReportRunnerContext]$Context,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory=$false)]
        [ValidateNotNull()]
        [AllowEmptyString()]
        [string]$Description = "",

        [Parameter(Mandatory=$false)]
        [ValidateNotNull()]
        [ScriptBlock[]]$Scripts = [ScriptBlock[]]@(),

        [Parameter(Mandatory=$false)]
        [ValidateNotNull()]
        [string[]]$LibraryMatches = [string[]]@(),

        [Parameter(Mandatory=$false)]
        [AllowNull()]
        [HashTable]$Data = $null
    )

    process
    {
        # Add the script to the list of scripts to process
        $entry = New-Object 'ReportRunnerSection' -ArgumentList $Name, $Description, $Scripts, $LibraryMatches, $Data
        $Context.Entries.Add($entry) | Out-Null
    }
}

<#
#>
Function Invoke-ReportRunnerContext
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [ReportRunnerContext]$Context
    )

    process
    {
        $Context.Entries | ForEach-Object {
            $entry = $_

            # Create a list of the scripts to run for this context section
            $scripts = New-Object 'System.Collections.Generic.LinkedList[ScriptBlock]'

            # Add any scripts defined specifically for this context section
            $entry.Scripts | ForEach-Object { $scripts.Add($_) }

            # Add library definition scripts where the name matches the incoming match list
            $script:Definitions.Keys | ForEach-Object {
                $key = $_
                $count = ($entry.LibraryMatches | Where-Object { $key -match $_ } | Measure-Object).Count
                if ($count -gt 0 )
                {
                    $scripts.Add($script:Definitions[$key])
                }
            }

            # Output a section format object
            $content = New-Object 'ReportRunnerSectionContent' -ArgumentList $entry.Name, $entry.Description

            $scripts | ForEach-Object {
                $script = $_

                Invoke-Command -NoNewScope {
                    # Run the script block
                    try {
                        ForEach-Object -InputObject $entry.Data -Process $script
                    } catch {
                        New-ReportRunnerNotice -Status InternalError -Description "Error running script: $_"
                    }
                }
            } *>&1 | ForEach-Object {
                $content.Content.Add($_) | Out-Null
            }

            $content
        }
    }
}

<#
#>
Function Format-ReportRunnerContentAsHtml
{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '')]
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline)]
        [ValidateNotNull()]
        [ReportRunnerSectionContent]$Section,

        [Parameter(Mandatory=$false)]
        [AllowEmptyString()]
        [ValidateNotNull()]
        [string]$Title = "",

        [Parameter(Mandatory=$false)]
        [bool]$DecodeHtml = $true
    )

    begin
    {
        # Collection of all notices across all sections
        $allNotices = [ordered]@{}

        $allSectionContent = New-Object 'System.Collections.ArrayList'

        # Html preamble
        "<!DOCTYPE html PUBLIC `"-//W3C//DTD XHTML 1.0 Strict//EN`"  `"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd`">"
        "<html xmlns=`"http://www.w3.org/1999/xhtml`">"
        "<head>"
        "<title>$Title</title>"
        "<style>"
        "table {"
        "  font-family: Arial, Helvetica, sans-serif;"
        "  border-collapse: collapse;"
        "  width: 100%;"
        "}"
        "td, th {"
        "  border: 1px solid #ddd;"
        "  padding: 8px;"
        "}"
        "tr:nth-child(even){background-color: #f2f2f2;}"
        "tr:hover {background-color: #ddd;}"
        "th {"
        "  padding-top: 12px;"
        "  padding-bottom: 12px;"
        "  text-align: left;"
        "  background-color: #04AA6D;"
        "  color: white;"
        "}"
        "</style>"
        "</head><body>"
    }

    process
    {
        # Generate string content for this section
        $sectionContent = & {
            $notices = New-Object 'System.Collections.Generic.List[string]'

            # Display section heading
            ("<b>Section: {0}</b><br>" -f $Section.Name)
            ("<i>{0}</i><br><p />" -f $Section.Description)
            "<hr />"

            $output = $Section.Content | ForEach-Object {

                # Default message to pass on in pipeline
                $msg = $_

                # Check if it is a string or status object
                if ([ReportRunnerNotice].IsAssignableFrom($msg.GetType()))
                {
                    [ReportRunnerNotice]$notice = $_
                    $noticeStr = $notice.ToString()
                    $notices.Add($noticeStr) | Out-Null

                    # Only add Notices that are issues to the all notices list
                    if ($notice.Status -eq [ReportRunnerStatus]::Warning -or $notice.Status -eq [ReportRunnerStatus]::Error -or
                        $notice.Status -eq [ReportRunnerStatus]::InternalError)
                    {
                        if ($null -eq $allNotices[$Section.Name])
                        {
                            $allNotices[$Section.Name] = New-Object 'System.Collections.Generic.List[string]'
                        }

                        $allNotices[$Section.Name].Add($noticeStr) | Out-Null
                    }

                    # Alter message to notice string representation
                    $msg = $noticeStr
                }

                if ([System.Management.Automation.InformationRecord].IsAssignableFrom($_.GetType()))
                {
                    $msg = ("INFO: {0}" -f $_.ToString())
                }
                elseif ([System.Management.Automation.VerboseRecord].IsAssignableFrom($_.GetType()))
                {
                    $msg = ("VERBOSE: {0}" -f $_.ToString())
                }
                elseif ([System.Management.Automation.ErrorRecord].IsAssignableFrom($_.GetType()))
                {
                    $msg = ("ERROR: {0}" -f $_.ToString())
                }
                elseif ([System.Management.Automation.DebugRecord].IsAssignableFrom($_.GetType()))
                {
                    $msg = ("DEBUG: {0}" -f $_.ToString())
                }
                elseif ([System.Management.Automation.WarningRecord].IsAssignableFrom($_.GetType()))
                {
                    $msg = ("WARNING: {0}" -f $_.ToString())
                }

                if ([ReportRunnerFormatTable].IsAssignableFrom($msg.GetType()))
                {
                    $msg = $msg.Content | ConvertTo-Html -As Table -Fragment
                }

                if ([string].IsAssignableFrom($msg.GetType()))
                {
                    $msg += "<br>"
                    if ($DecodeHtml)
                    {
                        $msg = [System.Web.HttpUtility]::HtmlDecode($msg)
                    }
                }

                # Pass message on in the pipeline
                $msg
            }

            # Display notices for this section
            if (($notices | Measure-Object).Count -gt 0)
            {
                "<u>Notices:</u><br><ul>"
                $notices | ForEach-Object {
                    ("<li>{0}</li>" -f $_)
                }
                "</ul><br>"
            }

            # Display output
            "<u>Content:</u><br>"
            $output | Out-String

            "<p />"
        } | Out-String

        $allSectionContent.Add($sectionContent) | Out-Null
    }

    end
    {
        # Display all notices here
        "<u>All Notices:</u><br><ul>"
        $allNotices.Keys | ForEach-Object {
            $key = $_
            ("<li>{0}</li>" -f $key)

            "<ul>"
            $allNotices[$key] | ForEach-Object {
                ("<li>{0}</li>" -f $_)
            }
            "</ul>"
        }
        "</ul><br>"

        # Display all section content
        $allSectionContent | ForEach-Object { $_ }

        # Wrap up HTML
        "</body></html>"
    }
}
