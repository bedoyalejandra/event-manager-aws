@echo off
REM ========================================================================
REM Script de Limpieza - Event Manager AWS (Windows)
REM Este script elimina todos los recursos creados por el despliegue
REM ========================================================================

setlocal enabledelayedexpansion

REM Configuración
set ENVIRONMENT=dev
set SCRIPT_DIR=%~dp0

echo.
echo ========================================================================
echo                         ADVERTENCIA
echo ========================================================================
echo Este script eliminara TODOS los recursos del Event Manager
echo incluyendo bases de datos, buckets S3 y todos los datos.
echo.
echo ESTA ACCION NO SE PUEDE DESHACER!
echo ========================================================================
echo.

REM Verificar credenciales AWS
echo [INFO] Verificando credenciales AWS...
aws sts get-caller-identity >nul 2>&1
if errorlevel 1 (
    echo [ERROR] No se pudieron obtener las credenciales AWS.
    echo [ERROR] Por favor, configura 'aws configure' primero.
    exit /b 1
)

for /f "tokens=*" %%a in ('aws sts get-caller-identity --query Account --output text') do set AWS_ACCOUNT_ID=%%a
for /f "tokens=*" %%a in ('aws configure get region') do set AWS_REGION=%%a

echo [SUCCESS] Credenciales AWS validas
echo   - Account ID: %AWS_ACCOUNT_ID%
echo   - Region: %AWS_REGION%

REM Modo reparación para stacks DELETE_FAILED
if "%1"=="--fix-failed-stacks" (
    echo.
    echo === MODO REPARACION: STACKS DELETE_FAILED ===
    echo [INFO] Buscando y reparando stacks en estado DELETE_FAILED...
    
    aws cloudformation list-stacks --stack-status-filter DELETE_FAILED --query "StackSummaries[?contains(StackName, 'event-manager')].StackName" --output text > temp_failed_stacks.txt
    
    set /p FAILED_STACKS=<temp_failed_stacks.txt
    if "!FAILED_STACKS!"=="" (
        echo [SUCCESS] No se encontraron stacks en estado DELETE_FAILED
        del temp_failed_stacks.txt
        exit /b 0
    )
    
    echo.
    echo === STACKS EN DELETE_FAILED ===
    aws cloudformation list-stacks --stack-status-filter DELETE_FAILED --query "StackSummaries[?contains(StackName, 'event-manager')].{Name:StackName,Status:StackStatus}" --output table
    
    echo.
    set /p FIX_CONFIRM="Quieres intentar reparar estos stacks? (yes/no): "
    if not "!FIX_CONFIRM!"=="yes" (
        echo [INFO] Reparacion cancelada por el usuario
        del temp_failed_stacks.txt
        exit /b 0
    )
    
    for %%s in (!FAILED_STACKS!) do (
        echo [INFO] Reparando stack: %%s
        call :force_delete_failed_stack %%s
    )
    
    echo [SUCCESS] Proceso de reparacion completado
    del temp_failed_stacks.txt
    exit /b 0
)

REM Listar stacks existentes
echo.
echo [INFO] Buscando stacks relacionados con event-manager...
aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE CREATE_FAILED UPDATE_FAILED ROLLBACK_COMPLETE DELETE_FAILED --query "StackSummaries[?contains(StackName, 'event-manager')].{Name:StackName,Status:StackStatus}" --output table > temp_stacks.txt

set STACKS_FOUND=0
for /f "skip=3 tokens=*" %%a in (temp_stacks.txt) do (
    set line=%%a
    if not "!line!"=="" (
        if not "!line:~0,1!"=="-" (
            set STACKS_FOUND=1
        )
    )
)

if !STACKS_FOUND!==0 (
    echo [WARNING] No se encontraron stacks de event-manager para eliminar.
    del temp_stacks.txt
    exit /b 0
)

echo.
echo === STACKS ENCONTRADOS ===
type temp_stacks.txt
del temp_stacks.txt

REM Confirmación del usuario
echo.
echo ========================================================================
echo Estas ABSOLUTAMENTE SEGURO de que quieres eliminar todos estos recursos?
echo ========================================================================
set /p CONFIRMATION="Escribe 'DELETE' (en mayusculas) para confirmar: "

if not "%CONFIRMATION%"=="DELETE" (
    echo [INFO] Operacion cancelada por el usuario.
    exit /b 0
)

echo.
echo Segunda confirmacion requerida.
set /p FINAL_CONFIRM="Confirmas que quieres ELIMINAR PERMANENTEMENTE todos los datos? (yes/no): "

if not "%FINAL_CONFIRM%"=="yes" (
    echo [INFO] Operacion cancelada por el usuario.
    exit /b 0
)

echo.
echo [WARNING] Iniciando proceso de eliminacion...

REM Paso 1: Eliminar stack principal (event-manager)
echo.
echo [INFO] Eliminando stack principal: event-manager
aws cloudformation describe-stacks --stack-name event-manager >nul 2>&1
if not errorlevel 1 (
    echo [WARNING] Eliminando stack event-manager (esto puede tomar 10-15 minutos)...
    aws cloudformation delete-stack --stack-name event-manager
    call :wait_for_stack_deletion event-manager
) else (
    echo [INFO] Stack event-manager no existe o ya fue eliminado
)

REM Paso 1.5: Eliminar stack de InitDB
echo.
echo [INFO] Eliminando stack InitDB: event-manager-initdb
aws cloudformation describe-stacks --stack-name event-manager-initdb >nul 2>&1
if not errorlevel 1 (
    echo [WARNING] Eliminando stack event-manager-initdb...
    aws cloudformation delete-stack --stack-name event-manager-initdb
    call :wait_for_stack_deletion event-manager-initdb
) else (
    echo [INFO] Stack event-manager-initdb no existe o ya fue eliminado
)

REM Paso 1.6: Eliminar base de datos RDS y recursos relacionados
echo.
echo [INFO] Eliminando recursos de base de datos RDS...

set RDS_INSTANCE_ID=event-manager-db-%ENVIRONMENT%
aws rds describe-db-instances --db-instance-identifier %RDS_INSTANCE_ID% >nul 2>&1
if not errorlevel 1 (
    echo [WARNING] Eliminando instancia RDS: %RDS_INSTANCE_ID%
    echo [INFO] Esto puede tomar 10-15 minutos...
    aws rds delete-db-instance --db-instance-identifier %RDS_INSTANCE_ID% --skip-final-snapshot --delete-automated-backups
    echo [INFO] Esperando a que se elimine la instancia RDS...
    aws rds wait db-instance-deleted --db-instance-identifier %RDS_INSTANCE_ID%
    echo [SUCCESS] Instancia RDS eliminada: %RDS_INSTANCE_ID%
) else (
    echo [INFO] Instancia RDS %RDS_INSTANCE_ID% no existe o ya fue eliminada
)

REM Eliminar Security Group de RDS
set SG_NAME=event-manager-rds-sg
for /f "tokens=*" %%a in ('aws ec2 describe-security-groups --group-names %SG_NAME% --query "SecurityGroups[0].GroupId" --output text 2^>nul') do set SG_ID=%%a
if not "%SG_ID%"=="" (
    if not "%SG_ID%"=="None" (
        echo [WARNING] Eliminando Security Group RDS: %SG_NAME% (%SG_ID%)
        aws ec2 delete-security-group --group-id %SG_ID%
        echo [SUCCESS] Security Group RDS eliminado: %SG_NAME%
    )
) else (
    echo [INFO] Security Group %SG_NAME% no existe o ya fue eliminado
)

REM Eliminar Secret de base de datos
set SECRET_NAME=event-app/db-credentials-%ENVIRONMENT%-%AWS_ACCOUNT_ID%
aws secretsmanager describe-secret --secret-id %SECRET_NAME% >nul 2>&1
if not errorlevel 1 (
    echo [WARNING] Eliminando secret de base de datos: %SECRET_NAME%
    aws secretsmanager delete-secret --secret-id %SECRET_NAME% --force-delete-without-recovery
    echo [SUCCESS] Secret de base de datos eliminado: %SECRET_NAME%
) else (
    echo [INFO] Secret %SECRET_NAME% no existe o ya fue eliminado
)

REM Paso 2: Vaciar buckets S3
echo.
echo [INFO] Verificando buckets S3 para vaciar...
aws cloudformation describe-stacks --stack-name event-manager-s3 >nul 2>&1
if not errorlevel 1 (
    for /f "tokens=*" %%a in ('aws cloudformation describe-stacks --stack-name event-manager-s3 --query "Stacks[0].Outputs[?OutputKey=='LambdaCodeBucketName'].OutputValue" --output text 2^>nul') do set LAMBDA_BUCKET=%%a
    for /f "tokens=*" %%a in ('aws cloudformation describe-stacks --stack-name event-manager-s3 --query "Stacks[0].Outputs[?OutputKey=='ReportsBucketName'].OutputValue" --output text 2^>nul') do set REPORTS_BUCKET=%%a
    
    if not "!LAMBDA_BUCKET!"=="" (
        if not "!LAMBDA_BUCKET!"=="None" (
            echo [INFO] Vaciando bucket Lambda: !LAMBDA_BUCKET!
            aws s3 rm s3://!LAMBDA_BUCKET! --recursive
        )
    )
    
    if not "!REPORTS_BUCKET!"=="" (
        if not "!REPORTS_BUCKET!"=="None" (
            echo [INFO] Vaciando bucket de reportes: !REPORTS_BUCKET!
            aws s3 rm s3://!REPORTS_BUCKET! --recursive
        )
    )
)

REM Paso 3: Eliminar stack S3
echo.
echo [INFO] Eliminando stack S3: event-manager-s3
aws cloudformation describe-stacks --stack-name event-manager-s3 >nul 2>&1
if not errorlevel 1 (
    echo [WARNING] Eliminando stack event-manager-s3...
    aws cloudformation delete-stack --stack-name event-manager-s3
    call :wait_for_stack_deletion event-manager-s3
) else (
    echo [INFO] Stack event-manager-s3 no existe o ya fue eliminado
)

REM Paso 4: Verificar que todos los stacks fueron eliminados
echo.
echo [INFO] Verificando que todos los stacks fueron eliminados...
aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE CREATE_FAILED UPDATE_FAILED ROLLBACK_COMPLETE DELETE_FAILED --query "StackSummaries[?contains(StackName, 'event-manager')].StackName" --output text > temp_remaining.txt
set /p REMAINING_STACKS=<temp_remaining.txt
if not "!REMAINING_STACKS!"=="" (
    echo [WARNING] Algunos stacks aun existen: !REMAINING_STACKS!
    echo [INFO] Esto puede ser normal si estan en proceso de eliminacion.
) else (
    echo [SUCCESS] Todos los stacks de event-manager han sido eliminados
)
del temp_remaining.txt

REM Paso 5: Limpiar archivos locales temporales
echo.
echo [INFO] Limpiando archivos temporales locales...
if exist lambda-functions.zip del lambda-functions.zip
if exist response.json del response.json
if exist temp_*.txt del temp_*.txt

REM Paso 6: Verificar recursos huerfanos
echo.
echo [INFO] Verificando posibles recursos huerfanos...

REM Verificar funciones Lambda huerfanas
aws lambda list-functions --query "Functions[?contains(FunctionName, 'event-manager')].FunctionName" --output text > temp_orphan_lambdas.txt
set /p ORPHAN_LAMBDAS=<temp_orphan_lambdas.txt
if not "!ORPHAN_LAMBDAS!"=="" (
    if not "!ORPHAN_LAMBDAS!"=="None" (
        echo [WARNING] Se encontraron funciones Lambda huerfanas: !ORPHAN_LAMBDAS!
        echo [INFO] Puedes eliminarlas manualmente si es necesario.
    )
)
del temp_orphan_lambdas.txt

REM Verificar buckets S3 huerfanos
aws s3api list-buckets --query "Buckets[?contains(Name, 'event-manager')].Name" --output text > temp_orphan_buckets.txt
set /p ORPHAN_BUCKETS=<temp_orphan_buckets.txt
if not "!ORPHAN_BUCKETS!"=="" (
    if not "!ORPHAN_BUCKETS!"=="None" (
        echo [WARNING] Se encontraron buckets S3 huerfanos: !ORPHAN_BUCKETS!
        echo [INFO] Puedes eliminarlos manualmente si es necesario.
    )
)
del temp_orphan_buckets.txt

REM Verificar instancias RDS huerfanas
aws rds describe-db-instances --query "DBInstances[?contains(DBInstanceIdentifier, 'event-manager')].DBInstanceIdentifier" --output text > temp_orphan_rds.txt
set /p ORPHAN_RDS=<temp_orphan_rds.txt
if not "!ORPHAN_RDS!"=="" (
    if not "!ORPHAN_RDS!"=="None" (
        echo [WARNING] Se encontraron instancias RDS huerfanas: !ORPHAN_RDS!
        echo [INFO] Puedes eliminarlas manualmente si es necesario.
    )
)
del temp_orphan_rds.txt

REM Verificar secrets huerfanos
aws secretsmanager list-secrets --query "SecretList[?contains(Name, 'event-app/db-credentials')].Name" --output text > temp_orphan_secrets.txt
set /p ORPHAN_SECRETS=<temp_orphan_secrets.txt
if not "!ORPHAN_SECRETS!"=="" (
    if not "!ORPHAN_SECRETS!"=="None" (
        echo [WARNING] Se encontraron secrets huerfanos: !ORPHAN_SECRETS!
        echo [INFO] Puedes eliminarlos manualmente si es necesario.
    )
)
del temp_orphan_secrets.txt

REM RESUMEN FINAL
echo.
echo ========================================================================
echo                      LIMPIEZA COMPLETADA!
echo ========================================================================
echo.
echo [SUCCESS] Todos los recursos del Event Manager AWS han sido eliminados
echo [INFO] Fecha de eliminacion: %date% %time%
echo.
echo === RESUMEN DE ELIMINACION ===
echo [INFO] Stack event-manager eliminado
echo [INFO] Stack event-manager-initdb eliminado
echo [INFO] Base de datos RDS eliminada
echo [INFO] Security Group RDS eliminado
echo [INFO] Secrets Manager eliminado
echo [INFO] Stack event-manager-s3 eliminado
echo [INFO] Buckets S3 vaciados
echo [INFO] Archivos temporales eliminados
echo.
echo Para volver a desplegar el sistema, ejecuta:
echo deploy.bat
echo.
echo [SUCCESS] Limpieza completada exitosamente!

exit /b 0

REM ========================================================================
REM FUNCIONES
REM ========================================================================

:wait_for_stack_deletion
set STACK_NAME=%1
echo [INFO] Esperando a que se elimine el stack: %STACK_NAME%

:wait_loop
timeout /t 10 /nobreak >nul
aws cloudformation describe-stacks --stack-name %STACK_NAME% >nul 2>&1
if errorlevel 1 (
    echo [SUCCESS] Stack %STACK_NAME% eliminado correctamente
    goto :eof
)

for /f "tokens=*" %%a in ('aws cloudformation describe-stacks --stack-name %STACK_NAME% --query "Stacks[0].StackStatus" --output text 2^>nul') do set STACK_STATUS=%%a

if "%STACK_STATUS%"=="DELETE_FAILED" (
    echo [ERROR] Error al eliminar el stack %STACK_NAME%
    call :force_delete_failed_stack %STACK_NAME%
    goto :eof
)

echo [INFO] Estado actual del stack %STACK_NAME%: %STACK_STATUS%
goto wait_loop

:force_delete_failed_stack
set FAILED_STACK=%1
echo [WARNING] Intentando forzar eliminacion del stack: %FAILED_STACK%

REM Limpiar buckets S3 del stack
call :cleanup_s3_buckets %FAILED_STACK%

REM Reintentar eliminacion
echo [INFO] Reintentando eliminacion del stack: %FAILED_STACK%
aws cloudformation delete-stack --stack-name %FAILED_STACK%

timeout /t 10 /nobreak >nul

for /f "tokens=*" %%a in ('aws cloudformation describe-stacks --stack-name %FAILED_STACK% --query "Stacks[0].StackStatus" --output text 2^>nul') do set RETRY_STATUS=%%a

if "%RETRY_STATUS%"=="DELETE_FAILED" (
    echo [ERROR] Stack %FAILED_STACK% sigue en estado DELETE_FAILED
    echo [INFO] Mostrando recursos que fallaron al eliminar:
    aws cloudformation describe-stack-events --stack-name %FAILED_STACK% --query "StackEvents[?ResourceStatus=='DELETE_FAILED'].[LogicalResourceId,ResourceStatusReason]" --output table
    echo [WARNING] Puedes necesitar eliminar recursos manualmente o contactar soporte AWS
) else (
    echo [INFO] Stack %FAILED_STACK% ahora en estado: %RETRY_STATUS%
)
goto :eof

:cleanup_s3_buckets
set CLEANUP_STACK=%1
echo [INFO] Limpiando buckets S3 del stack: %CLEANUP_STACK%

aws cloudformation describe-stacks --stack-name %CLEANUP_STACK% >nul 2>&1
if not errorlevel 1 (
    for /f "tokens=*" %%b in ('aws cloudformation describe-stack-resources --stack-name %CLEANUP_STACK% --query "StackResources[?ResourceType=='AWS::S3::Bucket'].PhysicalResourceId" --output text 2^>nul') do (
        set BUCKET_NAME=%%b
        if not "!BUCKET_NAME!"=="" (
            if not "!BUCKET_NAME!"=="None" (
                aws s3api head-bucket --bucket !BUCKET_NAME! >nul 2>&1
                if not errorlevel 1 (
                    echo [INFO] Vaciando bucket: !BUCKET_NAME!
                    aws s3 rm s3://!BUCKET_NAME! --recursive
                    echo [SUCCESS] Bucket !BUCKET_NAME! vaciado
                )
            )
        )
    )
)
goto :eof
