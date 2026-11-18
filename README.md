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

El `HotelApp.xcodeproj` **está versionado en el repositorio**: basta con clonar
y abrir. No hace falta instalar nada.

```bash
git clone <repo>
cd ios-hotel
open HotelApp.xcodeproj
```

### Si añades, renombras o borras archivos

`project.yml` es la fuente de verdad del proyecto. Tras cualquier cambio en la
estructura de carpetas hay que regenerar y commitear el `.xcodeproj`:

```bash
xcodegen generate
git add HotelApp.xcodeproj project.yml
git commit -m "Regenera proyecto"
```

XcodeGen se instala sin permisos de administrador (sin Homebrew):

```bash
mkdir -p ~/bin && cd /tmp
curl -L -o xcodegen.zip https://github.com/yonaskolb/XcodeGen/releases/latest/download/xcodegen.zip
unzip -o xcodegen.zip -d ~/bin
chmod +x ~/bin/xcodegen/bin/xcodegen
xattr -d com.apple.quarantine ~/bin/xcodegen/bin/xcodegen 2>/dev/null
echo 'export PATH="$HOME/bin/xcodegen/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
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
