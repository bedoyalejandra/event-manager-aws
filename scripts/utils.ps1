# 🛠️ PowerShell Utilities - Event Manager AWS
# Reusable functions for all PowerShell scripts

# Global variables for debugging
$global:DebugMode = $false

# Console colors (using Write-Host with colors)
function Write-LogInfo {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

function Write-LogSuccess {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-LogWarning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-LogError {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Write-LogDebug {
    param([string]$Message)
    if ($global:DebugMode) {
        Write-Host "[DEBUG] $Message" -ForegroundColor Cyan
    }
}

# Function to show progress
function Show-Progress {
    param(
        [string]$Step,
        [int]$Total,
        [string]$Description
    )
    
    Write-Host ""
    Write-Host "=== STEP $Step/$Total`: $Description ===" -ForegroundColor Blue
    Write-Host ""
}

# Function to show headers
function Show-Header {
    param(
        [string]$Title,
        [string]$Color = "Blue"
    )
    
    Write-Host ""
    Write-Host "=== $Title ===" -ForegroundColor $Color
}

# Function to show banners
function Show-Banner {
    param(
        [string]$Title,
        [string]$Subtitle = "",
        [string]$Color = "Green"
    )
    
    $border = "╔══════════════════════════════════════════════════════════════╗"
    $emptyLine = "║" + (" " * 62) + "║"
    
    Write-Host $border -ForegroundColor $Color
    Write-Host $emptyLine -ForegroundColor $Color
    
    # Center the title
    $titlePadding = (62 - $Title.Length) / 2
    $leftPadding = [math]::Floor($titlePadding)
    $rightPadding = [math]::Ceiling($titlePadding)
    $titleLine = "║" + (" " * $leftPadding) + $Title + (" " * $rightPadding) + "║"
    Write-Host $titleLine -ForegroundColor $Color
    
    if (-not [string]::IsNullOrEmpty($Subtitle)) {
        $subtitlePadding = (62 - $Subtitle.Length) / 2
        $leftPadding = [math]::Floor($subtitlePadding)
        $rightPadding = [math]::Ceiling($subtitlePadding)
        $subtitleLine = "║" + (" " * $leftPadding) + $Subtitle + (" " * $rightPadding) + "║"
        Write-Host $subtitleLine -ForegroundColor $Color
    }
    
    Write-Host $emptyLine -ForegroundColor $Color
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor $Color
    Write-Host ""
}

# Function to verify AWS credentials
function Test-AWSCredentials {
    Write-LogInfo "Verifying AWS credentials..."
    
    try {
        $callerIdentity = aws sts get-caller-identity 2>$null | ConvertFrom-Json
        
        if ($null -eq $callerIdentity) {
            Write-LogError "Could not obtain AWS credentials."
            Write-LogError "Please run 'aws configure' first."
            return $false
        }
        
        $accountId = $callerIdentity.Account
        $currentUser = $callerIdentity.Arn
        $currentRegion = aws configure get region
        
        Write-LogSuccess "Valid AWS credentials:"
        Write-LogInfo "  - Account ID: $accountId"
        Write-LogInfo "  - User: $currentUser"
        Write-LogInfo "  - Region: $currentRegion"
        
        # Export variables for use in other scripts
        $global:AWS_ACCOUNT_ID = $accountId
        $global:AWS_USER_ARN = $currentUser
        $global:AWS_CURRENT_REGION = $currentRegion
        
        return $true
    } catch {
        Write-LogError "Error verifying AWS credentials: $_"
        return $false
    }
}

# Function to verify project structure
function Test-ProjectStructure {
    Write-LogInfo "Verifying project structure..."
    
    $requiredFiles = @(
        "infra/master-template.yml",
        "src"
    )
    
    foreach ($file in $requiredFiles) {
        if (-not (Test-Path $file)) {
            Write-LogError "Not found: $file"
            Write-LogError "Make sure you are in the correct project directory."
            return $false
        }
    }
    
    Write-LogSuccess "Project structure verified"
    return $true
}

# Function to wait for user confirmation
function Confirm-Action {
    param(
        [string]$Message,
        [string]$DefaultResponse = "n"
    )
    
    if ($DefaultResponse -eq "y") {
        $prompt = "$Message (Y/n): "
    } else {
        $prompt = "$Message (y/N): "
    }
    
    $response = Read-Host $prompt
    
    if ($DefaultResponse -eq "y") {
        return $response -notmatch "^[Nn]$"
    } else {
        return $response -match "^[Yy]$"
    }
}

# Function to wait for stack operation completion
function Wait-ForStackOperation {
    param(
        [string]$StackName,
        [string]$Operation = "CREATE",  # CREATE, UPDATE, DELETE
        [int]$Timeout = 1800  # 30 minutes default
    )
    
    Write-LogInfo "Waiting for $Operation operation to complete on stack: $StackName"
    
    $startTime = Get-Date
    $spinnerChars = @("⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏")
    $spinnerIndex = 0
    
    while ($true) {
        $elapsed = (Get-Date) - $startTime
        
        if ($elapsed.TotalSeconds -gt $Timeout) {
            Write-LogError "Timeout waiting for $Operation operation on stack $StackName"
            return $false
        }
        
        try {
            $status = aws cloudformation describe-stacks --stack-name $StackName --query 'Stacks[0].StackStatus' --output text 2>$null
        } catch {
            $status = "NOT_FOUND"
        }
        
        switch ($Operation) {
            "CREATE" {
                if ($status -eq "CREATE_COMPLETE") {
                    Write-LogSuccess "Stack $StackName created correctly"
                    return $true
                } elseif ($status -in @("CREATE_FAILED", "ROLLBACK_COMPLETE")) {
                    Write-LogError "Error creating stack $StackName (Status: $status)"
                    return $false
                }
            }
            "UPDATE" {
                if ($status -eq "UPDATE_COMPLETE") {
                    Write-LogSuccess "Stack $StackName updated correctly"
                    return $true
                } elseif ($status -in @("UPDATE_FAILED", "UPDATE_ROLLBACK_COMPLETE")) {
                    Write-LogError "Error updating stack $StackName (Status: $status)"
                    return $false
                }
            }
            "DELETE" {
                if ($status -eq "NOT_FOUND") {
                    Write-LogSuccess "Stack $StackName deleted correctly"
                    return $true
                } elseif ($status -eq "DELETE_FAILED") {
                    Write-LogError "Error deleting stack $StackName"
                    return $false
                }
            }
        }
        
        # Show spinner
        $spinnerChar = $spinnerChars[$spinnerIndex]
        Write-Host -NoNewline "`r[INFO] Current status: $status $spinnerChar ($([math]::Round($elapsed.TotalSeconds))s)"
        $spinnerIndex = ($spinnerIndex + 1) % $spinnerChars.Length
        
        Start-Sleep 5
    }
}

# Function to get stack outputs
function Get-StackOutput {
    param(
        [string]$StackName,
        [string]$OutputKey
    )
    
    try {
        $output = aws cloudformation describe-stacks --stack-name $StackName --query "Stacks[0].Outputs[?OutputKey=='$OutputKey'].OutputValue" --output text 2>$null
        return $output
    } catch {
        return ""
    }
}

# Function to list event-manager related stacks
function Get-EventManagerStacks {
    param(
        [string]$StatusFilter = "CREATE_COMPLETE UPDATE_COMPLETE"
    )
    
    $statusArray = $StatusFilter -split " "
    $filter = ($statusArray | ForEach-Object { "'$_'" }) -join " "
    
    aws cloudformation list-stacks --stack-status-filter $statusArray --query 'StackSummaries[?contains(StackName, `event-manager`)].{Name:StackName,Status:StackStatus,Created:CreationTime}' --output table
}

# Function to validate CloudFormation template
function Test-Template {
    param([string]$TemplateFile)
    
    Write-LogInfo "Validating template: $TemplateFile"
    
    if (-not (Test-Path $TemplateFile)) {
        Write-LogError "Template not found: $TemplateFile"
        return $false
    }
    
    try {
        aws cloudformation validate-template --template-body "file://$TemplateFile" >$null 2>&1
        Write-LogSuccess "Valid template: $TemplateFile"
        return $true
    } catch {
        Write-LogError "Invalid template: $TemplateFile"
        aws cloudformation validate-template --template-body "file://$TemplateFile"
        return $false
    }
}

# Function to clean temporary files
function Clear-TempFiles {
    $files = @("lambda-functions.zip", "response.json", "temp-*.json", "*.tmp")
    
    Write-LogInfo "Cleaning temporary files..."
    
    foreach ($pattern in $files) {
        $matchingFiles = Get-ChildItem -Path . -Name $pattern -ErrorAction SilentlyContinue
        if ($matchingFiles) {
            Remove-Item $matchingFiles -Force
            Write-LogDebug "Deleted: $pattern"
        }
    }
    
    Write-LogSuccess "Temporary files cleaned"
}

# Function to show elapsed time
function Show-ElapsedTime {
    param([datetime]$StartTime)
    
    $endTime = Get-Date
    $elapsed = $endTime - $StartTime
    
    $hours = [math]::Floor($elapsed.TotalHours)
    $minutes = [math]::Floor($elapsed.Minutes)
    $seconds = [math]::Floor($elapsed.Seconds)
    
    if ($hours -gt 0) {
        Write-LogInfo "Elapsed time: ${hours}h ${minutes}m ${seconds}s"
    } elseif ($minutes -gt 0) {
        Write-LogInfo "Elapsed time: ${minutes}m ${seconds}s"
    } else {
        Write-LogInfo "Elapsed time: ${seconds}s"
    }
}

# Function to check if command exists
function Test-Command {
    param([string]$Command)
    
    try {
        Get-Command $Command -ErrorAction Stop >$null
        return $true
    } catch {
        return $false
    }
}

# Function to check dependencies
function Test-Dependencies {
    $dependencies = @("aws", "npm", "node")
    $missingDeps = @()
    
    Write-LogInfo "Checking dependencies..."
    
    foreach ($dep in $dependencies) {
        if (-not (Test-Command $dep)) {
            $missingDeps += $dep
        }
    }
    
    if ($missingDeps.Count -gt 0) {
        Write-LogError "Missing dependencies: $($missingDeps -join ', ')"
        Write-LogError "Please install the missing dependencies before continuing."
        return $false
    }
    
    Write-LogSuccess "All dependencies are available"
    return $true
}

# Function to create configuration backup
function New-ConfigBackup {
    $backupDir = "backups\$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    
    Write-LogInfo "Creating configuration backup..."
    
    New-Item -ItemType Directory -Path $backupDir -Force >$null
    
    # Backup parameters
    if (Test-Path "infra\parameters") {
        Copy-Item -Path "infra\parameters" -Destination $backupDir -Recurse
    }
    
    # Backup environment variables
    if (Test-Path ".env") {
        Copy-Item -Path ".env" -Destination $backupDir
    }
    
    Write-LogSuccess "Backup created in: $backupDir"
    return $backupDir
}

# Function to show help
function Show-Help {
    param([string]$ScriptName)
    
    Write-Host "Usage: $ScriptName [options]" -ForegroundColor White
    Write-Host ""
    Write-Host "Available parameters:" -ForegroundColor White
    Write-Host "  -Environment     - Deployment environment (dev/prod) [default: dev]"
    Write-Host "  -DBUsername      - Database username [default: event_admin]"
    Write-Host "  -AWSRegion       - AWS region [default: configured region]"
    Write-Host "  -Debug           - Show debug messages [default: false]"
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor White
    Write-Host "  .\$ScriptName"
    Write-Host "  .\$ScriptName -Environment prod"
    Write-Host "  .\$ScriptName -Debug"
}

# Initialization message
Write-LogDebug "PowerShell utilities loaded correctly"
