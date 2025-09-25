event-app/
│── infra/                      
│   ├── master-template.yml         # Orquestador (incluye nested stacks)
│   ├── templates/
│   │   ├── vpc.yml                 # Red para RDS + Lambdas
│   │   ├── rds.yml                 # Aurora Serverless (EventManagerDB)
│   │   ├── lambdas.yml             # Todas las funciones Lambda
│   │   ├── apigateway.yml          # API Gateway + Integraciones
│   │   ├── cognito.yml             # User Pool y App Clients
│   │   ├── sqs-ses.yml             # Colas SQS + permisos para SES
│   │   ├── s3.yml                  # Bucket para reportes
│   │   └── stepfunctions.yml       # Workflow de generación de reportes
│   └── parameters/
│       ├── dev-params.json
│       └── prod-params.json
│
│── src/                            # Código de las Lambdas
│   ├── create-event/index.js
│   ├── delete-event/index.js
│   ├── update-event/index.js
│   ├── disable-event/index.js
│   ├── get-active-events/index.js
│   ├── post-event-assistance/index.js
│   ├── send-event-reminder/index.js
│   ├── send-email/index.js
│   ├── generate-report/index.js
│   ├── get-report/index.js
│   └── process-report-data/index.js
│
│── pipeline/
│   └── bitbucket-pipelines.yml     # CI/CD para despliegue automático
│
│── README.md                       # Documentación del despliegue
