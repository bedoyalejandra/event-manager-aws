@echo off
REM 🗄️ Windows Batch Script to Run InitDB - Event Manager AWS
REM This script executes the InitDB Lambda function to create/update the database model
REM
REM USAGE:
REM   scripts\run-init-db.bat [environment]
REM
REM PURPOSE:
REM   - Create database tables if they don't exist
REM   - Update table structure (ALTER TABLE with IF NOT EXISTS)
REM   - Create/update indexes for optimization
REM   - Verify database connectivity
REM
REM USE CASES:
REM   1. First time: Creates all tables and indexes
REM   2. Update: Executes schema changes without losing data
REM   3. Verification: Tests connectivity and database status

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
echo RUN INIT DB - Database Structure Update
echo ========================================
echo.
echo Configuration:
echo   - Environment: %ENVIRONMENT%
echo   - AWS Region: %AWS_REGION%
echo.
echo [WARNING] This script will execute changes to the database
echo.
echo This script will perform the following operations:
echo   * Create tables if they don't exist (CREATE TABLE IF NOT EXISTS)
echo   * Create indexes if they don't exist (CREATE INDEX IF NOT EXISTS)
echo   * Verify database connectivity
echo   * Will NOT delete existing data
echo.
set /p CONFIRM="Do you want to continue with the database update? (y/N): "
if /i not "%CONFIRM%"=="y" (
    echo.
    echo [INFO] Operation cancelled by user
    pause
    exit /b 0
)
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
    echo [ERROR] Please deploy the main stack first
    echo.
    echo [INFO] To deploy the complete stack (includes InitDB), run:
    echo   scripts\deploy.bat
    echo.
    echo [INFO] Note: InitDB is now deployed automatically as part of the main stack
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
REM Get Database Information
REM ============================================
echo.
echo [INFO] Getting database information...

for /f "tokens=*" %%i in ('aws cloudformation describe-stacks --stack-name event-manager --query "Stacks[0].Outputs[?OutputKey==`DBEndpoint`].OutputValue" --output text 2^>nul') do set DB_ENDPOINT=%%i
for /f "tokens=*" %%i in ('aws cloudformation describe-stacks --stack-name event-manager --query "Stacks[0].Outputs[?OutputKey==`DBSecretArn`].OutputValue" --output text 2^>nul') do set SECRET_ARN=%%i

if not "%DB_ENDPOINT%"=="" (
    echo [SUCCESS] Database Endpoint: %DB_ENDPOINT%
)
if not "%SECRET_ARN%"=="" (
    echo [SUCCESS] Secret ARN: %SECRET_ARN%
)

echo.
echo ===============================================================
echo   USEFUL COMMANDS TO VERIFY DATABASE
echo ===============================================================
echo.
echo 1. Get database credentials:
echo    aws secretsmanager get-secret-value --secret-id %SECRET_ARN% --query SecretString --output text
echo.
echo 2. Connect to MySQL (requires mysql client):
echo    mysql -h %DB_ENDPOINT% -u ^<USERNAME^> -p EventManagerDB
echo.
echo 3. Useful SQL commands:
echo    SHOW TABLES;                                    # List all tables
echo    DESCRIBE events;                                # View events table structure
echo    SHOW INDEX FROM events;                         # View events table indexes
echo    SELECT COUNT(*) FROM events;                    # Count events
echo    SELECT * FROM events ORDER BY created_at DESC LIMIT 5;  # View latest events
echo.
echo 4. Run this script again to update structure:
echo    scripts\run-init-db.bat %ENVIRONMENT%
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
    echo    * report           - Event reports
    echo    * events           - System events
    echo    * event_assistance - Event attendance
    echo.
    echo [INFO] Indexes created for optimization:
    echo    * idx_status       - Search by event status
    echo    * idx_start_date   - Sort by date
    echo    * idx_created_at   - Sort by creation
    echo    * idx_assistance_* - Attendance query optimization
    echo.
    echo [INFO] Database structure is ready to use
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
    echo [INFO] Possible causes:
    echo    * Incorrect database credentials
    echo    * Database not accessible from Lambda
    echo    * Security group blocking connection
    echo    * Connection timeout
    echo.
    echo [INFO] For debugging, check CloudWatch logs:
    echo    aws logs tail /aws/lambda/InitDBLambda-%ENVIRONMENT% --follow
    echo.
)

pause
