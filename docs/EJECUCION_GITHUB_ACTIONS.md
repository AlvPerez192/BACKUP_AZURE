# Ejecución desde GitHub Actions (AWS Academy)

Guía completa para ejecutar el ciclo de vida del proyecto desde la web
de GitHub, usando AWS Academy + Azure for Students + backend S3.

---

## Workflows incluidos (orden de uso)

| # | Workflow | Cuándo se usa |
|---|---|---|
| 1 | Setup Terraform State Bucket (S3) | Primera vez |
| 2 | Setup Azure Blob Storage | Primera vez |
| 3 | Build and Push Docker image | Primera vez (y al cambiar la app) |
| 4 | Setup AWS RDS Test | Cada vez que reinicias el lab |
| 5 | Load test data | Tras crear la RDS |
| 6 | Backup RDS to Azure Blob | Manualmente, antes de probar failover |
| 7 | Failover Pilot Light | Para simular fallo de AWS |
| 8 | Destroy Pilot Light | Tras la prueba de failover |
| 9 | Destroy AWS RDS Test | Antes de cerrar el lab |

---

## FASE 0: Preparación (una sola vez, en local)

### 0.1. Crear el repositorio en GitHub

```bash
git init tfg-infra
cd tfg-infra
# Copiar todos los archivos generados aquí
git add .
git commit -m "estructura inicial"
git branch -M main
git remote add origin https://github.com/TU_USUARIO/tfg-infra.git
git push -u origin main
```

### 0.2. Service principal de Azure

```bash
az login
az account show --query id -o tsv   # apunta tu subscription ID

az ad sp create-for-rbac \
  --name "tfg-github-actions" \
  --role contributor \
  --scopes /subscriptions/TU_SUBSCRIPTION_ID \
  --sdk-auth
```

Copia el JSON completo de la salida; lo pegarás como secreto `AZURE_CREDENTIALS`.

---

## FASE 1: Configurar secretos en GitHub

`Settings → Secrets and variables → Actions → New repository secret`

### Secretos que se definen ya (al inicio)

| Secreto | Valor | De dónde sale |
|---|---|---|
| `AWS_ACCESS_KEY_ID` | `ASIA...` | AWS Academy → Start Lab → AWS Details → AWS CLI |
| `AWS_SECRET_ACCESS_KEY` | `wJalr...` | AWS Academy → AWS Details |
| `AWS_SESSION_TOKEN` | `IQoJb3J...` | AWS Academy → AWS Details |
| `AZURE_CREDENTIALS` | JSON completo | Salida del `az ad sp create-for-rbac` |
| `DB_PASSWORD` | `TuPassSegura123!` | Inventada (mín 8 chars) |
| `DB_USER` | `admin` | Fijo |
| `VM_ADMIN_PASSWORD` | `OtraPassSegura456!` | Inventada (mín 12 chars, exigencia de Azure) |

### Secretos que se rellenan después (placeholder ahora con cualquier valor)

| Secreto | Se rellena en | Con valor sacado de... |
|---|---|---|
| `TFSTATE_BUCKET` | tras Fase 2.1 | output del workflow Setup Terraform State Bucket |
| `AZURE_STORAGE_KEY` | tras Fase 2.2 | artifact descargable del workflow Setup Azure Blob |
| `APP_IMAGE` | tras Fase 2.3 | output del workflow Build and Push Docker image |
| `AWS_RDS_HOST` | tras Fase 4 | output del workflow Setup AWS RDS Test |

> Crea cada secreto con un valor cualquiera (ej: `pendiente`) y lo
> actualizas más adelante. GitHub no permite ejecutar workflows que
> referencien secretos inexistentes.

---

## FASE 2: Setup inicial (una sola vez)

### 2.1. Crear el bucket de tfstate

`Actions → Setup Terraform State Bucket (S3) → Run workflow`

- Input `bucket_suffix`: pon algo único, p. ej. `pepito-2026`.
- Espera ~30s.
- Al final del log verás: `BUCKET LISTO: tfg-tfstate-pepito-2026`.
- **Copia ese nombre** y pégalo en el secreto `TFSTATE_BUCKET`.

### 2.2. Crear el Blob Storage

`Actions → Setup Azure Blob Storage → Run workflow`

- Espera ~1 min.
- En la página del run, baja hasta **Artifacts** y descarga
  `azure-storage-key`.
- Descomprime el zip, abre `AZURE_STORAGE_KEY.txt`, copia el contenido.
- Pégalo en el secreto `AZURE_STORAGE_KEY` de GitHub.

### 2.3. Construir la imagen Docker

`Actions → Build and Push Docker image → Run workflow`

- Tarda ~3 min (la primera vez; las siguientes ~30s con caché).
- Al final verás: `URL: ghcr.io/tu-usuario/tfg-infra/tfg-web:latest`.
- **Copia esa URL** y pégala en el secreto `APP_IMAGE`.
- **Hacer pública la imagen** (importante, si no la VM no podrá hacer
  pull):
  - Ve a tu perfil → **Packages** → click en `tfg-web`.
  - **Package settings** (botón abajo a la derecha) → **Change visibility**
    → **Public**.

---

## FASE 3: Cada sesión de lab (RDS de prueba)

### 3.1. Reiniciar credenciales de AWS Academy

Cada vez que reinicies el lab, las credenciales cambian. Hay que actualizar:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_SESSION_TOKEN`

### 3.2. Crear la RDS

`Actions → Setup AWS RDS Test → Run workflow`

- Tarda ~5-7 min (RDS tarda en arrancar).
- En el resumen verás el hostname:
  `tfg-test-mysql.xxxxx.eu-west-1.rds.amazonaws.com`.
- Pégalo en el secreto `AWS_RDS_HOST`.

### 3.3. Cargar los datos de prueba

`Actions → Load test data → Run workflow`

- Tarda ~30s.
- En los logs verás los 5 clientes insertados.

---

## FASE 4: Probar el ciclo completo

### 4.1. Hacer un backup

`Actions → Backup RDS to Azure Blob → Run workflow`

- Tarda ~1-2 min.
- Verifica que aparecen `tfg_app_<timestamp>.sql.gz` y
  `tfg_app_latest.sql.gz` en el listado del Blob.

### 4.2. Lanzar el failover

`Actions → Failover Pilot Light → Run workflow`

- Tarda **~12-15 min** (Azure DB Flexible Server son ~8 min).
- Al final verás en el resumen: `App: http://<VM_IP>`.
- Abre esa URL en el navegador → verás la app web con el badge
  `azure · westeurope · DR` y los datos restaurados desde el dump.

### 4.3. Destruir el pilot light

`Actions → Destroy Pilot Light → Run workflow`

- En el input `confirm`, escribe literalmente: `destroy`.
- Tarda ~5 min.
- Comprobar en el portal de Azure que el RG `tfg-pilot-light-rg` ya no
  existe (el de backups `tfg-multicloud-backup-rg` debe seguir).

---

## FASE 5: Antes de cerrar la sesión del lab

### 5.1. Destruir la RDS de prueba

`Actions → Destroy AWS RDS Test → Run workflow`

- Input `confirm`: `destroy`.
- Tarda ~5 min.

### 5.2. Cerrar el lab en AWS Academy

**End Lab** desde el portal de Academy.

> El bucket de tfstate **se conserva** entre sesiones. No hay que
> recrearlo. Lo único que cambia entre sesiones son las credenciales.

---

## Resumen visual del orden

```
  PRIMERA VEZ:
  ┌─────────────────────────────┐
  │ Fase 0: Repo + Azure SP    │   (local)
  │ Fase 1: Secretos GitHub    │   (web)
  │ Fase 2.1: tfstate bucket   │   (Actions)
  │ Fase 2.2: Azure Blob       │   (Actions)
  │ Fase 2.3: Docker image     │   (Actions)
  └─────────────────────────────┘

  CADA SESIÓN DE LAB:
  ┌─────────────────────────────┐
  │ 3.1: Refrescar 3 secretos  │   (web)
  │ 3.2: Setup RDS             │   (Actions, 5 min)
  │ 3.3: Load data             │   (Actions, 30s)
  │ 4.1: Backup                │   (Actions, 1 min)
  │ 4.2: Failover              │   (Actions, 12 min)
  │ — DEMO —                   │
  │ 4.3: Destroy pilot light   │   (Actions, 5 min)
  │ 5.1: Destroy RDS test      │   (Actions, 5 min)
  │ 5.2: End lab               │   (Academy)
  └─────────────────────────────┘
```

---

## Troubleshooting

| Síntoma | Causa probable | Solución |
|---|---|---|
| `InvalidClientTokenId` | Credenciales Academy caducadas | Reiniciar lab y actualizar 3 secretos |
| `Error acquiring the state lock` | Apply anterior cortado | En la consola: `aws s3 rm s3://$BUCKET/aws-test/terraform.tfstate.tflock` |
| `manifest unknown` al hacer `docker pull` | Imagen GHCR no es pública | Settings del package → Change visibility → Public |
| App da 500 en `/health` | Variables de entorno mal | Revisar logs: `ssh azureuser@VM_IP "sudo docker logs tfg-web"` |
| `Authentication failed` en Azure DB | Password mal o BD no existe | El secreto `DB_PASSWORD` es el mismo para AWS y Azure |
| Failover OK pero sin datos | El dump no se subió antes | Lanzar primero "Backup RDS to Azure Blob" |
| `terraform: Error refreshing state` con bucket vacío | Estado lost | `terraform init -reconfigure` y reaplica |
| `quota exceeded` en Azure | Cuotas de Azure for Students | Solo usar West Europe, no abrir múltiples regiones |

---

## Costes estimados (orientativo)

| Recurso | Coste/h | Coste si lo dejas 24h |
|---|---|---|
| RDS db.t3.micro | ~0.017 USD | ~0.40 USD |
| Azure DB B1s | ~0.032 USD | ~0.77 USD |
| VM B1s | ~0.012 USD | ~0.29 USD |
| Blob Storage | ~0 | ~0.02 USD/mes |
| Bucket S3 (state) | ~0 | <0.01 USD/mes |

**Una sesión completa de demo (~30 min)**: ~0.05 USD AWS + ~0.10 USD Azure.

**No olvidar destruir** los recursos al terminar; un fin de semana
olvidado son ~20 USD en Azure.
