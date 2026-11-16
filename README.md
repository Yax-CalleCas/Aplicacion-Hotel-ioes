# HotelApp iOS

App nativa del PMS hotelero. Consume la API de **Render**:
`https://hotel-pms-api-1som.onrender.com/api`

## Stack

- SwiftUI + Observation
- `@MainActor` stores, `async/await`
- Core Data (modelo programático, sin `.xcdatamodeld`)
- Keychain (JWT), Face ID, AVFoundation (escáner QR)
- XcodeGen (`project.yml`), iOS 17+

## Arranque en Mac

```bash
# 1) Instalar XcodeGen (una sola vez)
brew install xcodegen

# 2) Generar el proyecto Xcode
xcodegen generate

# 3) Abrir en Xcode
open HotelApp.xcodeproj
```

## Configuración

La URL del backend ya viene en `HotelApp/Info.plist`:

- `API_BASE_URL` → `https://hotel-pms-api-1som.onrender.com/api`
- `WEB_BASE_URL` → `https://hotel-pms-api-1som.onrender.com`

Para login social (Facebook) reemplaza `PON_AQUI_TU_APP_ID` y
`PON_AQUI_TU_CLIENT_TOKEN` en `HotelApp/Info.plist`.

## Firma de código

En Xcode, `Signing & Capabilities`:

- **Simulador**: desmarca *Automatically manage signing* (o configura tu Apple ID).
- **Dispositivo físico**: marca *Automatically manage signing* con tu Apple ID/Team.

## Usuarios demo (contraseña: `Hotel2026`)

| Email | Rol |
|---|---|
| admin@hotel.com | ADMIN |
| gerente@hotel.com | GERENTE |
| recepcion@hotel.com | RECEPCIONISTA |
| limpieza@hotel.com | HOUSEKEEPING |
| cliente@hotel.com | CLIENTE |

## Flujo de trabajo (OpenCode ↔ Mac)

1. Editar código aquí en OpenCode (Windows).
2. `git add . && git commit && git push` desde OpenCode.
3. En la Mac: `git pull` y abrir con Xcode para compilar/probar.
