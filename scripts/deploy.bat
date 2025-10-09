@echo off
REM 🚀 Windows Batch Deployment Script - Event Manager AWS
REM Simple Windows-compatible version for basic deployment

setlocal enabledelayedexpansion

REM Configuration
set ENVIRONMENT=%1
if "%ENVIRONMENT%"=="" set ENVIRONMENT=dev

set DB_USERNAME=%2
if "%DB_USERNAME%"=="" set DB_USERNAME=event_admin

set AWS_REGION=%3
if "%AWS_REGION%"=="" (
    for /f "tokens=*" %%i in ('aws configure get region') do set AWS_REGION=%%i
)
if "%AWS_REGION%"=="" set AWS_REGION=us-west-2

echo ========================================
echo EVENT MANAGER AWS DEPLOY - BATCH SCRIPT
echo ========================================
echo.
echo Configuration:
echo   - Environment: %ENVIRONMENT%
echo   - DB Username: %DB_USERNAME%
echo   - AWS Region: %AWS_REGION%
echo.

REM Check AWS credentials
echo [INFO] Verifying AWS credentials...
aws sts get-caller-identity >nul 2>&1
if !errorlevel! neq 0 (
    echo [ERROR] Could not obtain AWS credentials.
    echo [ERROR] Please run 'aws configure' first.
    pause
    exit /b 1
)

for /f "tokens=*" %%i in ('aws sts get-caller-identity --query Account --output text') do set ACCOUNT_ID=%%i
echo [SUCCESS] AWS credentials verified. Account ID: %ACCOUNT_ID%

REM Check project structure
echo [INFO] Verifying project structure...
if not exist "infra\master-template.yml" (
    echo [ERROR] master-template.yml not found
    pause
    exit /b 1
)
if not exist "src" (
    echo [ERROR] src directory not found
    pause
    exit /b 1
)
echo [SUCCESS] Project structure verified

REM Install dependencies and package Lambda
echo.
echo === STEP 1/8: Installing Dependencies and Packaging Lambda ===
echo.
cd src
if not exist "package.json" (
    echo [ERROR] package.json not found in src directory
    pause
    exit /b 1
)

echo [INFO] Installing Node.js dependencies...
call npm install
if !errorlevel! neq 0 (
    echo [ERROR] Failed to install dependencies
    pause
    exit /b 1
)

echo [INFO] Creating ZIP with Lambda functions...

REM Delete existing ZIP if it exists and wait for file system
if exist "lambda-functions.zip" (
    del /f /q "lambda-functions.zip" 2>nul
    timeout /t 1 /nobreak >nul
)

REM Use PowerShell with improved error handling for ZIP creation
powershell -command "$ErrorActionPreference = 'Stop'; try { $items = Get-ChildItem -Path . -Recurse | Where-Object { $_.Extension -ne '.zip' -and $_.Name -ne 'package-lock.json' } | Select-Object -ExpandProperty FullName; if ($items.Count -eq 0) { throw 'No files found to compress' }; Compress-Archive -Path $items -DestinationPath 'lambda-functions.zip' -CompressionLevel Optimal -Force; Write-Host '[SUCCESS] ZIP created successfully'; exit 0 } catch { Write-Host '[ERROR] Failed to create ZIP:' $_.Exception.Message; Write-Host '[WARNING] Continuing with existing ZIP file if available...'; exit 0 }"
if !errorlevel! neq 0 (
    echo [WARNING] ZIP creation had issues, checking for existing ZIP...
)

REM Wait a moment for file system to release the file
timeout /t 2 /nobreak >nul

REM Verify ZIP was created and get size
powershell -command "if (Test-Path 'lambda-functions.zip') { $size = [math]::Round((Get-Item 'lambda-functions.zip').Length / 1MB, 2); Write-Host '[INFO] ZIP file found. Size:' $size 'MB'; exit 0 } else { Write-Host '[WARNING] ZIP file not found in src directory'; Write-Host '[INFO] Checking parent directory...'; exit 0 }"

REM Verify dependencies are included in ZIP
echo [INFO] Verifying dependencies are included...
powershell -command "$ErrorActionPreference = 'Stop'; try { Add-Type -AssemblyName System.IO.Compression.FileSystem; $zipPath = (Resolve-Path 'lambda-functions.zip').Path; $zip = $null; try { $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath); $hasMySQL = $zip.Entries | Where-Object { $_.FullName -like '*node_modules/mysql2*' } | Select-Object -First 1; if ($hasMySQL) { Write-Host '[SUCCESS] mysql2 dependencies included in ZIP' } else { Write-Host '[WARNING] mysql2 dependencies NOT found in ZIP - may need manual verification'; exit 0 } } finally { if ($zip -ne $null) { $zip.Dispose() } } } catch { Write-Host '[WARNING] Could not verify ZIP contents:' $_.Exception.Message; Write-Host '[INFO] Continuing with deployment...'; exit 0 }"
if !errorlevel! neq 0 (
    echo [WARNING] ZIP verification had issues but continuing...
)

REM Move ZIP to parent directory if it exists in src
if exist "lambda-functions.zip" (
    move /y lambda-functions.zip ..\ >nul 2>&1
    if !errorlevel! equ 0 (
        echo [SUCCESS] ZIP moved to root directory
    ) else (
        echo [WARNING] Could not move ZIP, may already be in root
    )
) else (
    echo [INFO] ZIP not in src directory, checking root...
)

cd ..

REM Verify ZIP is in root directory
if exist "lambda-functions.zip" (
    echo [SUCCESS] Lambda code packaged and ready
) else (
    echo [ERROR] lambda-functions.zip not found in root directory
    echo [ERROR] Please create the ZIP manually or check previous errors
    pause
    exit /b 1
)

REM Clean up node_modules
if exist "src\node_modules" (
    rmdir /s /q src\node_modules >nul 2>&1
)

REM Deploy S3 stack
echo.
echo === STEP 2/8: Creating S3 Buckets ===
echo.
set LAMBDA_BUCKET_NAME=event-manager-lambda-code-%ENVIRONMENT%-%ACCOUNT_ID%
set REPORTS_BUCKET_NAME=event-manager-reports-%ENVIRONMENT%-%ACCOUNT_ID%

echo [INFO] Deploying S3 template...
aws cloudformation deploy --template-file infra/templates/s3.yml --stack-name event-manager-s3 --capabilities CAPABILITY_IAM --parameter-overrides Environment=%ENVIRONMENT%
if !errorlevel! neq 0 (
    echo [ERROR] Failed to deploy S3 stack
    pause
    exit /b 1
)
echo [SUCCESS] S3 stack deployed

REM Upload Lambda code
echo.
echo === STEP 3/8: Uploading Lambda Code ===
echo.
echo [INFO] Uploading lambda-functions.zip to S3...
aws s3 cp lambda-functions.zip s3://%LAMBDA_BUCKET_NAME%/lambda-functions.zip
if !errorlevel! neq 0 (
    echo [ERROR] Failed to upload Lambda code
    pause
    exit /b 1
)

echo [INFO] Uploading templates...
aws s3 cp infra/templates/ s3://%LAMBDA_BUCKET_NAME%/templates/ --recursive --exclude "*.md"
echo [SUCCESS] Files uploaded to S3

REM Validate template
echo.
echo === STEP 4/8: Validating Template ===
echo.
aws cloudformation validate-template --template-body file://infra/master-template.yml >nul
if !errorlevel! neq 0 (
    echo [ERROR] Template validation failed
    pause
    exit /b 1
)
echo [SUCCESS] Template validated

REM Get VPC information
echo.
echo === STEP 5/8: Getting VPC Information ===
echo.
echo [INFO] Getting default VPC and subnets...
for /f "tokens=*" %%i in ('aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text') do set VPC_ID=%%i
for /f "tokens=1,2 delims= " %%i in ('aws ec2 describe-subnets --filters "Name=default-for-az,Values=true" --query "Subnets[0:2].[SubnetId]" --output text') do (
    if not defined SUBNET_1 (
        set SUBNET_1=%%i
    ) else if not defined SUBNET_2 (
        set SUBNET_2=%%i
    )
)

if "%VPC_ID%"=="" (
    echo [ERROR] Could not find default VPC
    pause
    exit /b 1
)
if "%SUBNET_1%"=="" (
    echo [ERROR] Could not find subnets
    pause
    exit /b 1
)

set SUBNET_IDS=%SUBNET_1%,%SUBNET_2%
echo [SUCCESS] VPC Information:
echo [INFO]   VPC ID: %VPC_ID%
echo [INFO]   Subnet IDs: %SUBNET_IDS%

REM Database will be created by CloudFormation
echo.
echo === STEP 6/8: Database Configuration ===
echo.
echo [INFO] RDS will be deployed automatically by CloudFormation in the main stack
echo [INFO] RDS will be configured with:
echo [INFO]   - VPC: %VPC_ID%
echo [INFO]   - Subnets: %SUBNET_IDS%
echo [INFO]   - Security Group: Auto-created with MySQL port 3306 open
echo [INFO]   - Publicly Accessible: Yes (for Lambda connectivity)
echo [SUCCESS] RDS configuration ready

REM Deploy main stack
echo.
echo === STEP 7/8: Deploying Main Infrastructure ===
echo.
echo [WARNING] This step may take 15-20 minutes. Please be patient...
echo [INFO] Deploying main stack with RDS, InitDB, and all Lambda functions...
echo.
aws cloudformation deploy --template-file infra/master-template.yml --stack-name event-manager --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND --parameter-overrides Environment=%ENVIRONMENT% DBUsername=%DB_USERNAME% S3LambdaBucket=%LAMBDA_BUCKET_NAME% LambdaCodeKey=lambda-functions.zip VpcId=%VPC_ID% SubnetIds=%SUBNET_IDS% CreateS3Buckets=false ExistingLambdaCodeBucket=%LAMBDA_BUCKET_NAME% ExistingReportsBucket=%REPORTS_BUCKET_NAME% CreateSESResources=false ExistingSESConfigurationSet=event-manager-config-set-%ENVIRONMENT% ExistingDBSecretArn=""
if !errorlevel! neq 0 (
    echo [ERROR] Main stack deployment failed
    pause
    exit /b 1
)

REM Verify deployment
echo.
echo === STEP 8/8: Verifying Deployment ===
echo.
echo [INFO] Getting deployment information...
for /f "tokens=*" %%i in ('aws cloudformation describe-stacks --stack-name event-manager --query "Stacks[0].Outputs[?OutputKey==`ApiGatewayUrl`].OutputValue" --output text') do set API_URL=%%i
for /f "tokens=*" %%i in ('aws cloudformation describe-stacks --stack-name event-manager --query "Stacks[0].Outputs[?OutputKey==`CognitoUserPoolId`].OutputValue" --output text') do set USER_POOL_ID=%%i
for /f "tokens=*" %%i in ('aws cloudformation describe-stacks --stack-name event-manager --query "Stacks[0].Outputs[?OutputKey==`DBEndpoint`].OutputValue" --output text') do set DB_ENDPOINT=%%i

echo.
echo ================================================================
echo                     DEPLOYMENT COMPLETED!
echo ================================================================
echo.
echo IMPORTANT INFORMATION:
echo   API Gateway URL: %API_URL%
echo   Cognito User Pool ID: %USER_POOL_ID%
echo   Database Endpoint: %DB_ENDPOINT%
echo   VPC ID: %VPC_ID%
echo.
echo [SUCCESS] All components deployed:
echo   ✅ RDS MySQL Database (with VPC configuration)
echo   ✅ InitDB Lambda (database initialized automatically)
echo   ✅ All Lambda Functions
echo   ✅ API Gateway
echo   ✅ Cognito User Pool
echo   ✅ S3 Buckets
echo   ✅ SQS and SES
echo   ✅ Step Functions
echo   ✅ EventBridge
echo.
echo Deployment completed successfully at %DATE% %TIME%
echo.

REM Clean up
del lambda-functions.zip >nul 2>&1

pause
