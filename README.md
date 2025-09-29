# servicebus-compras

Escenario de Service Bus para el curso: **AddCompra** (productor) + **ProcesaCompra** (consumidor).

## Flujo
1. **AddCompra** recibe `POST /addcompra` con JSON de una compra.
2. Envía el mensaje a la **cola** `compras` de Azure Service Bus.
3. **ProcesaCompra** consume de la cola, **persiste** en SQLite y reenvía a **topics**:
   - `hombretopic` si `Genero == "hombre"`
   - `mujertopic` si `Genero == "mujer"`

> En Azure, podrás cambiar SQLite por Azure SQL/PosgreSQL y apuntar la cadena de conexión.

## Requisitos
- Azure Service Bus namespace con:
  - Cola: `compras`
  - Topics: `hombretopic`, `mujertopic`
- Variable `SERVICEBUS_CONNECTION_STRING` exportada en tu entorno.

## Levantar con Docker Compose
```bash
export SERVICEBUS_CONNECTION_STRING="Endpoint=sb://<ns>.servicebus.windows.net/;SharedAccessKeyName=<name>;SharedAccessKey=<key>"
export SERVICE_BUS_QUEUE_NAME="compras"   # opcional

docker compose up --build -d
```

- API disponible en `http://localhost:5081/swagger`

## Probar
```bash
curl -X POST http://localhost:5081/addcompra   -H "Content-Type: application/json"   -d '{
        "Nombre": "Carlos",
        "Genero": "hombre",
        "Monto": 123.45
      }'
```
Logs del worker deben mostrar persistencia y reenvío al topic correspondiente.

## Cambiar a BD en Azure (más adelante)
- Reemplaza `UseSqlite(...)` por el proveedor de tu preferencia y su cadena de conexión en `ProcesaCompra/Program.cs`.


## Azure SQL (free offer)
1. Crea un **Azure SQL Server** y una **Base de datos** (General Purpose **Serverless**) con el Bicep incluido:
```bash
cd infra
bash deploy-sql-free.sh
# copia el export que imprime y ejecútalo en tu shell:
export AZURE_SQL_CONNECTION_STRING='Server=tcp:<server>.database.windows.net,1433;Database=comprasdb;User ID=<user>;Password=<password>;Encrypt=true;TrustServerCertificate=false;Connection Timeout=30;'
```
2. Levanta los servicios con Docker Compose (además de las variables de Service Bus):
```bash
export SERVICEBUS_CONNECTION_STRING="Endpoint=..."
export AZURE_SQL_CONNECTION_STRING="Server=tcp:<server>.database.windows.net,1433;Database=comprasdb;User ID=<user>;Password=<password>;Encrypt=true;TrustServerCertificate=false;Connection Timeout=30;"
docker compose up --build -d
```

> La oferta **Azure SQL Database Free** te da una asignación mensual (p. ej. 100,000 vCore-segundos y 32 GB de almacenamiento por base) que, bien ajustado con *serverless*, es suficiente para pruebas y demos.
