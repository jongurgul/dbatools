function Install-DbaFirstResponderKit {
    <#
    .SYNOPSIS
        Installs or updates the First Responder Kit stored procedures.

    .DESCRIPTION
        Downloads, extracts and installs the First Responder Kit stored procedures:
        sp_Blitz, sp_BlitzWho, sp_BlitzFirst, sp_BlitzIndex, sp_BlitzCache and sp_BlitzTrace, etc.

        First Responder Kit links:
        http://FirstResponderKit.org
        https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the database to install the First Responder Kit stored procedures into

    .PARAMETER Branch
        Specifies an alternate branch of the First Responder Kit to install. (master or dev)

    .PARAMETER LocalFile
        Specifies the path to a local file to install FRK from. This *should* be the zip file as distributed by the maintainers.
        If this parameter is not specified, the latest version will be downloaded and installed from https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit

    .PARAMETER Force
        If this switch is enabled, the FRK will be downloaded from the internet even if previously cached.

    .PARAMETER Confirm
        Prompts to confirm actions

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Community, FirstResponderKit
        Author: Tara Kizer, Brent Ozar Unlimited (https://www.brentozar.com/)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        https://www.brentozar.com/responder

    .LINK
        https://dbatools.io/Install-DbaFirstResponderKit

    .EXAMPLE
        PS C:\> Install-DbaFirstResponderKit -SqlInstance server1 -Database master

        Logs into server1 with Windows authentication and then installs the FRK in the master database.

    .EXAMPLE
        PS C:\> Install-DbaFirstResponderKit -SqlInstance server1\instance1 -Database DBA

        Logs into server1\instance1 with Windows authentication and then installs the FRK in the DBA database.

    .EXAMPLE
        PS C:\> Install-DbaFirstResponderKit -SqlInstance server1\instance1 -Database master -SqlCredential $cred

        Logs into server1\instance1 with SQL authentication and then installs the FRK in the master database.

    .EXAMPLE
        PS C:\> Install-DbaFirstResponderKit -SqlInstance sql2016\standardrtm, sql2016\sqlexpress, sql2014

        Logs into sql2016\standardrtm, sql2016\sqlexpress and sql2014 with Windows authentication and then installs the FRK in the master database.

    .EXAMPLE
        PS C:\> $servers = "sql2016\standardrtm", "sql2016\sqlexpress", "sql2014"
        PS C:\> $servers | Install-DbaFirstResponderKit

        Logs into sql2016\standardrtm, sql2016\sqlexpress and sql2014 with Windows authentication and then installs the FRK in the master database.

    .EXAMPLE
        PS C:\> Install-DbaFirstResponderKit -SqlInstance sql2016 -Branch dev

        Installs the dev branch version of the FRK in the master database on sql2016 instance.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$Branch = "master",
        [object]$Database = "master",
        [string]$LocalFile,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        $DbatoolsData = Get-DbatoolsConfigValue -FullName "Path.DbatoolsData"

        if (-not $DbatoolsData) {
            $DbatoolsData = [System.IO.Path]::GetTempPath()
        }
        $temp = [System.IO.Path]::GetTempPath()
        if ($Branch -eq 'master') {
            $url = 'https://api.github.com/repos/BrentOzarULTD/SQL-Server-First-Responder-Kit/releases/latest'
            $zipFile = Join-Path -Path $temp -ChildPath "SQL-Server-First-Responder-Kit-latest.zip"
        } elseif ($Branch -eq 'dev') {
            $url = "https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/archive/dev.zip"
            $zipfile = Join-Path -Path $temp -ChildPath "SQL-Server-First-Responder-Kit-dev.zip"
        } else {
            Write-Message -Level Warning -Message "Unknown value provided for Branch parameter"
        }

        if ($LocalFile) {
            if (-not(Test-Path $LocalFile)) {
                if ($PSCmdlet.ShouldProcess($LocalFile, "File does not exists, returning to prompt")) {
                    Stop-Function -Message "$LocalFile doesn't exist"
                    return
                }
            }
            if (-not($LocalFile.EndsWith('.zip'))) {
                if ($PSCmdlet.ShouldProcess($LocalFile, "File is not a zip file, returning to prompt")) {
                    Stop-Function -Message "$LocalFile should be a zip file"
                    return
                }
            }
        }

        if ($Force -or -not(Test-Path -Path $LocalCachedCopy -PathType Container) -or $LocalFile) {
            # Force was passed, or we don't have a local copy, or $LocalFile was passed
            if ($zipfile | Test-Path) {
                if ($PSCmdlet.ShouldProcess($zipfile, "File found, dropping $zipfile")) {
                    Remove-Item -Path $zipfile -ErrorAction SilentlyContinue
                }
            }

            # $null = New-Item -ItemType Directory -Path $zipfolder -ErrorAction SilentlyContinue
            if ($LocalFile) {
                if (Test-Windows -NoWarn) {
                    if ($PSCmdlet.ShouldProcess($LocalFile, "Checking if Windows system, unblocking file")) {
                        Unblock-File $LocalFile -ErrorAction SilentlyContinue
                    }
                }
                if ($PSCmdlet.ShouldProcess($LocalFile, "Extracting archive to $temp path")) {
                    Expand-Archive -Path $LocalFile -DestinationPath $temp -Force
                }
            } else {
                Write-Message -Level Verbose -Message "Downloading and unzipping the First Responder Kit zip file."
                try {
                    if ($PSCmdlet.ShouldProcess($url, "Downloading zip file")) {
                        try {
                            if ($Branch -eq 'master') {
                                $zipball = (Invoke-TlsWebRequest $url | ConvertFrom-Json).zipball_url
                                Invoke-TlsWebRequest $zipball -OutFile $zipfile -ErrorAction Stop -UseBasicParsing
                            } else {
                                Invoke-TlsWebRequest $url -OutFile $zipfile -ErrorAction Stop -UseBasicParsing
                            }
                        } catch {
                            # Try with default proxy and usersettings
                            (New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
                            if ($Branch -eq 'master') {
                                $zipball = (Invoke-TlsWebRequest $url | ConvertFrom-Json).zipball_url
                                Invoke-TlsWebRequest $zipball -OutFile $zipfile -ErrorAction Stop -UseBasicParsing
                            } else {
                                Invoke-TlsWebRequest $url -OutFile $zipfile -ErrorAction Stop -UseBasicParsing
                            }
                        }
                    }

                    # Unblock if there's a block
                    if ($PSCmdlet.ShouldProcess($zipfile, "Expanding archive file")) {
                        if (Test-Windows -NoWarn) {
                            Unblock-File $zipfile -ErrorAction SilentlyContinue
                        }

                        Expand-Archive -Path $zipfile -DestinationPath $temp -Force
                        Remove-Item -Path $zipfile
                    }
                } catch {
                    $message =
                    if ($Branch -eq 'master') {
                        "Could not download the file. You may need to manually download from https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/releases"
                    } else {
                        "Could not download the file. You may need to manually download from https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/archive/$Branch.zip"
                    }
                    Stop-Function -Message $message -ErrorRecord $_
                    return
                }
            }

            ## Copy it into local area
            $tempFolder = Get-ChildItem $temp -Filter "*SQL-Server-First-Responder-Kit*" -Directory
            $LocalCachedCopy = Join-Path $dbatoolsData -Child (Split-Path $tempFolder -Leaf)
            if ($PSCmdlet.ShouldProcess("LocalCachedCopy", "Copying extracted files to the local module cache")) {
                if (Test-Path -Path $LocalCachedCopy -PathType Container) {
                    Remove-Item -Path (Join-Path $LocalCachedCopy '*') -Recurse -ErrorAction SilentlyContinue
                } else {
                    $null = New-Item -Path $LocalCachedCopy -ItemType Container
                }

                Copy-Item -Path $tempFolder -Destination $LocalCachedCopy -Recurse
            }
        }
    }

    process {
        if (Test-FunctionInterrupt) {
            return
        }

        foreach ($instance in $SqlInstance) {
            if ($PSCmdlet.ShouldProcess($instance, "Connecting to $instance")) {
                try {
                    $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
                } catch {
                    Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                }
            }

            if ($PSCmdlet.ShouldProcess($database, "Installing FRK procedures in $database on $instance")) {
                Write-Message -Level Verbose -Message "Starting installing/updating the First Responder Kit stored procedures in $database on $instance."
                $allprocedures_query = "select name from sys.procedures where is_ms_shipped = 0"
                $allprocedures = ($server.Query($allprocedures_query, $Database)).Name

                # Install/Update each FRK stored procedure
                foreach ($script in (Get-ChildItem $LocalCachedCopy -Recurse -Filter "sp_*.sql")) {
                    $scriptName = $script.Name
                    $scriptError = $false

                    $baseres = [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Database     = $Database
                        Name         = $script.BaseName
                        Status       = $null
                    }

                    if ($scriptName -eq "sp_BlitzQueryStore.sql" -and ($server.VersionMajor -lt 13)) {
                        Write-Message -Level Warning -Message "$instance found to be below SQL Server 2016, skipping sp_BlitzQueryStore.sql"
                        $baseres.Status = 'Skipped'
                        $baseres
                        continue
                    }
                    if ($scriptName -eq "sp_BlitzInMemoryOLTP.sql" -and ($server.VersionMajor -lt 12)) {
                        Write-Message -Level Warning -Message "$instance found to be below SQL Server 2014, not installing sp_BlitzQueryStore.sql"
                        $baseres.Status = 'Skipped'
                        $baseres
                        continue
                    }
                    if ($Pscmdlet.ShouldProcess($instance, "installing/updating $scriptName in $database.")) {
                        try {
                            Invoke-DbaQuery -SqlInstance $server -Database $Database -File $script.FullName -EnableException -Verbose:$false
                        } catch {
                            Write-Message -Level Warning -Message "Could not execute at least one portion of $scriptName in $Database on $instance." -ErrorRecord $_
                            $scriptError = $true
                        }
                        if ($scriptError) {
                            $baseres.Status = 'Error'
                        } elseif ($script.BaseName -in $allprocedures) {
                            $baseres.Status = 'Updated'
                        } else {
                            $baseres.Status = 'Installed'
                        }
                        $baseres
                    }
                }
            }
            Write-Message -Level Verbose -Message "Finished installing/updating the First Responder Kit stored procedures in $database on $instance."
        }
    }
}
