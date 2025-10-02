@echo off
REM 🗄️ Windows Batch Script to Run InitDB - Event Manager AWS
REM This script executes the InitDB Lambda function to create/update the database model

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
echo RUN INIT DB - Event Manager AWS
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

REM ============================================
REM STEP 1/3: Get Lambda Function Information
REM ============================================
echo.
echo === STEP 1/3: Getting Lambda Function Information ===
echo.

set FUNCTION_NAME=InitDBLambda-%ENVIRONMENT%

echo [INFO] Verifying Lambda function exists...
aws lambda get-function --function-name %FUNCTION_NAME% >nul 2>&1
if !errorlevel! neq 0 (
    echo [ERROR] Lambda function does not exist: %FUNCTION_NAME%
    echo [ERROR] Please deploy the InitDB stack first
    echo.
    echo [INFO] To deploy InitDB, run:
    echo   aws cloudformation deploy --template-file infra/templates/initdb.yml --stack-name event-manager-initdb-%ENVIRONMENT% --capabilities CAPABILITY_NAMED_IAM --parameter-overrides Environment=%ENVIRONMENT%
    pause
    exit /b 1
)
echo [SUCCESS] Lambda function found: %FUNCTION_NAME%

echo [INFO] Getting function details...
for /f "tokens=*" %%i in ('aws lambda get-function --function-name %FUNCTION_NAME% --query "Configuration.Runtime" --output text') do set RUNTIME=%%i
for /f "tokens=*" %%i in ('aws lambda get-function --function-name %FUNCTION_NAME% --query "Configuration.MemorySize" --output text') do set MEMORY=%%i
for /f "tokens=*" %%i in ('aws lambda get-function --function-name %FUNCTION_NAME% --query "Configuration.Timeout" --output text') do set TIMEOUT=%%i

echo [INFO] Function details:
echo   Runtime: %RUNTIME%
echo   Memory: %MEMORY% MB
echo   Timeout: %TIMEOUT% seconds

REM ============================================
REM STEP 2/3: Execute InitDB Function
REM ============================================
echo.
echo === STEP 2/3: Executing InitDB Function ===
echo.

echo [INFO] Invoking Lambda function to initialize/update database...
echo.

REM Create temporary file for response
set RESPONSE_FILE=%TEMP%\initdb-response-%RANDOM%.json

echo [INFO] Executing: aws lambda invoke --function-name %FUNCTION_NAME%
aws lambda invoke --function-name %FUNCTION_NAME% --log-type Tail --query "LogResult" --output text %RESPONSE_FILE% > %TEMP%\logs.txt 2>&1

if !errorlevel! equ 0 (
    echo.
    echo [SUCCESS] Function executed successfully
    echo.
    echo [INFO] Lambda Logs:
    echo -------------------------------------
    type %TEMP%\logs.txt
    echo -------------------------------------
) else (
    echo.
    echo [ERROR] Error executing Lambda function
    if exist %RESPONSE_FILE% del %RESPONSE_FILE%
    if exist %TEMP%\logs.txt del %TEMP%\logs.txt
    pause
    exit /b 1
)

REM ============================================
REM STEP 3/3: Process Results
REM ============================================
echo.
echo === STEP 3/3: Processing Results ===
echo.

echo [INFO] Function Response:
echo -------------------------------------
type %RESPONSE_FILE%
echo.
echo -------------------------------------

REM Check status code
for /f "tokens=*" %%i in ('powershell -command "try { (Get-Content '%RESPONSE_FILE%' | ConvertFrom-Json).statusCode } catch { 'unknown' }"') do set STATUS_CODE=%%i

if "%STATUS_CODE%"=="200" (
    echo.
    echo [SUCCESS] ✅ Database initialized/updated successfully
    
    REM Extract details from response
    echo.
    echo [INFO] Operation details:
    powershell -command "try { $json = Get-Content '%RESPONSE_FILE%' | ConvertFrom-Json; $body = $json.body | ConvertFrom-Json; $body | ConvertTo-Json } catch { Write-Host 'Could not parse response body' }"
) else (
    echo.
    echo [ERROR] ❌ Error initializing database
    echo [ERROR] Status code: %STATUS_CODE%
    
    REM Show error message if available
    echo.
    echo [ERROR] Error message:
    powershell -command "try { $json = Get-Content '%RESPONSE_FILE%' | ConvertFrom-Json; $json.body } catch { Write-Host 'Could not parse error message' }"
)

REM Cleanup
if exist %RESPONSE_FILE% del %RESPONSE_FILE%
if exist %TEMP%\logs.txt del %TEMP%\logs.txt

REM ============================================
REM Verification Instructions
REM ============================================
echo.
echo [INFO] To verify the tables created, you can connect to the database:
echo.
echo   # Get credentials from Secrets Manager
echo   aws secretsmanager get-secret-value --secret-id event-manager-rds-secret-%ENVIRONMENT%
echo.
echo   # Connect to MySQL
echo   mysql -h ^<DB_ENDPOINT^> -u ^<USERNAME^> -p EventManagerDB
echo.
echo   # List tables
echo   SHOW TABLES;
echo.

REM ============================================
REM Final Summary
REM ============================================
if "%STATUS_CODE%"=="200" (
    echo.
    echo ========================================
    echo INIT DB COMPLETED - SUCCESS
    echo ========================================
    echo.
    echo [SUCCESS] Database model updated successfully
    echo.
    echo [INFO] Tables created/updated:
    echo   - users
    echo   - events
    echo   - event_assistance
    echo   - report
    echo.
    echo [INFO] Indexes created for query optimization
    echo.
) else (
    echo.
    echo ========================================
    echo INIT DB FAILED - ERROR
    echo ========================================
    echo.
    echo [ERROR] Could not update database model
    echo [INFO] Review the logs above for more details
    echo.
)

pause
