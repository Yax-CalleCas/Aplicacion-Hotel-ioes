# Hotel PMS — Aplicación iOS (iPhone 13)

App nativa en **SwiftUI** que consume la API del backend hotelero
(Spring Boot, `:8082`).

---

## 1. Requisitos

| Herramienta | Versión |
|---|---|
| macOS | 14+ |
| Xcode | 15+ |
| iOS | 17+ (iPhone 13 compatible) |
| XcodeGen | `brew install xcodegen` |

---

## 2. Arranque

### Backend

```bash
cd ../../                     # hotel/
docker compose up -d          # o PostgreSQL local
./mvnw spring-boot:run        # http://localhost:8082
```

### Fotos del catálogo

Las imágenes las sirve el **frontend web** (`frontend/public/img/`):

```bash
cd ../frontend
npm start                     # http://localhost:4200
```

Si no está corriendo, la app muestra un ícono en lugar de la foto
(no rompe nada).

### iOS

```bash
cd ios-hotel
xcodegen generate
open HotelApp.xcodeproj
# Cmd+R con iPhone 13
```

**Simulador:** `localhost` funciona directo.
**iPhone físico:** cambia en `Info.plist`:

- `API_BASE_URL` → `http://<IP-del-Mac>:8082/api`
- `WEB_BASE_URL` → `http://<IP-del-Mac>:4200`

Y arranca Spring con `server.address=0.0.0.0`.

---

## 3. Usuarios demo

Contraseña: **`Hotel2026`**

| Email | Rol | Ve |
|---|---|---|
| `admin@hotel.com` | ADMIN | Todo: operación, reportes, usuarios y sedes |
| `gerente@hotel.com` | GERENTE | Operación y reportes |
| `recepcion@hotel.com` | RECEPCIONISTA | Operación de su sede |
| `limpieza@hotel.com` | HOUSEKEEPING | Sus tareas |
| `cliente@hotel.com` | CLIENTE | Reservas propias |

La app detecta el rol y muestra la pestaña adecuada automáticamente.

---

## 4. Arquitectura

```
HotelApp/
├── App/
│   └── HotelApp.swift          @main + TabViews por rol
├── Core/
│   ├── Config/                 AppConfig (API + imágenes)
│   ├── Models/                 DTOs espejo del backend
│   ├── Networking/             APIClient (actor) + APIError
│   ├── Persistence/            Core Data (reservas offline)
│   ├── Security/               Keychain + Face ID
│   ├── Notifications/          UserNotifications
│   ├── Services/               HotelAPI + stores
│   └── Session/                SesionStore
├── Features/
│   ├── Auth/                   Login (con bloqueo + Face ID), Registro
│   ├── Cliente/                Búsqueda con fotos, reservas, depósito
│   └── Operacion/              Home, habitaciones, tareas, pagos,
│                               reportes, usuarios, sedes, perfil
└── UI/                         Tema, ImagenRemota
```

**Patrón:** MVVM con `@Observable` (iOS 17). Stores `@MainActor`.
**Concurrencia:** `async/await`, `actor APIClient`.

---

## 5. Herramientas nativas iOS

| # | Herramienta | Framework | Uso |
|---|---|---|---|
| 1 | **Keychain** | `Security` | JWT seguro, nunca en UserDefaults |
| 2 | **Face ID** | `LocalAuthentication` | Entrada rápida y cambio de contraseña |
| 3 | **Core Data** | `CoreData` | Reservas consultables sin red |
| 4 | **Notificaciones** | `UserNotifications` | Aviso de expiración y cambios de estado |

---

## 6. Pantallas

### Cliente

| Pantalla | Qué hace |
|---|---|
| **Reservar** | Sedes con foto, fechas, ocupantes y catálogo visual de habitaciones |
| **Mis reservas** | Lista offline + búsqueda por código |
| **Detalle** | Folio con cargos y pagos, depósito del 50 %, cancelar |
| **Avisos** | Bandeja de notificaciones con marca de leída |
| **Perfil** | Datos, cambio de contraseña con Face ID, cerrar sesión |

### Operación (recepción / gerencia / admin)

| Pantalla | Qué hace |
|---|---|
| **Operación** | KPIs, llegadas/salidas, pagos por verificar, accesos rápidos |
| **Habitaciones** | Tablero por estado, detalle con foto, cambiar estado |
| **Tareas** | Housekeeping: iniciar → completar → verificar |
| **Pagos** | Aprobar o rechazar pagos pendientes |
| **Reportes** | KPIs, ocupación diaria e ingresos (ADMIN/GERENTE) |
| **Usuarios** | Crear, activar/desactivar, resetear, desbloquear (ADMIN) |
| **Sedes** | Editar datos y foto de cada sede (ADMIN) |
| **Perfil** | Datos, seguridad, accesos de admin, cerrar sesión |

---

## 7. Flujos

### Cliente

```
Buscar disponibilidad → elegir categoría (con foto) → confirmar reserva
    → PENDIENTE (expira en 30 min)
    → pagar depósito 50 %
    → recepción aprueba
    → CONFIRMADA
```

- La búsqueda consulta el backend en vivo.
- Las reservas se cachean en Core Data.
- Nunca se inventa un estado: se refleja lo que devuelve el servidor.
- La `idempotencyKey` se deriva del id de la reserva (reintentar no duplica).

### Recepción

```
Home: KPIs + llegadas + salidas + pagos pendientes
Habitaciones: tablero por estado (disponible/ocupada/limpieza/...)
Detalle reserva: check-in (valida depósito), check-out (valida saldo)
```

### Housekeeping

```
Tareas pendientes → iniciar → completar → [supervisor verifica]
```

Solo al verificar la tarea la habitación pasa a DISPONIBLE.

---

## 8. Endpoints consumidos

Cobertura completa del backend (**74 endpoints**).

| Dominio | Endpoints |
|---|---|
| **Auth** | `login`, `register`, `me`, `cambiar-password`, `logout` |
| **Catálogo** | `sedes`, `categorias`, `disponibilidad` |
| **Reservas** | `mias`, `reservas`, `reservas/{id}`, `codigo/{codigo}`, crear, cancelar |
| **Folio** | `folio`, `cargos`, `cargos/{id}/anular` |
| **Pagos** | registrar, `pendientes`, `aprobar`, `rechazar` |
| **Estadía** | `check-in`, `check-out`, `estadias/activas` |
| **Inventario** | `habitaciones` (listar/crear/editar/estado/historial), `pisos` CRUD, `categorias` CRUD, `temporadas`, `tarifas` |
| **Housekeeping** | `tareas`, `tareas/todas`, crear, actualizar (PATCH), `incidencias` |
| **Notificaciones** | listar, `no-leidas`, marcar leída |
| **Reportes** | `dashboard`, `kpis`, `ocupacion`, `ingresos/categoria`, `ingresos/concepto` |
| **Admin** | usuarios CRUD + estado + reset + bloqueo + desbloquear, roles CRUD, permisos, sedes CRUD |

---

## 9. Correcciones aplicadas

| Bug | Antes | Ahora |
|---|---|---|
| **PATCH sin body** | `actualizarTarea` enviaba PATCH vacío → **400 siempre** | `APIClient.patch(path, body:)` con `ActualizarTareaRequest` |
| **Faltaban verbos HTTP** | No existían `put` ni `delete` | Implementados en el actor |
| **Fachada de error** | `APIError` no coincidía con `ErrorResponse` | Mismos campos + `fieldErrors` + `mensajeUsuario` |
| **Fechas corridas** | `yyyy-MM-dd` se parseaba en UTC → día anterior en Perú | Parser anclado a `America/Lima` |
| **Sede no seleccionable** | La búsqueda usaba siempre la primera sede | `CatalogoStore.sedeId` con selector visual |
| **Sin fotos** | Solo íconos | `ImagenRemota` con `AsyncImage` y respaldo |
| **`Decimal` en pago** | Idempotencia por timestamp (duplicaba si reintentabas en otro segundo) | Clave estable por reserva y tipo |
| **Pago "confirmado"** | La UI decía confirmado al registrar (queda PENDIENTE) | Aviso explícito de verificación |
| **Check-out** | Sin observaciones | Envía `CheckOutRequest(observaciones, cerrarFolio)` |
| **Modelo duplicado** | `ModeloProgramatico.swift` del proyecto de agricultura rompía el build | Archivo eliminado |
| **Notificaciones** | Métodos nunca invocados | Programadas al reservar, canceladas al pagar/cancelar |
| **Face ID** | Solo definido | Botón de entrada y protección del cambio de contraseña |

---

## 10. Validación

```bash
node tools/verificar-sintaxis.js
```

```
31 archivos Swift, 0 con problemas.
```

Comprueba balance de símbolos, imports y ausencia de placeholders.
**No sustituye a `swiftc`** — la compilación real requiere macOS:

```bash
xcodebuild -scheme HotelApp -destination 'platform=iOS Simulator,name=iPhone 13' build
```

---

## 11. Limitaciones conocidas

| Limitación | Impacto |
|---|---|
| No compilado en Xcode | Puede haber errores de tipos finos |
| Sin App Icon | Xcode mostrará warning |
| Push remoto (APNs) | Solo notificaciones locales |
| Fotos requieren el frontend | Sin el 4200 activo se muestra el ícono |
