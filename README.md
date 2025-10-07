# Event Manager AWS

Sistema de gestión de eventos con arquitectura serverless en AWS que permite crear, gestionar y generar reportes de eventos con notificaciones automáticas.

## 🏗️ Arquitectura

```
event-manager-aws/
├── infra/                          # Infraestructura como código
│   ├── master-template.yml         # Template principal CloudFormation
│   ├── templates/                  # Nested stacks
│   │   ├── vpc.yml                 # Red VPC para RDS + Lambdas
│   │   ├── rds.yml                 # Aurora Serverless (EventManagerDB)
│   │   ├── lambdas.yml             # Todas las funciones Lambda
│   │   ├── apigateway.yml          # API Gateway + Integraciones
│   │   ├── cognito.yml             # User Pool y App Clients
│   │   ├── sqs-ses.yml             # Colas SQS + permisos para SES
│   │   ├── s3.yml                  # Bucket para reportes
│   │   ├── stepfunctions.yml       # Workflow de generación de reportes
│   │   ├── eventbridge.yml         # Event Bus, Rules y Scheduler
│   │   └── initdb.yml              # Inicialización de base de datos
│   └── parameters/                 # Parámetros por entorno
│       ├── dev-params.json
│       └── prod-params.json
├── src/                            # Código de las funciones Lambda
│   ├── create-event/               # Crear eventos (publica a EventBridge)
│   ├── delete-event/               # Eliminar eventos (API + Scheduler)
│   ├── create-task/                # Crear tareas (triggered by EventBridge)
│   ├── update-event/               # Actualizar eventos
│   ├── disable-event/              # Deshabilitar eventos
│   ├── get-active-events/          # Obtener eventos activos
│   ├── post-event-assistance/      # Registrar asistencia
│   ├── send-event-reminder/        # Enviar recordatorios
│   ├── send-email/                 # Servicio de email
│   ├── generate-report/            # Generar reportes
│   ├── get-report/                 # Obtener reportes
│   ├── init-db/                    # Inicializar base de datos
│   └── process-report-data/        # Procesar datos de reportes
└── pipeline/
    └── bitbucket-pipelines.yml     # CI/CD para despliegue automático
```

## 🚀 Servicios AWS Utilizados

- **VPC**: Red privada personalizada
- **Aurora Serverless**: Base de datos MySQL serverless
- **API Gateway**: API REST con autenticación Cognito
- **Lambda Functions**: 13 funciones serverless en Node.js
- **Cognito User Pools**: Autenticación y autorización
- **SQS + SES**: Colas de mensajes y servicio de email
- **S3**: Almacenamiento de reportes
- **Step Functions**: Orquestación de workflows
- **EventBridge**: Event bus y scheduler para automatización
- **CloudFormation**: Infraestructura como código

## 📋 Funcionalidades

### Gestión de Eventos
- ✅ Crear eventos con detalles completos
- ✅ Actualizar información de eventos
- ✅ Deshabilitar/eliminar eventos
- ✅ Consultar eventos activos

### Automatización con EventBridge
- ✅ **Creación automática de tareas** cuando se crea un evento
- ✅ **Eliminación programada** de eventos en su fecha de ejecución
- ✅ Event-driven architecture con EventBridge Event Bus
- ✅ Scheduler dinámico para cada evento

### Sistema de Notificaciones
- ✅ Recordatorios automáticos por email
- ✅ Notificaciones de confirmación
- ✅ Colas SQS para procesamiento asíncrono

### Reportes y Analytics
- ✅ Generación de reportes de asistencia
- ✅ Almacenamiento en S3
- ✅ Procesamiento con Step Functions

### Seguridad
- ✅ Autenticación con Cognito
- ✅ API Gateway con autorización
- ✅ VPC para aislamiento de red

## 🛠️ Configuración y Despliegue

### Prerrequisitos

1. **Cuenta AWS** con permisos administrativos
2. **AWS CLI** configurado
3. **Repositorio Bitbucket** (para CI/CD)
4. **Node.js** (para desarrollo local)

### Despliegue Manual

#### 🐧 Linux/macOS (usando bash)

```bash
# Usar script automatizado (recomendado)
./scripts/deploy.sh

# O despliegue manual paso a paso:

# 1. Empaquetar funciones Lambda
zip -r lambda-functions.zip src/

# 2. Crear buckets S3 automáticamente
aws cloudformation deploy \
  --template-file infra/templates/s3.yml \
  --stack-name event-manager-s3 \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides Environment=dev

# 3. Obtener nombre del bucket creado automáticamente
export LAMBDA_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name event-manager-s3 \
  --query 'Stacks[0].Outputs[?OutputKey==`LambdaCodeBucketName`].OutputValue' \
  --output text)

# 4. Subir código al bucket creado automáticamente
aws s3 cp lambda-functions.zip s3://$LAMBDA_BUCKET/lambda-functions.zip

# 5. Desplegar infraestructura principal
aws cloudformation deploy \
  --template-file infra/master-template.yml \
  --stack-name event-manager \
  --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
  --parameter-overrides \
    Environment=dev \
    DBUsername=event_admin \
    S3LambdaBucket=$LAMBDA_BUCKET \
    LambdaCodeKey=lambda-functions.zip
```

#### 🪟 Windows

```powershell
# Opción 1: PowerShell (recomendado)
.\scripts\deploy.ps1

# Opción 2: Batch file
.\scripts\deploy.bat

# Opción 3: WSL
./scripts/deploy.sh
```

#### ✨ Scripts Automatizados Disponibles

**Despliegue Completo:**
- **`./scripts/deploy.sh`** - Script completo para Linux/macOS
- **`.\scripts\deploy.ps1`** - Script completo para Windows PowerShell  
- **`.\scripts\deploy.bat`** - Script básico para Windows CMD

**Actualización de Código Lambda:**
- **`./scripts/upload-lambda-code.sh`** - Subir y actualizar código Lambda (Linux/macOS)
- **`.\scripts\upload-lambda-code.bat`** - Subir y actualizar código Lambda (Windows)

**Inicialización de Base de Datos:**
- **`./scripts/run-init-db.sh`** - Ejecutar InitDB para crear/actualizar tablas (Linux/macOS)
- **`.\scripts\run-init-db.bat`** - Ejecutar InitDB para crear/actualizar tablas (Windows)

**Utilidades:**
- **`./scripts/cleanup.sh`** - Limpiar recursos
- **`./scripts/status.sh`** - Verificar estado del despliegue

🎉 **Los scripts automatizan TODO:**
- Buckets S3 (código Lambda + reportes)
- Contraseña de base de datos (Secrets Manager)
- Creación y inicialización de RDS
- VPC, Cognito, API Gateway, Step Functions, etc.

### Despliegue Automático con Bitbucket

#### 1. Configurar Repositorio

1. Crea un repositorio en [Bitbucket.org](https://bitbucket.org)
2. Sube tu código al repositorio
3. Ve a **Repository settings** > **Pipelines** > **Settings**
4. Habilita **Enable Pipelines**

#### 2. Variables de Entorno

Ve a **Repository settings** > **Pipelines** > **Repository variables** y configura:

| Variable | Descripción | Ejemplo | Secured |
|----------|-------------|---------|---------|
| `AWS_ACCESS_KEY_ID` | Access Key de AWS | `AKIA...` | No |
| `AWS_SECRET_ACCESS_KEY` | Secret Key de AWS | `...` | ✅ Sí |
| `AWS_DEFAULT_REGION` | Región de AWS | `us-east-1` | No |
| `DB_USERNAME` | Usuario de la base de datos | `event_admin` | No |
| `STACK_NAME` | Nombre del stack CloudFormation | `event-manager` | No |
| `ENVIRONMENT` | Entorno (dev/prod) | `dev` | No |

> **🎉 Todo Automático**: No necesitas configurar `DB_PASSWORD` ni `S3_LAMBDA_BUCKET` porque se crean automáticamente durante el despliegue.

#### 3. Credenciales AWS

**Opción A: Usuario IAM (Desarrollo)**
1. Crea un usuario IAM en AWS Console
2. Asigna políticas: `PowerUserAccess` + `IAMFullAccess`
3. Genera Access Keys
4. Configura las variables en Bitbucket

**Opción B: Roles IAM (Producción)**
1. Configura OpenID Connect entre Bitbucket y AWS
2. Crea un rol IAM con las políticas necesarias

#### 4. Políticas IAM Mínimas

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
                "logs:*"
            ],
            "Resource": "*"
        }
    ]
}
```

#### 5. Flujo de Branches

- **develop**: Despliegue automático a desarrollo
- **main**: Despliegue manual a producción
- **feature/***: Pipeline de validación sin despliegue

## 🔐 Manejo Automático de Credenciales

### Cómo Funciona el Sistema de Credenciales

El proyecto utiliza **AWS Secrets Manager** para manejar automáticamente las credenciales de la base de datos:

#### 1. **Generación Automática de Contraseñas**
```yaml
# En rds.yml - CloudFormation genera automáticamente la contraseña
DBCredentialsSecret:
  Type: AWS::SecretsManager::Secret
  Properties:
    Name: event-app/db-credentials
    GenerateSecretString:
      SecretStringTemplate: '{"username":"event_admin"}'
      GenerateStringKey: password
      PasswordLength: 30
      ExcludePunctuation: true
```

#### 2. **Acceso desde Lambda Functions**
```javascript
// En tus funciones Lambda - Código de ejemplo
const AWS = require('aws-sdk');
const secretsManager = new AWS.SecretsManager();

async function getDBCredentials() {
    const secretArn = process.env.RDS_SECRET_ARN;
    const secret = await secretsManager.getSecretValue({
        SecretId: secretArn
    }).promise();
    
    return JSON.parse(secret.SecretString);
}

// Uso en tu función
const dbCredentials = await getDBCredentials();
const connection = mysql.createConnection({
    host: process.env.DB_ENDPOINT,
    user: dbCredentials.username,
    password: dbCredentials.password,
    database: process.env.DB_NAME
});
```

#### 3. **Variables de Entorno Automáticas**
Las funciones Lambda reciben automáticamente:
- `RDS_SECRET_ARN`: ARN del secreto en Secrets Manager
- `DB_NAME`: Nombre de la base de datos
- `DB_ENDPOINT`: Endpoint del cluster Aurora

#### 4. **Buckets S3 - Dos Tipos Diferentes**

**Bucket para Código Lambda (Manual - Pre-requisito):**
- `S3_LAMBDA_BUCKET`: Debes crearlo ANTES del despliegue
- Contiene el código empaquetado de las funciones Lambda
- Se especifica como variable de entorno porque CloudFormation lo necesita para desplegar

**Bucket para Reportes (Automático - Creado por YAML):**
- `REPORTS_BUCKET`: Se crea automáticamente por el template S3
- Usado por las funciones Lambda para almacenar reportes generados
- Se pasa como variable de entorno a las funciones Lambda

### Obtener Credenciales Manualmente (Si Necesario)

Si necesitas acceder a las credenciales desde fuera de Lambda:

```bash
# Obtener credenciales de la base de datos
aws secretsmanager get-secret-value \
    --secret-id event-app/db-credentials \
    --query SecretString --output text | jq .

# Obtener outputs del stack CloudFormation
aws cloudformation describe-stacks \
    --stack-name event-manager \
    --query 'Stacks[0].Outputs'
```

## 🔧 Pipeline de CI/CD

El pipeline de Bitbucket ejecuta automáticamente:

1. **Build**: Instala dependencias y empaqueta Lambda functions
2. **Upload**: Sube el código a S3
3. **Deploy**: Despliega infraestructura con CloudFormation
4. **Initialize**: Ejecuta la función de inicialización de BD

### Flujo de Credenciales en el Pipeline

1. **CloudFormation** crea el secreto en Secrets Manager
2. **Aurora** se configura automáticamente con las credenciales del secreto
3. **Lambda Functions** reciben el ARN del secreto como variable de entorno
4. **Funciones** acceden a las credenciales usando el SDK de AWS

## 📊 Monitoreo y Logs

- **CloudWatch Logs**: Logs de todas las funciones Lambda
- **CloudWatch Metrics**: Métricas de rendimiento
- **X-Ray**: Trazabilidad de requests (opcional)

## 🐛 Troubleshooting

### Errores Comunes

**"Template validation failed"**
```bash
# Validar template localmente
aws cloudformation validate-template --template-body file://infra/master-template.yml
```

**"Access Denied"**
- Verifica credenciales AWS
- Confirma permisos del usuario/rol

**"Bucket does not exist"**
```bash
# Crear bucket S3 manualmente
aws s3 mb s3://tu-bucket-name --region us-east-1
```

**"Stack does not exist"**
- El stack se crea automáticamente en el primer despliegue
- Verifica que el nombre sea único en tu cuenta AWS

### Comandos Útiles

```bash
# Listar stacks
aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE

# Ver eventos del stack
aws cloudformation describe-stack-events --stack-name event-manager

# Eliminar stack (¡CUIDADO en producción!)
aws cloudformation delete-stack --stack-name event-manager

# Invocar función Lambda
aws lambda invoke --function-name event-manager-CreateEventLambda --payload '{}' response.json
```

## 🔐 Seguridad

- Todas las contraseñas deben marcarse como **secured** en Bitbucket
- Usar roles IAM en lugar de usuarios para producción
- Habilitar MFA en cuentas AWS
- Rotar credenciales regularmente
- Revisar políticas IAM periódicamente

## 📝 Desarrollo Local

### Configuración del Entorno Local

1. **Copia el archivo de variables de entorno:**
```bash
cp .env.example .env
```

2. **Edita el archivo `.env` con tus credenciales:**
```bash
# Variables requeridas para desarrollo local
AWS_ACCESS_KEY_ID=tu-access-key
AWS_SECRET_ACCESS_KEY=tu-secret-key
AWS_DEFAULT_REGION=us-east-1
STACK_NAME=event-manager-dev
ENVIRONMENT=dev
S3_LAMBDA_BUCKET=tu-bucket-lambda-code
DB_USERNAME=event_admin
```

3. **Instalar dependencias:**
```bash
# En el directorio raíz
npm install

# En cada función Lambda (si tienen package.json)
for dir in src/*/; do
  if [ -f "$dir/package.json" ]; then
    cd "$dir" && npm install && cd -
  fi
done
```

4. **Comandos útiles para desarrollo:**
```bash
# Validar templates CloudFormation
aws cloudformation validate-template --template-body file://infra/master-template.yml

# Ejecutar tests (si existen)
npm test

# Actualizar solo el código Lambda (desarrollo rápido)
./scripts/upload-lambda-code.sh

# Actualizar modelo de base de datos
./scripts/run-init-db.sh

# Invocar función Lambda después del despliegue
aws lambda invoke \
  --function-name CreateEventLambda-dev \
  --payload '{"test": true}' \
  response.json
```

### 🔄 Flujo de Desarrollo Rápido

Para desarrollo iterativo sin redesplegar toda la infraestructura:

**1. Modificar código Lambda:**
```bash
# Editar archivos en src/
vim src/create-event/index.js
```

**2. Actualizar funciones Lambda:**
```bash
# Linux/macOS
./scripts/upload-lambda-code.sh

# Windows PowerShell
.\scripts\upload-lambda-code.ps1

# Windows CMD
scripts\upload-lambda-code.bat
```

Este script automáticamente:
- ✅ Instala dependencias de Node.js
- ✅ Empaqueta todas las funciones Lambda
- ✅ Sube el código a S3
- ✅ **Actualiza las 12 funciones Lambda automáticamente**

**3. Actualizar modelo de base de datos:**

Si modificas el esquema en `src/init-db/index.js`:

```bash
# Linux/macOS
./scripts/run-init-db.sh

# Windows PowerShell
.\scripts\run-init-db.ps1

# Windows CMD
scripts\run-init-db.bat
```

Este script:
- ✅ Ejecuta la función InitDB Lambda
- ✅ Crea/actualiza tablas: `users`, `events`, `event_assistance`, `report`
- ✅ Crea índices para optimización
- ✅ Muestra logs detallados de la operación

**4. Probar cambios:**
```bash
# Invocar función actualizada
aws lambda invoke \
  --function-name CreateEventLambda-dev \
  --payload file://test-payload.json \
  response.json

# Ver respuesta
cat response.json | jq '.'
```

### Variables de Entorno por Contexto

| Contexto | Variables Requeridas |
|----------|---------------------|
| **Desarrollo Local** | AWS credentials, STACK_NAME, ENVIRONMENT, S3_LAMBDA_BUCKET, DB_USERNAME |
| **Bitbucket Pipeline** | Mismas variables configuradas en Repository Settings |
| **Funciones Lambda** | Se configuran automáticamente por CloudFormation |

## 🤝 Contribución

1. Crea una rama feature desde `develop`
2. Realiza tus cambios
3. Haz push y crea un Pull Request
4. El pipeline validará automáticamente los cambios
5. Merge a `develop` para despliegue a desarrollo
6. Merge a `main` para despliegue a producción (manual)

## 📞 Soporte

Para problemas o preguntas:
1. Revisa los logs en CloudWatch
2. Consulta la sección de Troubleshooting
3. Verifica el estado del pipeline en Bitbucket
