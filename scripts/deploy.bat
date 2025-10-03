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
if exist "lambda-functions.zip" del "lambda-functions.zip"

REM Use PowerShell with improved error handling for ZIP creation
powershell -command "try { $compress = @{ Path = Get-ChildItem -Exclude '*.zip', 'package-lock.json' -Recurse | ForEach-Object { $_.FullName }; DestinationPath = 'lambda-functions.zip'; CompressionLevel = 'Optimal' }; Compress-Archive @compress; Write-Host '[SUCCESS] ZIP created successfully' } catch { Write-Host '[ERROR] Failed to create ZIP:' $_.Exception.Message; exit 1 }"
if !errorlevel! neq 0 (
    echo [ERROR] Failed to create ZIP file
    pause
    exit /b 1
)

REM Verify ZIP was created and get size
powershell -command "if (Test-Path 'lambda-functions.zip') { $size = [math]::Round((Get-Item 'lambda-functions.zip').Length / 1MB, 2); Write-Host '[INFO] ZIP created successfully. Size:' $size 'MB' } else { Write-Host '[ERROR] ZIP file not found'; exit 1 }"

REM Verify dependencies are included in ZIP
echo [INFO] Verifying dependencies are included...
powershell -command "try { $zipFile = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path 'lambda-functions.zip')); $hasMySQL = $zipFile.Entries | Where-Object { $_.FullName -like '*node_modules/mysql2*' }; $zipFile.Dispose(); if ($hasMySQL) { Write-Host '[SUCCESS] mysql2 dependencies included in ZIP' } else { Write-Host '[ERROR] mysql2 dependencies NOT found in ZIP'; exit 1 } } catch { Write-Host '[ERROR] Could not verify ZIP contents:' $_.Exception.Message; exit 1 }"
if !errorlevel! neq 0 (
    echo [ERROR] ZIP verification failed
    pause
    exit /b 1
)

move lambda-functions.zip ..\
cd ..
rmdir /s /q src\node_modules
echo [SUCCESS] Lambda code packaged

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

REM Create RDS (simplified - assumes it doesn't exist)
echo.
echo === STEP 5/8: Creating Database ===
echo.
echo [WARNING] This step may take 10-15 minutes. Please be patient...

REM Check if RDS instance exists
aws rds describe-db-instances --db-instance-identifier event-manager-db-%ENVIRONMENT% >nul 2>&1
if !errorlevel! equ 0 (
    echo [WARNING] Database already exists
    for /f "tokens=*" %%i in ('aws rds describe-db-instances --db-instance-identifier event-manager-db-%ENVIRONMENT% --query "DBInstances[0].Endpoint.Address" --output text') do set DB_ENDPOINT=%%i
) else (
    echo [INFO] Creating RDS instance...
    
    REM Create security group
    aws ec2 describe-security-groups --group-names event-manager-rds-sg >nul 2>&1
    if !errorlevel! neq 0 (
        for /f "tokens=*" %%i in ('aws ec2 create-security-group --group-name event-manager-rds-sg --description "Security group for Event Manager RDS MySQL" --query GroupId --output text') do set SG_ID=%%i
        aws ec2 authorize-security-group-ingress --group-id !SG_ID! --protocol tcp --port 3306 --cidr 0.0.0.0/0
    ) else (
        for /f "tokens=*" %%i in ('aws ec2 describe-security-groups --group-names event-manager-rds-sg --query "SecurityGroups[0].GroupId" --output text') do set SG_ID=%%i
    )
    
    REM Create RDS instance
    aws rds create-db-instance --db-instance-identifier event-manager-db-%ENVIRONMENT% --db-instance-class db.t3.micro --engine mysql --engine-version 8.0.43 --master-username %DB_USERNAME% --master-user-password EventManager123! --allocated-storage 20 --db-name EventManagerDB --vpc-security-group-ids !SG_ID! --publicly-accessible --no-multi-az --storage-type gp2 --backup-retention-period 0
    
    echo [INFO] Waiting for database to be available...
    aws rds wait db-instance-available --db-instance-identifier event-manager-db-%ENVIRONMENT%
    
    for /f "tokens=*" %%i in ('aws rds describe-db-instances --db-instance-identifier event-manager-db-%ENVIRONMENT% --query "DBInstances[0].Endpoint.Address" --output text') do set DB_ENDPOINT=%%i
)

echo [SUCCESS] Database ready: %DB_ENDPOINT%

REM Create secret
echo [INFO] Creating Secrets Manager secret...
set SECRET_NAME=event-app/db-credentials-%ENVIRONMENT%-%ACCOUNT_ID%
aws secretsmanager create-secret --name %SECRET_NAME% --description "Credentials for Event Manager database" --secret-string "{\"username\":\"%DB_USERNAME%\",\"password\":\"EventManager123!\"}" >nul 2>&1
for /f "tokens=*" %%i in ('aws secretsmanager describe-secret --secret-id %SECRET_NAME% --query ARN --output text') do set SECRET_ARN=%%i
echo [SUCCESS] Secret created: %SECRET_ARN%

REM Validate RDS values before continuing
if "%DB_ENDPOINT%"=="" (
    echo [ERROR] DB_ENDPOINT is empty
    pause
    exit /b 1
)
if "%SECRET_ARN%"=="" (
    echo [ERROR] SECRET_ARN is empty
    pause
    exit /b 1
)

echo [SUCCESS] RDS values validated:
echo [INFO]   DB Endpoint: %DB_ENDPOINT%
echo [INFO]   Secret ARN: %SECRET_ARN%

REM Deploy InitDB
echo.
echo === STEP 6/8: Initializing Database ===
echo.
aws cloudformation deploy --template-file infra/templates/initdb.yml --stack-name event-manager-initdb --capabilities CAPABILITY_NAMED_IAM --parameter-overrides RDSSecretArn=%SECRET_ARN% RDSClusterEndpoint=%DB_ENDPOINT% LambdaCodeBucket=%LAMBDA_BUCKET_NAME% LambdaCodeKey=lambda-functions.zip Environment=%ENVIRONMENT%

for /f "tokens=*" %%i in ('aws cloudformation describe-stacks --stack-name event-manager-initdb --query "Stacks[0].Outputs[?OutputKey==`InitDBLambdaName`].OutputValue" --output text') do set INIT_LAMBDA_NAME=%%i
aws lambda invoke --function-name %INIT_LAMBDA_NAME% --payload "{}" %TEMP%\init-response.json >nul
echo [SUCCESS] Database initialized

REM Deploy main stack
echo.
echo === STEP 7/8: Deploying Main Infrastructure ===
echo.
echo [WARNING] This step may take 15-20 minutes. Please be patient...
aws cloudformation deploy --template-file infra/master-template.yml --stack-name event-manager --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND --parameter-overrides Environment=%ENVIRONMENT% DBUsername=%DB_USERNAME% S3LambdaBucket=%LAMBDA_BUCKET_NAME% LambdaCodeKey=lambda-functions.zip DBEndpoint=%DB_ENDPOINT% RDSSecretArn=%SECRET_ARN%
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

echo.
echo ================================================================
echo                     DEPLOYMENT COMPLETED!
echo ================================================================
echo.
echo IMPORTANT INFORMATION:
echo   API Gateway URL: %API_URL%
echo   Cognito User Pool ID: %USER_POOL_ID%
echo   Database Endpoint: %DB_ENDPOINT%
echo.
echo Deployment completed successfully at %DATE% %TIME%
echo.

REM Clean up
del lambda-functions.zip >nul 2>&1
del %TEMP%\init-response.json >nul 2>&1

pause
