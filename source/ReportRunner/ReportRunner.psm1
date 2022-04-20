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

# List of library items that can be referenced in Add-ReportRunnerSection
$Script:Definitions = New-Object 'System.Collections.Generic.Dictionary[string, ReportRunnerBlock]'

Class ReportRunnerContext
{
    [string]$Title
    [System.Collections.Generic.List[ReportRunnerSection]]$Sections
    [HashTable]$Data

    ReportRunnerContext([string]$title, [HashTable]$data)
    {
        $this.Title = $title
        $this.Data = $data.Clone()
        $this.Sections = New-Object 'System.Collections.Generic.LinkedList[ReportRunnerSection]'
    }
}

Class ReportRunnerSection
{
    [string]$Name
    [string]$Description
    [HashTable]$Data
    [System.Collections.Generic.LinkedList[ReportRunnerBlock]]$Blocks

    ReportRunnerSection([string]$name, [string]$description, [HashTable]$data)
    {
        $this.Name = $name
        $this.Description = $description
        $this.Data = $data.Clone()
        $this.Blocks = New-Object 'System.Collections.Generic.LinkedList[ReportRunnerBlock]'
    }
}

class ReportRunnerBlock
{
    [string]$Name
    [string]$Description
    [HashTable]$Data
    [ScriptBlock]$Script
    [System.Collections.Generic.LinkedList[PSObject]]$Content

    ReportRunnerBlock([string]$Name, [string]$Description, [HashTable]$data, [ScriptBlock]$script)
    {
        $this.Name = $name
        $this.Description = $description
        $this.Content = New-Object 'System.Collections.Generic.LinkedList[PSObject]'
        $this.Data = $data.Clone()
        $this.Script = $script
    }
}

Class ReportRunnerFormatTable
{
    [System.Collections.ArrayList]$Content

    ReportRunnerFormatTable([System.Collections.ArrayList]$content)
    {
        $this.Content = $content
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
    [string]$SourceBlock

    ReportRunnerNotice([ReportRunnerStatus]$status, [string]$description)
    {
        $this.Status = $status
        $this.Description = $description
        $this.SourceBlock = $null
    }

    [string] ToString()
    {
        return ("{0}: {1}" -f $this.Status.ToString().ToUpper(), $this.Description)
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
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Title,

        [Parameter(Mandatory=$false)]
        [ValidateNotNull()]
        [HashTable]$Data = @{}
    )

    process
    {
        $obj = New-Object ReportRunnerContext -ArgumentList $Title, $Data

        $obj
    }
}

<#
#>
Function New-ReportRunnerSection
{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType('ReportRunnerSection')]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [ReportRunnerContext]$Context,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Description,

        [Parameter(Mandatory=$false)]
        [ValidateNotNull()]
        [HashTable]$Data = @{}
    )

    process
    {
        $obj = New-Object ReportRunnerSection -ArgumentList $Name, $Description, $Data

        # Add this new section to the list of sections in the current context
        $Context.Sections.Add($obj)

        # Pass the section on to allow the caller access to the section
        $obj
    }
}

<#
#>
Function New-ReportRunnerBlock
{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding(DefaultParameterSetName="NewBlock")]
    [OutputType('ReportRunnerBlock')]
    param(
        [Parameter(Mandatory=$true, ParameterSetName="NewBlock")]
        [Parameter(Mandatory=$true, ParameterSetName="Library")]
        [ValidateNotNullOrEmpty()]
        [ReportRunnerSection]$Section,

        [Parameter(Mandatory=$true, ParameterSetName="Library")]
        [ValidateNotNullOrEmpty()]
        [string]$LibraryFilter,

        [Parameter(Mandatory=$true, ParameterSetName="NewBlock")]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory=$true, ParameterSetName="NewBlock")]
        [ValidateNotNullOrEmpty()]
        [string]$Description,

        [Parameter(Mandatory=$false, ParameterSetName="Library")]
        [Parameter(Mandatory=$false, ParameterSetName="NewBlock")]
        [ValidateNotNull()]
        [HashTable]$Data = @{},

        [Parameter(Mandatory=$true, ParameterSetName="NewBlock")]
        [ValidateNotNull()]
        [ScriptBlock]$Script
    )

    process
    {
        # Check if we're matching on a LibraryFilter, rather than a new block
        if (![string]::IsNullOrEmpty($LibraryFilter))
        {
            # Find all matches and add each block to the section with the supplied data
            $script:Definitions.Keys | Where-Object { $_ -match $LibraryFilter} | ForEach-Object {
                $lib = $Script:Definitions[$_]

                $obj = New-Object ReportRunnerBlock -ArgumentList $lib.Name, $lib.Description, $Data, $lib.Script

                $Section.Blocks.Add($obj)
            }

            return
        }

        # Create a new block that will be added to the section
        $obj = New-Object ReportRunnerBlock -ArgumentList $Name, $Description, $Data, $Script

        # Add this new block to the list of blocks in the current section
        $Section.Blocks.Add($obj)
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
Function ConvertTo-ReportRunnerFormatTable
{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param(
        [Parameter(mandatory=$true,ValueFromPipeline)]
        [ValidateNotNull()]
        $Content
    )

    begin
    {
        $objs = New-Object 'System.Collections.ArrayList'
    }

    process
    {
        $objs.Add($Content) | Out-Null
    }

    end
    {
        $format = [ReportRunnerFormatTable]::New($objs)

        $format
    }
}

<#
#>
Function Add-ReportRunnerLibraryBlock
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, HelpMessage = "Must be in module.group.id format")]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern("^[a-zA-Z_-]*\.[a-zA-Z_-]*\.[a-zA-Z_-]*$")]
        [string]$Id,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Description,

        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [ScriptBlock]$Script
    )

    process
    {
        $script:Definitions[$Id] = New-Object ReportRunnerBlock -ArgumentList $Name, $Description, @{}, $Script
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
        $Context.Sections | ForEach-Object {
            $section = $_

            # Flatten the Context and Section data in to a new HashTable
            $sectionData = $Context.Data.Clone()
            $section.Data.Keys | ForEach-Object { $sectionData[$_] = $section.Data[$_] }

            $section.Blocks | ForEach-Object {
                $block = $_

                # Flatten the Section and Block data in to a new HashTable
                $blockData = $sectionData.Clone()
                $block.Data.Keys | ForEach-Object { $blockData[$_] = $block.Data[$_] }

                # Invoke the block script with the relevant data and store content
                $content = New-Object 'System.Collections.Generic.LinkedList[PSObject]'
                Invoke-Command -NoNewScope {
                    # Run the script block
                    try {
                        ForEach-Object -InputObject $blockData -Process $block.Script
                    } catch {
                        New-ReportRunnerNotice -Status InternalError -Description "Error running script: $_"
                    }
                } *>&1 | ForEach-Object { $content.Add($_) }

                # Save the content back to the block
                $block.Content = $content
            }
        }
    }
}

<#
#>
Function Format-ReportRunnerContextAsHtml
{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '')]
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [ReportRunnerContext]$Context,

        [Parameter(Mandatory=$false)]
        [bool]$DecodeHtml = $true
    )

    process
    {
        # Collection of all notices across all sections
        $allNotices = [ordered]@{}

        # Html preamble
        $title = $Context.Title
        "<!DOCTYPE html PUBLIC `"-//W3C//DTD XHTML 1.0 Strict//EN`"  `"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd`">"
        "<html xmlns=`"http://www.w3.org/1999/xhtml`">"
        "<head>"
        "<title>$title</title>"
        "<style>"
        "table {"
        "  font-family: Arial, Helvetica, sans-serif;"
        "  border-collapse: collapse;"
        "  width: 100%;"
        "}"
        "td, th {"
        "  border: 1px solid #ddd;"
        "  padding: 6px;"
        "}"
        "tr:nth-child(even){background-color: #f2f2f2;}"
        "tr:hover {background-color: #ddd;}"
        ".warningCell {background-color: #ffeb9c;}"
        ".errorCell {background-color: #ffc7ce;}"
        ".internalErrorCell {background-color: #ffc7ce;}"
        "th {"
        "  padding-top: 12px;"
        "  padding-bottom: 12px;"
        "  text-align: left;"
        "  background-color: #04AA6D;"
        "  color: white;"
        "}"
        "div.section {"
        "  padding: 10px;"
        "  padding-bottom: 20px;"
        "  border: 1px solid gray;"
        "  margin-bottom: 10px;"
        "  box-shadow: 4px 3px 8px 1px #969696"
        "}"
        "div.block {"
        "  border-top: 1px solid gray;"
        "  margin-top: 20px;"
        "}"
        "div.blockContent {"
        "  font-family: Courier New, monospace;"
        "  white-space: pre"
        "}"
        "</style>"
        "</head><body>"
        "<h2>$title</h2>"

        $allContent = $Context.Sections | ForEach-Object {
            $section = $_
            $notices = New-Object 'System.Collections.Generic.LinkedList[ReportRunnerNotice]'

            # Format section start
            "<div class=`"section`">"
            ("<h3>Section: {0}</h3>" -f $Section.Name)
            ("<i>{0}</i><br><br>" -f $Section.Description)

            # Iterate through block content
            $content = $section.Blocks | ForEach-Object {
                $block = $_
                $guid = [Guid]::NewGuid()

                # Format block start
                "<div class=`"block`" id=`"$guid`">"
                ("<h4>{0}</h4><i>{1}</i><br><br>" -f $block.Name, $block.Description)

                # Format block content
                $blockContent = $block.Content | ForEach-Object {
                    $msg = $_

                    # Check if it is a string or status object
                    if ([ReportRunnerNotice].IsAssignableFrom($msg.GetType()))
                    {
                        [ReportRunnerNotice]$notice = $_
                        $notice.SourceBlock = $guid
                        $notices.Add($notice) | Out-Null

                        if ($allNotices.Keys -notcontains $section.Name)
                        {
                            $allNotices[$section.Name] = New-Object 'System.Collections.Generic.LinkedList[ReportRunnerNotice]'
                        }

                        $allNotices[$section.Name].Add($notice) | Out-Null

                        # Alter message to notice string representation
                        $msg = $notice.ToString()
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
                        $msg = $msg.Content | ConvertTo-Html -As Table -Fragment | Out-String
                        $msg = $msg.Replace([Environment]::Newline, "")
                    }

                    if ([string].IsAssignableFrom($msg.GetType()))
                    {
                        # $msg += "<br>"
                        if ($DecodeHtml)
                        {
                            $msg = [System.Web.HttpUtility]::HtmlDecode($msg)
                        }
                    }

                    # Pass message on in the pipeline
                    $msg
                } | Out-String

                # Replace newlines with breaks and output
                $blockContent = $blockContent.Replace([Environment]::Newline, "<br>")
                "<div class=`"blockContent`">"
                $blockContent
                "</div>"

                # Format block end
                "</div>"
            }

            # Display notices for this section
            if (($notices | Measure-Object).Count -gt 0)
            {
                "<div class=`"notice`">"
                "<h4>Notices</h4>"

                $output = $notices | Format-ReportRunnerNoticeHtml | ConvertTo-Html -As Table -Fragment | Update-ReportRunnerNoticeCellClass
                [System.Web.HttpUtility]::HtmlDecode($output)

                "</div>"
            }

            # Display block content
            $content | Out-String

            # Format section end
            "</div>"
        } | Out-String

        # Display all notices here
        "<div class=`"section`"><div class=`"notice`">"
        "<h3>All Notices</h3>"
        "<i>Notices generated by any section</i>"

        $output = $allNotices.Keys | ForEach-Object {
            $key = $_
            $allNotices[$key] | Format-ReportRunnerNoticeHtml -SectionName $key
        } | ConvertTo-Html -As Table -Fragment | Update-ReportRunnerNoticeCellClass
        [System.Web.HttpUtility]::HtmlDecode($output)

        "</div></div>"

        # Display all section content
        $allContent | ForEach-Object { $_ }

        # Wrap up HTML
        "</body></html>"
    }
}

Function Update-ReportRunnerNoticeCellClass
{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType('System.String')]
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline)]
        [AllowNull()]
        [string]$Content
    )

    process
    {
        $val = $Content

        $val = $val.Replace("<td>Warning</td>", "<td class=`"warningCell`">Warning</td>")
        $val = $val.Replace("<td>Error</td>", "<td class=`"errorCell`">Error</td>")
        $val = $val.Replace("<td>InternalError</td>", "<td class=`"internalErrorCell`">InternalError</td>")

        $val
    }
}

Function Format-ReportRunnerNoticeHtml
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline)]
        [ValidateNotNull()]
        [ReportRunnerNotice]$Notice,

        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$SectionName
    )

    process
    {
        # Format the description as Html ID reference, if SourceBlock has been defined
        $description = $_.Description
        if (![string]::IsNullOrEmpty($Notice.SourceBlock))
        {
            $description = ("<a href=`"#{0}`">{1}</a>" -f $_.SourceBlock, $description)
        }

        # Don't add the properties in here just yet. Want Section to be first, if specified
        $obj = [ordered]@{}

        # Add the section, if it has been defined
        if (![string]::IsNullOrEmpty($SectionName))
        {
            $obj["Section"] = $SectionName
        }

        # Add status and description properties
        $obj["Status"] = $_.Status
        $obj["Description"] = $description

        [PSCustomObject]$obj
    }
}