# 🚀 Guía de Despliegue Manual - Event Manager AWS

Esta guía te permitirá desplegar manualmente el sistema de gestión de eventos con arquitectura serverless en AWS.

## 📋 Prerrequisitos

Antes de comenzar, asegúrate de tener:

1. **AWS CLI** instalado y configurado
   ```bash
   aws --version
   aws configure list
   ```

2. **Credenciales AWS** con permisos administrativos
   - Access Key ID
   - Secret Access Key
   - Región configurada (ej: us-east-1)

3. **Node.js** instalado (para desarrollo local)
   ```bash
   node --version
   npm --version
   ```

4. **Permisos IAM** necesarios (ver sección de Políticas IAM)

## 🎯 Pasos del Despliegue Manual

### Paso 1: Preparar el Entorno

```bash
# 1. Clonar o navegar al directorio del proyecto
cd /ruta/a/tu/proyecto/event-manager-aws

# 2. Verificar estructura del proyecto
ls -la
# Deberías ver: infra/, src/, README.md, etc.

# 3. Configurar variables de entorno (opcional para referencia)
export AWS_DEFAULT_REGION=us-east-1
export ENVIRONMENT=dev
export DB_USERNAME=event_admin
```

### Paso 2: Empaquetar Funciones Lambda

```bash
# Crear archivo ZIP con todas las funciones Lambda
zip -r lambda-functions.zip src/

# Verificar que se creó correctamente
ls -lh lambda-functions.zip
```

### Paso 3: Crear Bucket S3 para Código Lambda

```bash
# Desplegar template S3 para crear buckets
aws cloudformation deploy \
    --template-file infra/templates/s3.yml \
    --stack-name event-manager-s3 \
    --capabilities CAPABILITY_IAM \
    --parameter-overrides Environment=dev

# Verificar que el stack se creó correctamente
aws cloudformation describe-stacks --stack-name event-manager-s3
```

### Paso 4: Obtener Nombre del Bucket Creado

```bash
# Obtener el nombre del bucket automáticamente generado
export LAMBDA_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name event-manager-s3 \
    --query 'Stacks[0].Outputs[?OutputKey==`LambdaCodeBucketName`].OutputValue' \
    --output text)

# Verificar que se obtuvo el nombre
echo "Bucket para código Lambda: $LAMBDA_BUCKET"
```

### Paso 5: Subir Código Lambda al Bucket

```bash
# Subir el archivo ZIP al bucket S3
aws s3 cp lambda-functions.zip s3://$LAMBDA_BUCKET/lambda-functions.zip

# Verificar que se subió correctamente
aws s3 ls s3://$LAMBDA_BUCKET/
```

### Paso 6: Validar Template Principal

```bash
# Validar el template de CloudFormation antes del despliegue
aws cloudformation validate-template --template-body file://infra/master-template.yml

# Si hay errores, se mostrarán aquí. Corrígelos antes de continuar.
```

### Paso 7: Desplegar Infraestructura Principal

```bash
# Desplegar el stack principal con todos los servicios
aws cloudformation deploy \
    --template-file infra/master-template.yml \
    --stack-name event-manager \
    --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
    --parameter-overrides \
        Environment=dev \
        DBUsername=event_admin \
        S3LambdaBucket=$LAMBDA_BUCKET \
        LambdaCodeKey=lambda-functions.zip

# Este paso puede tomar 15-20 minutos
```

### Paso 8: Verificar el Despliegue

```bash
# Ver el estado del stack principal
aws cloudformation describe-stacks --stack-name event-manager

# Ver todos los outputs del stack (endpoints, ARNs, etc.)
aws cloudformation describe-stacks \
    --stack-name event-manager \
    --query 'Stacks[0].Outputs' \
    --output table

# Listar todos los stacks creados
aws cloudformation list-stacks \
    --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
    --query 'StackSummaries[?contains(StackName, `event-manager`)].{Name:StackName,Status:StackStatus,Created:CreationTime}' \
    --output table
```

### Paso 9: Probar las Funciones Lambda

```bash
# Listar las funciones Lambda creadas
aws lambda list-functions \
    --query 'Functions[?contains(FunctionName, `event-manager`)].{Name:FunctionName,Runtime:Runtime,LastModified:LastModified}' \
    --output table

# Probar una función específica (ejemplo: CreateEvent)
aws lambda invoke \
    --function-name event-manager-CreateEventLambda \
    --payload '{"test": true}' \
    response.json

# Ver la respuesta
cat response.json
```

## ✅ Verificación del Despliegue Exitoso

Después del despliegue, deberías tener:

### Stacks de CloudFormation Creados:
- `event-manager-s3` - Buckets S3
- `event-manager` - Stack principal con nested stacks

### Recursos AWS Creados:
- ✅ **VPC** con subnets públicas y privadas
- ✅ **Aurora Serverless** (MySQL) con credenciales en Secrets Manager
- ✅ **12 Funciones Lambda** con código desplegado
- ✅ **API Gateway** con endpoints REST
- ✅ **Cognito User Pool** para autenticación
- ✅ **SQS Queues** para procesamiento de emails
- ✅ **S3 Buckets** (código Lambda + reportes)
- ✅ **Step Functions** para workflows
- ✅ **IAM Roles y Políticas** automáticas

### Endpoints Disponibles:
```bash
# Obtener la URL del API Gateway
aws cloudformation describe-stacks \
    --stack-name event-manager \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayUrl`].OutputValue' \
    --output text
```

## 🔐 Acceso a Credenciales

### Credenciales de Base de Datos (Automáticas)
```bash
# Ver las credenciales de la base de datos (generadas automáticamente)
aws secretsmanager get-secret-value \
    --secret-id event-app/db-credentials \
    --query SecretString --output text | jq .

# Obtener endpoint de la base de datos
aws cloudformation describe-stacks \
    --stack-name event-manager \
    --query 'Stacks[0].Outputs[?OutputKey==`DatabaseEndpoint`].OutputValue' \
    --output text
```

### Información del Cognito User Pool
```bash
# Obtener User Pool ID
aws cloudformation describe-stacks \
    --stack-name event-manager \
    --query 'Stacks[0].Outputs[?OutputKey==`CognitoUserPoolId`].OutputValue' \
    --output text

# Obtener App Client ID
aws cloudformation describe-stacks \
    --stack-name event-manager \
    --query 'Stacks[0].Outputs[?OutputKey==`CognitoAppClientId`].OutputValue' \
    --output text
```

## 🐛 Solución de Problemas

### Error: "Template validation failed"
```bash
# Validar template específico
aws cloudformation validate-template --template-body file://infra/master-template.yml

# Revisar sintaxis YAML
yamllint infra/master-template.yml
```

### Error: "Access Denied"
```bash
# Verificar credenciales
aws sts get-caller-identity

# Verificar permisos
aws iam get-user
```

### Error: "Bucket does not exist"
```bash
# Verificar que el bucket S3 existe
aws s3 ls s3://$LAMBDA_BUCKET

# Si no existe, repetir el paso 3
```

### Error: "Stack does not exist"
```bash
# Verificar stacks existentes
aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE

# El stack se crea automáticamente en el primer despliegue
```

### Ver Logs de Errores
```bash
# Ver eventos del stack para debugging
aws cloudformation describe-stack-events \
    --stack-name event-manager \
    --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]' \
    --output table

# Ver logs de CloudWatch
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/event-manager
```

## 🗑️ Limpiar Recursos (Opcional)

⚠️ **CUIDADO**: Esto eliminará toda la infraestructura y datos.

```bash
# Eliminar stack principal (esto puede tomar tiempo)
aws cloudformation delete-stack --stack-name event-manager

# Esperar a que se complete
aws cloudformation wait stack-delete-complete --stack-name event-manager

# Eliminar stack de S3 (después del principal)
aws cloudformation delete-stack --stack-name event-manager-s3

# Verificar que se eliminaron
aws cloudformation list-stacks \
    --stack-status-filter DELETE_COMPLETE \
    --query 'StackSummaries[?contains(StackName, `event-manager`)]'
```

## 📊 Monitoreo Post-Despliegue

### CloudWatch Logs
```bash
# Ver logs de una función específica
aws logs describe-log-streams \
    --log-group-name /aws/lambda/event-manager-CreateEventLambda

# Ver logs recientes
aws logs filter-log-events \
    --log-group-name /aws/lambda/event-manager-CreateEventLambda \
    --start-time $(date -d '1 hour ago' +%s)000
```

### Métricas de CloudWatch
```bash
# Ver métricas de Lambda
aws cloudwatch get-metric-statistics \
    --namespace AWS/Lambda \
    --metric-name Invocations \
    --dimensions Name=FunctionName,Value=event-manager-CreateEventLambda \
    --start-time $(date -d '1 hour ago' --iso-8601) \
    --end-time $(date --iso-8601) \
    --period 300 \
    --statistics Sum
```

## 🔐 Políticas IAM Mínimas Requeridas

Para el usuario/rol que ejecuta el despliegue:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "cloudformation:*",
                "lambda:*",
                "apigateway:*",
                "rds:*",
                "cognito-idp:*",
                "s3:*",
                "sqs:*",
                "ses:*",
                "states:*",
                "iam:*",
                "ec2:*",
                "logs:*",
                "secretsmanager:*"
            ],
            "Resource": "*"
        }
    ]
}
```

## ⏱️ Tiempos Estimados

- **Paso 1-2**: 2-3 minutos
- **Paso 3**: 2-3 minutos (crear S3)
- **Paso 4-5**: 1-2 minutos (subir código)
- **Paso 6-7**: 15-20 minutos (infraestructura principal)
- **Paso 8-9**: 2-3 minutos (verificación)

**Total estimado**: 25-30 minutos

## 📞 Soporte

Si encuentras problemas:

1. **Revisa los logs** en CloudWatch
2. **Verifica las credenciales** AWS
3. **Consulta los eventos** del stack en CloudFormation
4. **Valida los templates** antes del despliegue

---

## 🎉 ¡Despliegue Completado!

Una vez completados todos los pasos, tendrás un sistema completo de gestión de eventos funcionando en AWS con:

- API REST completamente funcional
- Base de datos Aurora Serverless
- Sistema de autenticación con Cognito
- Notificaciones automáticas por email
- Generación de reportes
- Monitoreo con CloudWatch

¡Tu aplicación estará lista para usar!
