function Invoke-AtomicTest {
    [CmdletBinding(DefaultParameterSetName = 'technique',
        SupportsShouldProcess = $true,
        PositionalBinding = $false,
        ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $true,
            Position = 0,
            ValueFromPipelineByPropertyName = $true,
            ParameterSetName = 'technique')]
        [ValidateNotNullOrEmpty()]
        [String[]]
        $AtomicTechnique,

        [Parameter(Mandatory = $false,
            ValueFromPipelineByPropertyName = $true,
            ParameterSetName = 'technique')]
        [switch]
        $ShowDetails,

        [Parameter(Mandatory = $false,
            ValueFromPipelineByPropertyName = $true,
            ParameterSetName = 'technique')]
        [switch]
        $ShowDetailsBrief,

        [Parameter(Mandatory = $false,
            ParameterSetName = 'technique')]
        [String[]]
        $TestNumbers,

        [Parameter(Mandatory = $false,
            ParameterSetName = 'technique')]
        [String[]]
        $TestNames,

        [Parameter(Mandatory = $false,
            ParameterSetName = 'technique')]
        [String[]]
        $TestGuids,

        [Parameter(Mandatory = $false,
            ParameterSetName = 'technique')]
        [String]
        $PathToAtomicsFolder = $( if ($IsLinux -or $IsMacOS) { $Env:HOME + "/AtomicRedTeam/atomics" } else { $env:HOMEDRIVE + "\AtomicRedTeam\atomics" }),

        [Parameter(Mandatory = $false,
            ValueFromPipelineByPropertyName = $true,
            ParameterSetName = 'technique')]
        [switch]
        $CheckPrereqs = $false,

        [Parameter(Mandatory = $false,
            ValueFromPipelineByPropertyName = $true,
            ParameterSetName = 'technique')]
        [switch]
        $PromptForInputArgs = $false,

        [Parameter(Mandatory = $false,
            ValueFromPipelineByPropertyName = $true,
            ParameterSetName = 'technique')]
        [switch]
        $GetPrereqs = $false,

        [Parameter(Mandatory = $false,
            ValueFromPipelineByPropertyName = $true,
            ParameterSetName = 'technique')]
        [switch]
        $Cleanup = $false,

        [Parameter(Mandatory = $false,
            ParameterSetName = 'technique')]
        [switch]
        $NoExecutionLog = $false,

        [Parameter(Mandatory = $false,
            ParameterSetName = 'technique')]
        [String]
        $ExecutionLogPath = $( if ($IsLinux -or $IsMacOS) { "/tmp/Invoke-AtomicTest-ExecutionLog.csv" } else { "$env:TEMP\Invoke-AtomicTest-ExecutionLog.csv" }),

        [Parameter(Mandatory = $false,
            ParameterSetName = 'technique')]
        [switch]
        $Force,

        [Parameter(Mandatory = $false,
            ParameterSetName = 'technique')]
        [HashTable]
        $InputArgs,
    
        [Parameter(Mandatory = $false,
            ParameterSetName = 'technique')]
        [Int]
        $TimeoutSeconds = 120,

        [Parameter(Mandatory = $false, ParameterSetName = 'technique')]
        [System.Management.Automation.Runspaces.PSSession[]]$Session,

        [Parameter(Mandatory = $false,
            ValueFromPipelineByPropertyName = $true,
            ParameterSetName = 'technique')]
        [switch]
        $Interactive = $false,

        [Parameter(Mandatory = $false,
            ValueFromPipelineByPropertyName = $true,
            ParameterSetName = 'technique')]
        [switch]
        $KeepStdOutStdErrFiles = $false,

        [Parameter(Mandatory = $false,
            ParameterSetName = 'technique')]
        [String]
        $LoggingModule

    )
    BEGIN { } # Intentionally left blank and can be removed
    PROCESS {
        $PathToAtomicsFolder = (Resolve-Path $PathToAtomicsFolder).Path
        
        Write-Verbose -Message 'Attempting to run Atomic Techniques'
        Write-Host -ForegroundColor Cyan "PathToAtomicsFolder = $PathToAtomicsFolder`n"
        
        $executionPlatform, $isElevated, $tmpDir, $executionHostname, $executionUser = Get-TargetInfo $Session
        $PathToPayloads = if ($Session) { "$tmpDir`AtomicRedTeam" }  else { $PathToAtomicsFolder }

        Function Get-Logger {
            Param([string]$name)
            if (-not(Get-Module -name $name)) {
                if (Get-Module -ListAvailable |
                    Where-Object { $_.name -eq $name }) {
                    Import-Module -Name $name -Force
                    $true
                } #end if module available then import
                else {
                    $false
                } #module not available
            } # end if not module
            else {
                $true
            } #module already loaded
        } #end function Get-Logger

        $isLoggingModuleSet = $false
        if (-not $NoExecutionLog) {
            $isLoggingModuleSet = $true
            if (-not $PSBoundParameters.ContainsKey('LoggingModule')) {
                # use the syslog logger as default if the server and port are configured in the config file
                if ([bool]$artConfig.syslogServer -and [bool]$artConfig.syslogPort) {
                    Import-Module "$PSScriptRoot\Syslog-ExecutionLogger.psm1" -Force
                    $LoggingModule = "Syslog-ExecutionLogger"
                }
                else {
                    Import-Module "$PSScriptRoot\Default-ExecutionLogger.psm1" -Force
                    $LoggingModule = "Default-ExecutionLogger"
                }
            } 
            else {
                Remove-Module -Name "Default-ExecutionLogger" -erroraction silentlycontinue
                if (($PSBoundParameters['LoggingModule'] -eq "Syslog-ExecutionLogger") -and [bool]$artConfig.syslogServer -and [bool]$artConfig.syslogPort) {
                    Import-Module "$PSScriptRoot\Syslog-ExecutionLogger.psm1" -Force
                    $LoggingModule = "Syslog-ExecutionLogger"
                }
                else {
                    Remove-Module -Name "Syslog-ExecutionLogger" -erroraction silentlycontinue
                }
            }
        }

        if ($isLoggingModuleSet) {
            if (Get-Logger -name $LoggingModule) {
                Write-Verbose "Using Logger: $LoggingModule"
            }
            else {
                Write-Host "Logger not found: ", $LoggingModule
            }

            if ((Get-Command Start-ExecutionLog -erroraction silentlycontinue).Source -eq $LoggingModule) {
                if ((Get-Command Write-ExecutionLog -erroraction silentlycontinue).Source -eq $LoggingModule) {
                    if ((Get-Command Stop-ExecutionLog -erroraction silentlycontinue).Source -eq $LoggingModule) {
                        Write-Verbose "All logging commands found"
                    }
                    else {
                        Write-Host "Stop-ExecutionLog not found or loaded from the wrong module"
                        return
                    }
                }
                else {
                    Write-Host "Write-ExecutionLog not found or loaded from the wrong module"
                    return
                }
            }
            else {
                Write-Host "Start-ExecutionLog not found or loaded from the wrong module"
                return
            }
        }

        if ($isLoggingModuleSet) {
            # Since there might a comma(T1559-1,2,3) Powershell takes it as array.
            # So converting it back to string.
            if ($AtomicTechnique -is [array]) {
                $AtomicTechnique = $AtomicTechnique -join ","
            }
            
            # Splitting Atomic Technique short form into technique and test numbers.
            $AtomicTechniqueParams = ($AtomicTechnique -split '-')
            $AtomicTechnique = $AtomicTechniqueParams[0]

            if ($AtomicTechniqueParams.Length -gt 1) {
                $ShortTestNumbers = $AtomicTechniqueParams[-1]
            }

            if ($TestNumbers -eq $null -and $ShortTestNumbers -ne $null) {
                $TestNumbers = $ShortTestNumbers -split ','
            }
            
            # Here we're rebuilding an equivalent command line to put in the logs
            $commandLine = "Invoke-AtomicTest $AtomicTechnique"

            if ($ShowDetails -ne $false) {
                $commandLine = "$commandLine -ShowDetails $ShowDetails"
            }

            if ($ShowDetailsBrief -ne $false) {
                $commandLine = "$commandLine -ShowDetailsBrief $ShowDetailsBrief"
            }

            if ($TestNumbers -ne $null) {
                $commandLine = "$commandLine -TestNumbers $TestNumbers"
            }

            if ($TestNames -ne $null) {
                $commandLine = "$commandLine -TestNames $TestNames"
            }

            if ($TestGuids -ne $null) {
                $commandLine = "$commandLine -TestGuids $TestGuids"
            }

            $commandLine = "$commandLine -PathToAtomicsFolder $PathToAtomicsFolder"

            if ($CheckPrereqs -ne $false) {
                $commandLine = "$commandLine -CheckPrereqs $CheckPrereqs"
            }

            if ($PromptForInputArgs -ne $false) {
                $commandLine = "$commandLine -PromptForInputArgs $PromptForInputArgs"
            }

            if ($GetPrereqs -ne $false) {
                $commandLine = "$commandLine -GetPrereqs $GetPrereqs"
            }

            if ($Cleanup -ne $false) {
                $commandLine = "$commandLine -Cleanup $Cleanup"
            }

            if ($NoExecutionLog -ne $false) {
                $commandLine = "$commandLine -NoExecutionLog $NoExecutionLog"
            }

            $commandLine = "$commandLine -ExecutionLogPath $ExecutionLogPath"

            if ($Force -ne $false) {
                $commandLine = "$commandLine -Force $Force"
            }

            if ($InputArgs -ne $null) {
                $commandLine = "$commandLine -InputArgs $InputArgs"
            }

            $commandLine = "$commandLine -TimeoutSeconds $TimeoutSeconds"
            if ($PSBoundParameters.ContainsKey('Session')) {
                if ( $null -eq $Session ) {
                    Write-Error "The provided session is null and cannot be used."
                    continue
                } else {
                    $commandLine = "$commandLine -Session $Session"
                }
            }

            if ($Interactive -ne $false) {
                $commandLine = "$commandLine -Interactive $Interactive"
            }

            if ($KeepStdOutStdErrFiles -ne $false) {
                $commandLine = "$commandLine -KeepStdOutStdErrFiles $KeepStdOutStdErrFiles"
            }

            if ($LoggingModule -ne $null) {
                $commandLine = "$commandLine -LoggingModule $LoggingModule"
            }

            $startTime = Get-Date
            Start-ExecutionLog $startTime $ExecutionLogPath $executionHostname $executionUser $commandLine (-Not($IsLinux -or $IsMacOS))
        }

        function Platform-IncludesCloud {
            $cloud = ('office-365', 'azure-ad', 'google-workspace', 'saas', 'iaas', 'containers', 'iaas:aws', 'iaas:azure', 'iaas:gcp')
            foreach ($platform in $test.supported_platforms) {
                if ($cloud -contains $platform) {
                    return $true
                }
            }
            return $false
        }

        function Test-IncludesTerraform($AT, $testCount) {
            $AT = $AT.ToUpper()
            $pathToTerraform = Join-Path $PathToAtomicsFolder "\$AT\src\$AT-$testCount\$AT-$testCount.tf"
            $cloud = ('iaas', 'containers', 'iaas:aws', 'iaas:azure', 'iaas:gcp')
            foreach ($platform in $test.supported_platforms) {
                if ($cloud -contains $platform) {
                    return $(Test-Path -Path $pathToTerraform)
                }
            }
            return $false
        }

        function Build-TFVars($AT, $testCount, $InputArgs) {
            $tmpDirPath = Join-Path $PathToAtomicsFolder "\$AT\src\$AT-$testCount"
            if ($InputArgs) {
                $destinationVarsPath = Join-Path "$tmpDirPath" "terraform.tfvars.json"
                $InputArgs | ConvertTo-Json | Out-File -FilePath $destinationVarsPath
            }
        }

        function Remove-TerraformFiles($AT, $testCount) {
            $tmpDirPath = Join-Path $PathToAtomicsFolder "\$AT\src\$AT-$testCount"
            Write-Host $tmpDirPath
            $tfStateFile = Join-Path $tmpDirPath "terraform.tfstate"
            $tfvarsFile = Join-Path $tmpDirPath "terraform.tfvars.json"
            if ($(Test-Path $tfvarsFile)) {
                Remove-Item -LiteralPath $tfvarsFile -Force
            }
            if ($(Test-Path $tfStateFile)) {
                (Get-ChildItem -Path $tmpDirPath).Fullname -match "terraform.tfstate*" | Remove-Item -Force
            }
        }

        function Invoke-AtomicTestSingle ($AT) {

            $AT = $AT.ToUpper()
            $pathToYaml = Join-Path $PathToAtomicsFolder "\$AT\$AT.yaml"
            if (Test-Path -Path $pathToYaml) { $AtomicTechniqueHash = Get-AtomicTechnique -Path $pathToYaml }
            else {
                Write-Host -Fore Red "ERROR: $PathToYaml does not exist`nCheck your Atomic Number and your PathToAtomicsFolder parameter"
                return
            }
            $techniqueCount = 0

            foreach ($technique in $AtomicTechniqueHash) {

                $techniqueCount++

                $props = @{
                    Activity        = "Running $($technique.display_name.ToString()) Technique"
                    Status          = 'Progress:'
                    PercentComplete = ($techniqueCount / ($AtomicTechniqueHash).Count * 100)
                }
                Write-Progress @props

                Write-Debug -Message "Gathering tests for Technique $technique"

                $testCount = 0
                $order = 1
                foreach ($test in $technique.atomic_tests) {

                    Write-Verbose -Message 'Determining tests for target platform'

                    $testCount++
                    
                    if ( -not $(Platform-IncludesCloud) -and -Not $test.supported_platforms.Contains($executionPlatform) ) {
                        Write-Verbose -Message "Unable to run non-$executionPlatform tests"
                        continue
                    }

                    if ( $executionPlatform -eq "windows" -and ($test.executor.name -eq "sh" -or $test.executor.name -eq "bash")) {
                        Write-Verbose -Message "Unable to run sh or bash on $executionPlatform"
                        continue    
                    }
                    if ( ("linux", "macos") -contains $executionPlatform -and $test.executor.name -eq "command_prompt") {
                        Write-Verbose -Message "Unable to run cmd.exe on $executionPlatform"
                        continue    
                    }
                    

                    if ($null -ne $TestNumbers) {
                        if (-Not ($TestNumbers -contains $testCount) ) { continue }
                    }

                    if ($null -ne $TestNames) {
                        if (-Not ($TestNames -contains $test.name) ) { continue }
                    }

                    if ($null -ne $TestGuids) {
                        if (-Not ($TestGuids -contains $test.auto_generated_guid) ) { continue }
                    }

                    $props = @{
                        Activity        = 'Running Atomic Tests'
                        Status          = 'Progress:'
                        PercentComplete = ($testCount / ($technique.atomic_tests).Count * 100)
                    }
                    Write-Progress @props

                    Write-Verbose -Message 'Determining manual tests'

                    if ($test.executor.name.Contains('manual')) {
                        Write-Verbose -Message 'Unable to run manual tests'
                        continue
                    }

                    $testId = "$AT-$testCount $($test.name)"
                    if ($ShowDetailsBrief) {
                        Write-KeyValue $testId
                        continue
                    }

                    if ($PromptForInputArgs) {
                        $InputArgs = Invoke-PromptForInputArgs $test.input_arguments
                    }

                    if ($ShowDetails) {
                        Show-Details $test $testCount $technique $InputArgs $PathToPayloads
                        continue
                    }

                    Write-Debug -Message 'Gathering final Atomic test command'


                    if ($CheckPrereqs) {
                        Write-KeyValue "CheckPrereq's for: " $testId
                        $failureReasons = Invoke-CheckPrereqs $test $isElevated $executionPlatform $InputArgs $PathToPayloads $TimeoutSeconds $session
                        Write-PrereqResults $FailureReasons $testId
                    }
                    elseif ($GetPrereqs) {
                        if ($(Test-IncludesTerraform $AT $testCount)) {
                            Build-TFVars $AT $testCount $InputArgs
                        }
                        Write-KeyValue "GetPrereq's for: " $testId
                        if ( $test.executor.elevation_required -and -not $isElevated) {
                            Write-Host -ForegroundColor Red "Elevation required but not provided"
                        }
                        if ($nul -eq $test.dependencies) { Write-KeyValue "No Preqs Defined"; continue }
                        foreach ($dep in $test.dependencies) {
                            $executor = Get-PrereqExecutor $test
                            $description = (Merge-InputArgs $dep.description $test $InputArgs $PathToPayloads).trim()
                            Write-KeyValue  "Attempting to satisfy prereq: " $description
                            $final_command_prereq = Merge-InputArgs $dep.prereq_command $test $InputArgs $PathToPayloads
                            if ($executor -ne "powershell") { $final_command_prereq = ($final_command_prereq.trim()).Replace("`n", " && ") }
                            $final_command_get_prereq = Merge-InputArgs $dep.get_prereq_command $test $InputArgs $PathToPayloads
                            $res = Invoke-ExecuteCommand $final_command_prereq $executor $executionPlatform $TimeoutSeconds $session -Interactive:$true

                            if ($res.ExitCode -eq 0) {
                                Write-KeyValue "Prereq already met: " $description
                            }
                            else {
                                $res = Invoke-ExecuteCommand $final_command_get_prereq $executor $executionPlatform $TimeoutSeconds $session -Interactive:$Interactive
                                $res = Invoke-ExecuteCommand $final_command_prereq $executor $executionPlatform $TimeoutSeconds $session -Interactive:$true
                                if ($res.ExitCode -eq 0) {
                                    Write-KeyValue "Prereq successfully met: " $description
                                }
                                else {
                                    Write-Host -ForegroundColor Red "Failed to meet prereq: $description"
                                }
                            }
                        }
                    }
                    elseif ($Cleanup) {
                        Write-KeyValue "Executing cleanup for test: " $testId
                        $final_command = Merge-InputArgs $test.executor.cleanup_command $test $InputArgs $PathToPayloads
                        $res = Invoke-ExecuteCommand $final_command $test.executor.name $executionPlatform $TimeoutSeconds $session -Interactive:$Interactive
                        Write-KeyValue "Done executing cleanup for test: " $testId
                        if ($(Test-IncludesTerraform $AT $testCount)) {
                            Remove-TerraformFiles $AT $testCount
                        }
                    }
                    else {
                        Write-KeyValue "Executing test: " $testId
                        $startTime = Get-Date
                        $final_command = Merge-InputArgs $test.executor.command $test $InputArgs $PathToPayloads
                        $res = Invoke-ExecuteCommand $final_command $test.executor.name $executionPlatform $TimeoutSeconds $session -Interactive:$Interactive
                        $stopTime = Get-Date
                        if ($isLoggingModuleSet) {
                            Write-ExecutionLog $startTime $stopTime $AT $order $test.name $test.auto_generated_guid $test.executor.name $test.description $final_command $ExecutionLogPath $executionHostname $executionUser $res (-Not($IsLinux -or $IsMacOS))
                            $order++
                        }
                        Write-KeyValue "Done executing test: " $testId
                    }
                } # End of foreach Test in single Atomic Technique
            } # End of foreach Technique in Atomic Tests
        } # End of Invoke-AtomicTestSingle function

        if ($AtomicTechnique -eq "All") {
            function Invoke-AllTests() {
                $AllAtomicTests = New-Object System.Collections.ArrayList
                Get-ChildItem $PathToAtomicsFolder -Directory -Filter T* | ForEach-Object {
                    $currentTechnique = [System.IO.Path]::GetFileName($_.FullName)
                    if ( $currentTechnique -match "T[0-9]{4}.?([0-9]{3})?" ) { $AllAtomicTests.Add($currentTechnique) | Out-Null }
                }
                $AllAtomicTests.GetEnumerator() | Foreach-Object { Invoke-AtomicTestSingle $_ }
            }
        
            if ( ($Force -or $CheckPrereqs -or $ShowDetails -or $ShowDetailsBrief -or $GetPrereqs) -or $psCmdlet.ShouldContinue( 'Do you wish to execute all tests?',
                    "Highway to the danger zone, Executing All Atomic Tests!" ) ) {
                Invoke-AllTests
            }
        }
        else {
            Invoke-AtomicTestSingle $AtomicTechnique
        }

        if ($isLoggingModuleSet) {
            Stop-ExecutionLog $startTime $ExecutionLogPath $executionHostname $executionUser (-Not($IsLinux -or $IsMacOS))
        }

    } # End of PROCESS block
    END { } # Intentionally left blank and can be removed
}