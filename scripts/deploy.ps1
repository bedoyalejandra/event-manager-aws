# 🚀 PowerShell Deployment Script - Event Manager AWS
# Windows-compatible version of deploy.sh

param(
    [string]$Environment = "dev",
    [string]$DBUsername = "event_admin", 
    [string]$AWSRegion = "",
    [switch]$Debug = $false
)

# Error handling - stop on any error
$ErrorActionPreference = "Stop"

# Import utilities
. "$PSScriptRoot\utils.ps1"

# Set debug mode
if ($Debug) { $global:DebugMode = $true }

# Configuration 
if ([string]::IsNullOrEmpty($AWSRegion)) {
    $AWSRegion = aws configure get region
    if ([string]::IsNullOrEmpty($AWSRegion)) {
        $AWSRegion = "us-west-2"
    }
}

Show-Banner "EVENT MANAGER AWS DEPLOY" "PowerShell Script"

Write-LogInfo "Configuration:"
Write-LogInfo "  - Environment: $Environment"
Write-LogInfo "  - DB Username: $DBUsername"
Write-LogInfo "  - AWS Region: $AWSRegion"

# STEP 0: Pre-checks
Show-Progress 0 10 "Pre-checks"

if (-not (Test-AWSCredentials)) { exit 1 }
if (-not (Test-ProjectStructure)) { exit 1 }

# Check existing stacks
Write-LogInfo "Checking existing stacks..."
$existingStacks = aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE --query 'StackSummaries[?contains(StackName, `event-manager`)].StackName' --output text

if (-not [string]::IsNullOrEmpty($existingStacks)) {
    Write-LogWarning "Found existing stacks: $existingStacks"
    $continue = Read-Host "Do you want to continue? This might update existing stacks (y/N)"
    if ($continue -ne "y" -and $continue -ne "Y") {
        Write-LogInfo "Deployment cancelled by user."
        exit 0
    }
}

# STEP 1: Prepare environment
Show-Progress 1 10 "Preparing Environment"

Write-LogInfo "Setting up environment variables..."
$env:AWS_DEFAULT_REGION = $AWSRegion
$env:ENVIRONMENT = $Environment
$env:DB_USERNAME = $DBUsername

Write-LogSuccess "Environment variables configured"

# STEP 2: Install dependencies and package Lambda functions
Show-Progress 2 10 "Installing Dependencies and Packaging Lambda Functions"

Write-LogInfo "Installing Node.js dependencies..."
Set-Location src

if (-not (Test-Path "package.json")) {
    Write-LogError "package.json not found in src/ directory"
    exit 1
}

npm install
Write-LogSuccess "Dependencies installed correctly"

Write-LogInfo "Creating ZIP file with Lambda functions..."
if (Test-Path "lambda-functions.zip") {
    Write-LogWarning "Removing existing lambda-functions.zip..."
    Remove-Item "lambda-functions.zip" -Force
}

# Create ZIP using PowerShell
$compress = @{
    Path = Get-ChildItem -Exclude "*.zip", "package-lock.json" -Recurse | ForEach-Object { $_.FullName }
    DestinationPath = "lambda-functions.zip"
    CompressionLevel = "Optimal"
}
Compress-Archive @compress

$zipSize = (Get-Item "lambda-functions.zip").Length
$zipSizeMB = [math]::Round($zipSize / 1MB, 2)
Write-LogSuccess "lambda-functions.zip created (Size: ${zipSizeMB}MB)"

# Verify dependencies are included
Write-LogInfo "Verifying dependencies are included..."
$zipContent = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path "lambda-functions.zip"))
$hasMySQL = $zipContent.Entries | Where-Object { $_.FullName -like "*node_modules/mysql2*" }
$zipContent.Dispose()

if ($hasMySQL) {
    Write-LogSuccess "✅ mysql2 dependencies included in ZIP"
} else {
    Write-LogError "❌ mysql2 dependencies NOT found in ZIP"
    exit 1
}

# Move ZIP to project root
Move-Item "lambda-functions.zip" "../"
Set-Location ..

Write-LogInfo "Cleaning temporary node_modules..."
Remove-Item "src/node_modules" -Recurse -Force
Write-LogSuccess "Cleanup completed"

# STEP 3: Create S3 bucket for Lambda code
Show-Progress 3 10 "Creating S3 Bucket for Lambda Code"

$accountId = aws sts get-caller-identity --query Account --output text
$lambdaBucketName = "event-manager-lambda-code-$Environment-$accountId"
$reportsBucketName = "event-manager-reports-$Environment-$accountId"

Write-LogInfo "Checking if S3 buckets already exist..."
try {
    aws s3api head-bucket --bucket $lambdaBucketName 2>$null
    Write-LogWarning "Lambda bucket already exists: $lambdaBucketName"
    $useExistingBuckets = $true
} catch {
    Write-LogInfo "Lambda bucket does not exist, will create: $lambdaBucketName"
    $useExistingBuckets = $false
}

Write-LogInfo "Deploying S3 template..."
if ($useExistingBuckets) {
    Write-LogInfo "Using existing buckets..."
    aws cloudformation deploy --template-file infra/templates/s3.yml --stack-name event-manager-s3 --capabilities CAPABILITY_IAM --parameter-overrides Environment=$Environment CreateS3Buckets=false ExistingLambdaCodeBucket=$lambdaBucketName ExistingReportsBucket=$reportsBucketName
} else {
    Write-LogInfo "Creating new buckets..."
    aws cloudformation deploy --template-file infra/templates/s3.yml --stack-name event-manager-s3 --capabilities CAPABILITY_IAM --parameter-overrides Environment=$Environment
}

Write-LogSuccess "event-manager-s3 stack deployed correctly"

# STEP 4: Get bucket information
Show-Progress 4 10 "Getting S3 Bucket Information"

Write-LogInfo "Getting Lambda bucket name..."
$lambdaBucket = Get-StackOutput "event-manager-s3" "LambdaCodeBucketName"

if ([string]::IsNullOrEmpty($lambdaBucket)) {
    Write-LogWarning "Could not get bucket name from stack, using previously determined name"
    $lambdaBucket = $lambdaBucketName
}

Write-LogSuccess "Lambda bucket obtained: $lambdaBucket"

# STEP 5: Upload Lambda code to bucket
Show-Progress 5 10 "Uploading Lambda Code to Bucket"

Write-LogInfo "Uploading lambda-functions.zip to S3 bucket..."
aws s3 cp lambda-functions.zip s3://$lambdaBucket/lambda-functions.zip

Write-LogInfo "Verifying file was uploaded correctly..."
aws s3 ls s3://$lambdaBucket/lambda-functions.zip

Write-LogSuccess "Lambda code uploaded correctly"

# STEP 6: Upload nested stack templates to S3
Show-Progress 6 10 "Uploading Nested Stack Templates"

Write-LogInfo "Uploading nested stack templates to S3 bucket..."
aws s3 cp infra/templates/ s3://$lambdaBucket/templates/ --recursive --exclude "*.md"

Write-LogInfo "Verifying templates were uploaded correctly..."
aws s3 ls s3://$lambdaBucket/templates/

Write-LogSuccess "Nested stack templates uploaded correctly"

# STEP 7: Validate main template
Show-Progress 7 10 "Validating Main Template"

if (-not (Test-Template "infra/master-template.yml")) { exit 1 }

# STEP 8: Create RDS database
Show-Progress 8 10 "Creating MySQL Database"

Write-LogInfo "Checking if database already exists..."
try {
    $dbEndpoint = aws rds describe-db-instances --db-instance-identifier "event-manager-db-$Environment" --query 'DBInstances[0].Endpoint.Address' --output text 2>$null
    Write-LogWarning "Database already exists: event-manager-db-$Environment"
    Write-LogSuccess "Using existing database: $dbEndpoint"
} catch {
    Write-LogInfo "Creating security group for RDS..."
    try {
        $sgId = aws ec2 describe-security-groups --group-names event-manager-rds-sg --query 'SecurityGroups[0].GroupId' --output text 2>$null
    } catch {
        $sgId = aws ec2 create-security-group --group-name event-manager-rds-sg --description "Security group for Event Manager RDS MySQL" --query 'GroupId' --output text
        
        Write-LogInfo "Adding MySQL access rule to security group..."
        aws ec2 authorize-security-group-ingress --group-id $sgId --protocol tcp --port 3306 --cidr 0.0.0.0/0
    }

    Write-LogInfo "Creating RDS MySQL instance..."
    aws rds create-db-instance --db-instance-identifier "event-manager-db-$Environment" --db-instance-class db.t3.micro --engine mysql --engine-version 8.0.43 --master-username $DBUsername --master-user-password EventManager123! --allocated-storage 20 --db-name EventManagerDB --vpc-security-group-ids $sgId --publicly-accessible --no-multi-az --storage-type gp2 --backup-retention-period 0 --tags Key=Name,Value="event-manager-db-$Environment" Key=Environment,Value=$Environment

    Write-LogSuccess "✅ RDS creation request sent successfully"

    Write-LogInfo "Waiting for database to be available (this may take 5-10 minutes)..."
    
    # Wait for RDS to be available
    $maxWaitTime = 1200 # 20 minutes
    $waitTime = 0
    do {
        Start-Sleep 30
        $waitTime += 30
        try {
            $dbStatus = aws rds describe-db-instances --db-instance-identifier "event-manager-db-$Environment" --query 'DBInstances[0].DBInstanceStatus' --output text
            Write-Progress -Activity "Waiting for RDS" -Status "Status: $dbStatus" -PercentComplete (($waitTime / $maxWaitTime) * 100)
        } catch {
            $dbStatus = "unknown"
        }
        
        if ($dbStatus -eq "failed" -or $waitTime -ge $maxWaitTime) {
            Write-LogError "❌ Error creating database or timeout reached. Status: $dbStatus"
            exit 1
        }
    } while ($dbStatus -ne "available")
    
    $dbEndpoint = aws rds describe-db-instances --db-instance-identifier "event-manager-db-$Environment" --query 'DBInstances[0].Endpoint.Address' --output text
    Write-LogSuccess "Database created successfully: $dbEndpoint"
}

Write-LogInfo "Creating secret in Secrets Manager for database credentials..."
$secretName = "event-app/db-credentials-$Environment-$accountId"

try {
    aws secretsmanager describe-secret --secret-id $secretName >$null 2>&1
    Write-LogWarning "Secret already exists, updating credentials..."
    aws secretsmanager update-secret --secret-id $secretName --secret-string "{`"username`":`"$DBUsername`",`"password`":`"EventManager123!`"}"
} catch {
    Write-LogInfo "Creating new secret with database credentials..."
    aws secretsmanager create-secret --name $secretName --description "Credentials for Event Manager database" --secret-string "{`"username`":`"$DBUsername`",`"password`":`"EventManager123!`"}" --tags Key=Environment,Value=$Environment Key=Name,Value=event-manager-db-secret
}

$secretArn = aws secretsmanager describe-secret --secret-id $secretName --query 'ARN' --output text
Write-LogSuccess "Secret created/updated successfully: $secretArn"

# STEP 8.5: Deploy InitDB stack
Show-Progress "8.5" 11 "Creating InitDB Lambda Function"

Write-LogInfo "Deploying InitDB stack to create tables..."
aws cloudformation deploy --template-file infra/templates/initdb.yml --stack-name event-manager-initdb --capabilities CAPABILITY_NAMED_IAM --parameter-overrides RDSSecretArn=$secretArn RDSClusterEndpoint=$dbEndpoint LambdaCodeBucket=$lambdaBucket LambdaCodeKey=lambda-functions.zip Environment=$Environment

Write-LogSuccess "InitDB stack deployed correctly"

# STEP 8.6: Execute InitDB Lambda
Show-Progress "8.6" 11 "Initializing Database"

$initLambdaName = aws cloudformation describe-stacks --stack-name event-manager-initdb --query 'Stacks[0].Outputs[?OutputKey==`InitDBLambdaName`].OutputValue' --output text

Write-LogInfo "Executing InitDB function to create tables..."
Write-LogInfo "Function name: $initLambdaName"

try {
    $initResponse = aws lambda invoke --function-name $initLambdaName --log-type Tail --payload '{}' "$env:TEMP\init-db-response.json"
    
    if (Test-Path "$env:TEMP\init-db-response.json") {
        $initResult = Get-Content "$env:TEMP\init-db-response.json" | ConvertFrom-Json
        if ($initResult.statusCode -eq 200) {
            Write-LogSuccess "✅ Database initialized correctly - tables created"
        } else {
            Write-LogError "❌ Error initializing database:"
            $initResult | ConvertTo-Json | Write-Host
            exit 1
        }
    } else {
        Write-LogError "Could not get response from InitDB function"
        exit 1
    }
} catch {
    Write-LogError "Error executing InitDB function"
    exit 1
}

# STEP 9: Deploy main stack
Show-Progress 9 11 "Deploying Main Infrastructure"

Write-LogWarning "This step may take 15-20 minutes. Please be patient..."
Write-LogInfo "Deploying main stack with all services..."
Write-LogInfo "Using database endpoint: $dbEndpoint"

aws cloudformation deploy --template-file infra/master-template.yml --stack-name event-manager --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND --parameter-overrides Environment=$Environment DBUsername=$DBUsername S3LambdaBucket=$lambdaBucketName LambdaCodeKey=lambda-functions.zip CreateS3Buckets=false ExistingLambdaCodeBucket=$lambdaBucketName ExistingReportsBucket=$reportsBucketName CreateSESResources=false ExistingSESConfigurationSet="event-manager-config-set-$Environment" DBEndpoint=$dbEndpoint RDSSecretArn=$secretArn

# STEP 10: Verify deployment
Show-Progress 10 11 "Verifying Deployment"

Write-LogInfo "Verifying main stack status..."
aws cloudformation describe-stacks --stack-name event-manager --query 'Stacks[0].StackStatus' --output text

Write-LogInfo "Getting stack outputs..."
Show-Header "STACK OUTPUTS"
aws cloudformation describe-stacks --stack-name event-manager --query 'Stacks[0].Outputs' --output table

Write-LogInfo "Listing all created stacks..."
Show-Header "CREATED STACKS"
aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE --query 'StackSummaries[?contains(StackName, `event-manager`)].{Name:StackName,Status:StackStatus,Created:CreationTime}' --output table

# STEP 11: Verify Lambda functions
Show-Progress 11 11 "Verifying Lambda Functions"

Write-LogInfo "Listing created Lambda functions..."
Show-Header "CREATED LAMBDA FUNCTIONS"
aws lambda list-functions --query 'Functions[?contains(FunctionName, `event-manager`)].{Name:FunctionName,Runtime:Runtime,LastModified:LastModified}' --output table

# Clean temporary files
Write-LogInfo "Cleaning temporary files..."
if (Test-Path "lambda-functions.zip") { Remove-Item "lambda-functions.zip" -Force }
if (Test-Path "$env:TEMP\init-db-response.json") { Remove-Item "$env:TEMP\init-db-response.json" -Force }

# FINAL SUMMARY
Show-Banner "DEPLOYMENT COMPLETED!" "" "Green"

Write-LogSuccess "The Event Manager AWS system has been deployed successfully"

Show-Header "IMPORTANT INFORMATION"

# Get important information
$apiUrl = Get-StackOutput "event-manager" "ApiGatewayUrl"
$userPoolId = Get-StackOutput "event-manager" "CognitoUserPoolId"

if ([string]::IsNullOrEmpty($apiUrl)) { $apiUrl = "Not available" }
if ([string]::IsNullOrEmpty($userPoolId)) { $userPoolId = "Not available" }

# Get Cognito Client ID
Write-LogInfo "Getting Cognito Client ID..."
try {
    $clientId = aws cognito-idp list-user-pool-clients --user-pool-id $userPoolId --query 'UserPoolClients[0].ClientId' --output text 2>$null
    if ([string]::IsNullOrEmpty($clientId)) { $clientId = "Not available" }
} catch {
    $clientId = "Not available"
}

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║                    🚀 DEPLOYMENT INFORMATION                    ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-LogSuccess "🌐 API Gateway URL: $apiUrl"
Write-LogSuccess "🔑 Cognito User Pool ID: $userPoolId"  
Write-LogSuccess "🔑 Cognito Client ID: $clientId"
Write-LogSuccess "🗄️ Database Endpoint: $dbEndpoint"
Write-Host ""

Write-LogSuccess "Deployment completed successfully at $(Get-Date)!"
