@echo off
REM 📦 Windows Batch Script to Upload Lambda Code - Event Manager AWS
REM This script packages and uploads only the Lambda functions code

setlocal enabledelayedexpansion

REM Configuration
set ENVIRONMENT=%1
if "%ENVIRONMENT%"=="" set ENVIRONMENT=dev

set AWS_REGION=%2
if "%AWS_REGION%"=="" (
    for /f "tokens=*" %%i in ('aws configure get region') do set AWS_REGION=%%i
)
if "%AWS_REGION%"=="" set AWS_REGION=us-west-2

echo ========================================
echo UPLOAD LAMBDA CODE - Event Manager AWS
echo ========================================
echo.
echo Configuration:
echo   - Environment: %ENVIRONMENT%
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
if not exist "src" (
    echo [ERROR] src directory not found
    echo [ERROR] Please run this script from the project root directory
    pause
    exit /b 1
)
if not exist "src\package.json" (
    echo [ERROR] package.json not found in src directory
    pause
    exit /b 1
)
echo [SUCCESS] Project structure verified

REM ============================================
REM STEP 1/4: Install Dependencies and Package
REM ============================================
echo.
echo === STEP 1/4: Installing Dependencies and Packaging Lambda ===
echo.

cd src

echo [INFO] Installing Node.js dependencies...
call npm install
if !errorlevel! neq 0 (
    echo [ERROR] Failed to install dependencies
    cd ..
    pause
    exit /b 1
)
echo [SUCCESS] Dependencies installed successfully

echo [INFO] Creating ZIP with Lambda functions...
if exist "lambda-functions.zip" del "lambda-functions.zip"

REM Use PowerShell to create ZIP with proper compression
powershell -command "try { $compress = @{ Path = Get-ChildItem -Exclude '*.zip', 'package-lock.json' -Recurse | ForEach-Object { $_.FullName }; DestinationPath = 'lambda-functions.zip'; CompressionLevel = 'Optimal' }; Compress-Archive @compress; Write-Host '[SUCCESS] ZIP created successfully' } catch { Write-Host '[ERROR] Failed to create ZIP:' $_.Exception.Message; exit 1 }"
if !errorlevel! neq 0 (
    echo [ERROR] Failed to create ZIP file
    cd ..
    pause
    exit /b 1
)

REM Verify ZIP was created and get size
for /f "tokens=*" %%i in ('powershell -command "if (Test-Path 'lambda-functions.zip') { $size = [math]::Round((Get-Item 'lambda-functions.zip').Length / 1MB, 2); Write-Output $size } else { exit 1 }"') do set ZIP_SIZE=%%i
if !errorlevel! neq 0 (
    echo [ERROR] ZIP file not found after creation
    cd ..
    pause
    exit /b 1
)
echo [SUCCESS] ZIP created. Size: %ZIP_SIZE% MB

REM Verify dependencies are included in ZIP
echo [INFO] Verifying dependencies are included...
powershell -command "try { Add-Type -AssemblyName System.IO.Compression.FileSystem; $zipFile = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path 'lambda-functions.zip')); $hasMySQL = $zipFile.Entries | Where-Object { $_.FullName -like '*node_modules/mysql2*' }; $zipFile.Dispose(); if ($hasMySQL) { Write-Host '[SUCCESS] mysql2 dependencies included in ZIP' } else { Write-Host '[ERROR] mysql2 dependencies NOT found in ZIP'; exit 1 } } catch { Write-Host '[ERROR] Could not verify ZIP contents:' $_.Exception.Message; exit 1 }"
if !errorlevel! neq 0 (
    echo [ERROR] ZIP verification failed
    cd ..
    pause
    exit /b 1
)

REM Move ZIP to project root
move lambda-functions.zip ..\
cd ..

echo [INFO] Cleaning temporary node_modules...
rmdir /s /q src\node_modules 2>nul
echo [SUCCESS] Cleanup completed

REM ============================================
REM STEP 2/4: Get S3 Bucket Information
REM ============================================
echo.
echo === STEP 2/4: Getting S3 Bucket Information ===
echo.

echo [INFO] Searching for S3 bucket from CloudFormation stack...
set LAMBDA_BUCKET=

REM Try to get bucket name from CloudFormation stack
for /f "tokens=*" %%i in ('aws cloudformation describe-stacks --stack-name event-manager-s3 --query "Stacks[0].Outputs[?OutputKey=='LambdaCodeBucketName'].OutputValue" --output text 2^>nul') do set LAMBDA_BUCKET=%%i

REM If stack not found, construct bucket name
if "%LAMBDA_BUCKET%"=="" (
    echo [WARNING] Could not get bucket from stack, constructing bucket name...
    set LAMBDA_BUCKET=event-manager-lambda-code-%ENVIRONMENT%-%ACCOUNT_ID%
    echo [INFO] Constructed bucket name: !LAMBDA_BUCKET!
) else (
    echo [SUCCESS] Bucket found from stack: %LAMBDA_BUCKET%
)

REM Verify bucket exists
echo [INFO] Verifying that bucket exists...
aws s3api head-bucket --bucket %LAMBDA_BUCKET% 2>nul
if !errorlevel! neq 0 (
    echo [ERROR] S3 bucket does not exist: %LAMBDA_BUCKET%
    echo [ERROR] Please run the full deployment script first or create the bucket manually
    pause
    exit /b 1
)
echo [SUCCESS] Bucket verified: %LAMBDA_BUCKET%

REM ============================================
REM STEP 3/4: Upload Lambda Code to S3
REM ============================================
echo.
echo === STEP 3/4: Uploading Lambda Code to S3 ===
echo.

echo [INFO] Uploading lambda-functions.zip to S3 bucket...
aws s3 cp lambda-functions.zip s3://%LAMBDA_BUCKET%/lambda-functions.zip
if !errorlevel! neq 0 (
    echo [ERROR] Failed to upload file to S3
    pause
    exit /b 1
)

echo [INFO] Verifying file was uploaded correctly...
aws s3 ls s3://%LAMBDA_BUCKET%/lambda-functions.zip
if !errorlevel! neq 0 (
    echo [ERROR] Could not verify file in S3
    pause
    exit /b 1
)
echo [SUCCESS] File verified in S3

REM Get object URL
set OBJECT_URL=s3://%LAMBDA_BUCKET%/lambda-functions.zip
echo [SUCCESS] Object URL: %OBJECT_URL%

REM Clean up local ZIP file
echo [INFO] Cleaning up local ZIP file...
del lambda-functions.zip
echo [SUCCESS] Cleanup completed

REM ============================================
REM STEP 4/4: Update All Lambda Functions
REM ============================================
echo.
echo === STEP 4/4: Updating Lambda Functions ===
echo.

REM Define all Lambda functions
set LAMBDA_FUNCTIONS=CreateEventLambda DeleteEventLambda UpdateEventLambda DisableEventLambda GetActiveEventsLambda GenerateReportLambda GetReportLambda ProcessReportDataLambda SendEmailLambda SendEventReminderLambda PostEventAssistanceLambda InitDBLambda

set UPDATED_COUNT=0
set FAILED_COUNT=0
set SKIPPED_COUNT=0

echo [INFO] Updating Lambda functions...
echo.

for %%F in (%LAMBDA_FUNCTIONS%) do (
    set FUNCTION_NAME=%%F-%ENVIRONMENT%
    
    REM Check if function exists
    aws lambda get-function --function-name !FUNCTION_NAME! >nul 2>&1
    if !errorlevel! equ 0 (
        echo [INFO] Updating function: !FUNCTION_NAME!
        
        aws lambda update-function-code --function-name !FUNCTION_NAME! --s3-bucket %LAMBDA_BUCKET% --s3-key lambda-functions.zip --output json >nul 2>&1
        if !errorlevel! equ 0 (
            echo [SUCCESS]   ✅ !FUNCTION_NAME! updated
            set /a UPDATED_COUNT+=1
        ) else (
            echo [ERROR]   ❌ Error updating !FUNCTION_NAME!
            set /a FAILED_COUNT+=1
        )
    ) else (
        echo [WARNING]   ⏭️  !FUNCTION_NAME! does not exist (skipped^)
        set /a SKIPPED_COUNT+=1
    )
)

echo.
echo [INFO] Update Summary:
echo [SUCCESS]   ✅ Updated: %UPDATED_COUNT%
if %FAILED_COUNT% gtr 0 (
    echo [ERROR]   ❌ Failed: %FAILED_COUNT%
)
if %SKIPPED_COUNT% gtr 0 (
    echo [WARNING]   ⏭️  Skipped: %SKIPPED_COUNT%
)

REM ============================================
REM UPLOAD COMPLETED
REM ============================================
echo.
echo ========================================
echo UPLOAD COMPLETED - SUCCESS
echo ========================================
echo.
echo [SUCCESS] Lambda code uploaded and functions updated
echo.
echo Details:
echo   - Bucket: %LAMBDA_BUCKET%
echo   - File: lambda-functions.zip
echo   - Size: %ZIP_SIZE% MB
echo   - URL: %OBJECT_URL%
echo   - Functions updated: %UPDATED_COUNT%
echo.
if %FAILED_COUNT% gtr 0 (
    echo [WARNING] Some functions could not be updated. Check logs above.
    echo [INFO] You can update manually with:
    echo   aws lambda update-function-code --function-name ^<FUNCTION_NAME^> --s3-bucket %LAMBDA_BUCKET% --s3-key lambda-functions.zip
    echo.
)
pause
