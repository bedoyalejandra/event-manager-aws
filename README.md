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
│   │   └── initdb.yml              # Inicialización de base de datos
│   └── parameters/                 # Parámetros por entorno
│       ├── dev-params.json
│       └── prod-params.json
├── src/                            # Código de las funciones Lambda
│   ├── create-event/               # Crear eventos
│   ├── delete-event/               # Eliminar eventos
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
- **Lambda Functions**: 12 funciones serverless en Node.js
- **Cognito User Pools**: Autenticación y autorización
- **SQS + SES**: Colas de mensajes y servicio de email
- **S3**: Almacenamiento de reportes
- **Step Functions**: Orquestación de workflows
- **CloudFormation**: Infraestructura como código

## 📋 Funcionalidades

### Gestión de Eventos
- ✅ Crear eventos con detalles completos
- ✅ Actualizar información de eventos
- ✅ Deshabilitar/eliminar eventos
- ✅ Consultar eventos activos

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

```bash
# 1. Crear bucket para código Lambda
aws s3 mb s3://tu-bucket-lambda-code --region us-east-1

# 2. Empaquetar funciones Lambda
zip -r lambda-functions.zip src/

# 3. Subir código a S3
aws s3 cp lambda-functions.zip s3://tu-bucket-lambda-code/

# 4. Desplegar infraestructura
aws cloudformation deploy \
  --template-file infra/master-template.yml \
  --stack-name event-manager \
  --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
  --parameter-overrides \
    Environment=dev \
    DBUsername=admin \
    DBPassword=tu-password \
    S3LambdaBucket=tu-bucket-lambda-code \
    LambdaCodeKey=lambda-functions.zip
```

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
| `DB_USERNAME` | Usuario de la base de datos | `admin` | No |
| `DB_PASSWORD` | Contraseña de la base de datos | `...` | ✅ Sí |
| `S3_LAMBDA_BUCKET` | Bucket S3 para código Lambda | `event-manager-lambda-code` | No |
| `STACK_NAME` | Nombre del stack CloudFormation | `event-manager` | No |
| `ENVIRONMENT` | Entorno (dev/prod) | `dev` | No |

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

## 🔧 Pipeline de CI/CD

El pipeline de Bitbucket ejecuta automáticamente:

1. **Build**: Instala dependencias y empaqueta Lambda functions
2. **Upload**: Sube el código a S3
3. **Deploy**: Despliega infraestructura con CloudFormation
4. **Initialize**: Ejecuta la función de inicialización de BD

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

```bash
# Instalar dependencias
npm install

# Ejecutar tests (si existen)
npm test

# Validar templates CloudFormation
aws cloudformation validate-template --template-body file://infra/master-template.yml
```

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
