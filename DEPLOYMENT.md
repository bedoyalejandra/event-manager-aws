# 🚀 Guía de Despliegue - Event Manager AWS

Esta guía te llevará paso a paso por el proceso de despliegue de la aplicación Event Manager en AWS.

---

## 📋 Requisitos Previos

Antes de comenzar, asegúrate de tener:

- ✅ **Git** instalado
- ✅ **AWS CLI** instalado y configurado
- ✅ **Node.js** (v14 o superior) y **npm** instalados
- ✅ **Credenciales AWS** con permisos de administrador
- ✅ **Postman** instalado para realizar las pruebas

---

## 📥 Paso 1: Descargar el Código del Repositorio

### 1.1 Clonar el repositorio

Abre tu terminal y ejecuta:

```bash
git clone https://github.com/bedoyalejandra/event-manager-aws.git
```

### 1.2 Navegar al directorio del proyecto

```bash
cd event-manager-aws
```

### 1.3 Verificar la estructura del proyecto

```bash
ls -la
```

Deberías ver los siguientes archivos y carpetas:
- `infra/` - Templates de CloudFormation
- `src/` - Código de las funciones Lambda
- `scripts/` - Scripts de despliegue
- `events-manager.postman_collection.json` - Colección de Postman
- `.env.example` - Ejemplo de variables de entorno
- `README.md` - Documentación principal

---

## 🔧 Paso 2: Configurar Variables de Entorno

### 2.1 Copiar el archivo de ejemplo

```bash
cp .env.example .env
```

### 1.2 Editar el archivo `.env`

Abre el archivo `.env` y completa los siguientes valores:

```bash
# Credenciales AWS
AWS_ACCESS_KEY_ID=tu_access_key_id
AWS_SECRET_ACCESS_KEY=tu_secret_access_key
AWS_DEFAULT_REGION=us-west-2

# Configuración del proyecto
ENVIRONMENT=dev
DB_USERNAME=event_admin
```

**Notas importantes:**
- Reemplaza `tu_access_key_id` y `tu_secret_access_key` con tus credenciales reales de AWS
- La región por defecto es `us-west-2`, pero puedes cambiarla según tu preferencia
- El `ENVIRONMENT` puede ser `dev`, `staging` o `prod`

### 1.3 Verificar credenciales

Ejecuta el siguiente comando para verificar que tus credenciales funcionan:

```bash
aws sts get-caller-identity
```

Deberías ver información sobre tu cuenta AWS.

---

## 🚀 Paso 2: Ejecutar el Script de Despliegue

### 2.1 Dar permisos de ejecución al script

```bash
chmod +x scripts/deploy.sh
```

### 2.2 Ejecutar el despliegue

```bash
./scripts/deploy.sh
```

### 2.3 ¿Qué hace el script?

El script automatiza todo el proceso de despliegue:

1. ✅ **Verificaciones previas**: Valida credenciales AWS y estructura del proyecto
2. ✅ **Preparación del entorno**: Configura variables de entorno
3. ✅ **Empaquetado Lambda**: Instala dependencias y crea el archivo ZIP
4. ✅ **Creación de buckets S3**: Crea buckets para código Lambda y reportes
5. ✅ **Subida de código**: Sube el código Lambda a S3
6. ✅ **Subida de templates**: Sube templates de CloudFormation a S3
7. ✅ **Creación de RDS**: Crea la base de datos MySQL automáticamente
8. ✅ **Despliegue de stacks**: Despliega toda la infraestructura
9. ✅ **Inicialización de BD**: Crea las tablas necesarias automáticamente
10. ✅ **Verificación**: Valida que todo esté funcionando correctamente

### 2.4 Tiempo estimado

El despliegue completo toma aproximadamente **15-20 minutos**.

---

## 📝 Paso 3: Obtener Información del Despliegue

Una vez completado el despliegue, el script mostrará información importante:

```
✅ DESPLIEGUE COMPLETADO EXITOSAMENTE

📊 Información del Stack:
  - Stack Name: event-manager-dev
  - API Gateway URL: https://xxxxxxxxxx.execute-api.us-west-2.amazonaws.com/dev
  - Cognito User Pool ID: us-west-2_XXXXXXXXX
  - Cognito Client ID: xxxxxxxxxxxxxxxxxxxxxxxxxx
  - Database Endpoint: event-manager-db-dev.xxxxxxxxxx.us-west-2.rds.amazonaws.com
```

**Guarda esta información**, la necesitarás para configurar Postman.

---

## 🧪 Paso 4: Configurar Postman para Pruebas

### 4.1 Importar la colección

1. Abre **Postman**
2. Haz clic en **Import**
3. Selecciona el archivo `events-manager.postman_collection.json` del proyecto
4. La colección se importará con todas las peticiones configuradas

### 4.2 Configurar variables de entorno en Postman

1. En Postman, haz clic en el ícono de **Environments** (⚙️) en la esquina superior derecha
2. Haz clic en **Create Environment** o selecciona un entorno existente
3. Agrega las siguientes variables:

| Variable | Valor | Descripción |
|----------|-------|-------------|
| `CLIENT_ID` | `xxxxxxxxxxxxxxxxxxxxxxxxxx` | Cognito Client ID (del output del despliegue) |
| `REGION` | `us-west-2` | Región AWS donde desplegaste |
| `URL` | `https://xxxxxxxxxx.execute-api.us-west-2.amazonaws.com/dev` | API Gateway URL (del output del despliegue) |
| `TOKEN` | *(se genera automáticamente)* | Se obtiene automáticamente al hacer login |

**Ejemplo de configuración:**

```
CLIENT_ID: 6i59fgnk4k550bqeq8mq6m7tjs
REGION: us-west-2
URL: https://s5p727z145.execute-api.us-west-2.amazonaws.com/dev
TOKEN: (se genera automáticamente al hacer login)
```

### 4.3 Guardar el entorno

1. Haz clic en **Save** para guardar las variables
2. Asegúrate de que el entorno esté **seleccionado** (activo) en el dropdown superior

---

## 🎯 Paso 5: Realizar Pruebas

### 5.1 Flujo de pruebas recomendado

La colección de Postman incluye las siguientes peticiones organizadas en carpetas:

#### **Carpeta: Auth**

1. **SignUp** - Registrar un nuevo usuario
   - Modifica el `Username`, `Password` y `email` según necesites
   - Ejecuta la petición
   - Recibirás un código de confirmación en el email proporcionado

2. **Confirm User** - Confirmar el registro
   - Copia el código de confirmación recibido por email
   - Pégalo en el campo `ConfirmationCode`
   - Ejecuta la petición

3. **LogIn** - Iniciar sesión
   - Usa el mismo `Username` y `Password` del registro
   - Ejecuta la petición
   - **El TOKEN se guardará automáticamente** en las variables de entorno
   - Verás un mensaje en la consola: `✅ Token saved successfully!`

#### **Carpeta: Events**

Una vez autenticado, puedes probar los endpoints de eventos:

4. **Create event** - Crear un nuevo evento
   - El token se incluye automáticamente en el header
   - Modifica los datos del evento según necesites
   - Ejecuta la petición

5. **GetActiveEvents** - Obtener todos los eventos activos
   - Lista todos los eventos disponibles
   - Ejecuta la petición

6. **Actualizar event** - Actualizar un evento existente
   - Cambia el ID del evento en la URL
   - Modifica los campos que desees actualizar
   - Ejecuta la petición

7. **Delete event** - Eliminar un evento
   - Cambia el ID del evento en la URL
   - Ejecuta la petición

8. **Post event assistance** - Registrar asistencia a un evento
   - Modifica el `eventId` y datos del usuario
   - Ejecuta la petición

9. **Create Report** - Generar un reporte
   - Proporciona los datos del reporte
   - Ejecuta la petición

10. **Get Report** - Obtener un reporte
    - Ejecuta la petición

### 5.2 Notas importantes sobre las pruebas

- ✅ **El TOKEN se renueva automáticamente**: Cada vez que ejecutes **LogIn**, el token se actualiza
- ✅ **Autenticación automática**: Todas las peticiones de eventos usan el token guardado
- ✅ **Códigos de respuesta**: 
  - `200` = Éxito
  - `201` = Creado exitosamente
  - `400` = Error en la petición
  - `401` = No autenticado
  - `500` = Error del servidor

---

## 🔍 Verificación del Despliegue

### Verificar servicios en AWS Console

1. **CloudFormation**: Verifica que el stack `event-manager-dev` esté en estado `CREATE_COMPLETE`
2. **API Gateway**: Verifica que la API esté desplegada
3. **Lambda**: Verifica que las 12 funciones Lambda estén creadas
4. **RDS**: Verifica que la base de datos esté disponible
5. **Cognito**: Verifica que el User Pool esté creado

### Comandos útiles

```bash
# Ver el estado del stack principal
aws cloudformation describe-stacks --stack-name event-manager-dev

# Listar todas las funciones Lambda
aws lambda list-functions --query 'Functions[?contains(FunctionName, `event-manager`)].FunctionName'

# Ver logs de una función Lambda
aws logs tail /aws/lambda/CreateEventLambda-dev --follow

# Ver el endpoint de la API
aws cloudformation describe-stacks --stack-name event-manager-dev \
  --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayUrl`].OutputValue' --output text
```

---

## 🛠️ Troubleshooting

### Problema: "Stack already exists"

**Solución**: Elimina el stack existente antes de redesplegar:

```bash
aws cloudformation delete-stack --stack-name event-manager-dev
aws cloudformation wait stack-delete-complete --stack-name event-manager-dev
```

### Problema: "Access Denied" al crear recursos

**Solución**: Verifica que tus credenciales AWS tengan los permisos necesarios:
- CloudFormation
- Lambda
- API Gateway
- RDS
- S3
- Cognito
- IAM

### Problema: "Token expired" en Postman

**Solución**: Ejecuta nuevamente la petición **LogIn** para obtener un nuevo token.

### Problema: Error al conectar con la base de datos

**Solución**: Verifica que el InitDB Lambda se haya ejecutado correctamente:

```bash
aws lambda invoke --function-name InitDBLambda-dev response.json
cat response.json
```

### Problema: No recibo el código de confirmación

**Solución**: 
1. Verifica que el email sea válido
2. Revisa la carpeta de spam
3. Usa un servicio de email temporal como mailinator.com para pruebas

---

## 🧹 Limpieza de Recursos

Para eliminar todos los recursos creados y evitar costos:

```bash
# Eliminar el stack principal (esto eliminará todos los nested stacks)
aws cloudformation delete-stack --stack-name event-manager-dev

# Esperar a que se complete la eliminación
aws cloudformation wait stack-delete-complete --stack-name event-manager-dev

# Eliminar buckets S3 manualmente (si tienen contenido)
aws s3 rb s3://event-manager-lambda-code-dev-ACCOUNT_ID --force
aws s3 rb s3://event-manager-reports-dev-ACCOUNT_ID --force

# Eliminar la base de datos RDS manualmente
aws rds delete-db-instance \
  --db-instance-identifier event-manager-db-dev \
  --skip-final-snapshot
```

---

## 📚 Recursos Adicionales

- **Documentación completa**: Ver `README.md`
- **Arquitectura del sistema**: Ver diagrama en `arquitecture.png`
- **Pipeline CI/CD**: Ver `bitbucket-pipelines.yml`
- **Templates CloudFormation**: Ver carpeta `infra/`

---

## ✅ Checklist de Despliegue

- [ ] Configurar archivo `.env` con credenciales AWS
- [ ] Ejecutar `./scripts/deploy.sh`
- [ ] Guardar outputs del despliegue (API URL, Client ID, etc.)
- [ ] Importar colección de Postman
- [ ] Configurar variables de entorno en Postman
- [ ] Ejecutar petición SignUp
- [ ] Confirmar usuario con código de email
- [ ] Ejecutar petición LogIn (guarda TOKEN automáticamente)
- [ ] Probar endpoints de eventos
- [ ] Verificar que todo funcione correctamente

---

## 🎉 ¡Listo!

Tu aplicación Event Manager está desplegada y lista para usar. Si tienes problemas, revisa la sección de **Troubleshooting** o consulta los logs en CloudWatch.

**¡Feliz desarrollo! 🚀**
