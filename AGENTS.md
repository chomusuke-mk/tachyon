# 🤖 Guía Normativa para Agentes de IA en Tachyon

¡Bienvenido! Eres un agente de inteligencia artificial (IA) o asistente de código colaborando en el proyecto **Tachyon**. Esta guía contiene las instrucciones normativas, convenciones de arquitectura, reglas de código, diseño de características y restricciones críticas del proyecto para que trabajes con máxima precisión, seguridad y coherencia.

---

## 🛑 REGLA DE ORO: PROHIBICIÓN ABSOLUTA DE COMANDOS GIT

> [!CAUTION]
> **ESTÁ TOTALMENTE PROHIBIDO EJECUTAR COMANDOS DE GIT PARA AGREGAR (`git add`), HACER COMMIT (`git commit`), PUSH (`git push`), PULL (`git pull`), REBASE, MERGE O CUALQUIER OTRA MUTACIÓN DEL REPOSITORIO ACTUAL.**

- El control de versiones, el área de staging (`git add`), la creación de commits (`git commit`), la sincronización remota (`git push`, `git pull`), el cambio de ramas y la resolución de conflictos son **responsabilidad y potestad exclusiva del usuario humano**.
- Los agentes de IA **NUNCA** deben ejecutar comandos que modifiquen el historial, el índice de git o el estado del repositorio remoto o local (`git add`, `git commit`, `git push`, `git pull`, `git checkout`, `git reset`, `git rebase`, `git merge`, `git cherry-pick`, `git stash`, etc.).
- Comandos de solo lectura como `git status` o `git diff` para inspeccionar cambios de trabajo están permitidos únicamente cuando sea estrictamente necesario para diagnosticar el código.

---

## 🎯 Objetivo General del Proyecto

**Tachyon** es un reproductor de música moderno, refinado, multiplataforma (Linux, Windows, macOS, Android, iOS) y 100% libre desarrollado en **Flutter (Dart)**. Su propósito es brindar una experiencia de reproducción de audio fluida, estética (Material 3 con esquema de color dinámico y modo OLED), con soporte nativo de crossfade continuo de 25 ms, biblioteca musical local ultrarrápida, y visualización sincronizada de letras con respaldo inteligente en APIs remotas.

---

## 🏛️ Arquitectura Desacoplada: UI Isolate vs Backend Host Isolate

El proyecto Tachyon opera bajo un desacoplamiento estricto entre el hilo visual y la capa de servicios de fondo:

```raw
┌──────────────────────────────────────────────────────────┐
│                   MAIN ISOLATE (UI)                      │
│  - Widgets Material 3, Temas, Animaciones                │
│  - Controladores ChangeNotifier (Library, Playback, etc) │
│  - CERO SQLite directa, CERO reproductores de audio      │
│  - CERO extracción/procesamiento de imágenes             │
└──────────────────────────┬───────────────────────────────┘
                           │  TachyonBackendClient
                           │  (SendPort / ReceivePort / DirectClient)
                           ▼
┌──────────────────────────────────────────────────────────┐
│              CORE BACKEND HOST (ISOLATE)                 │
│  - CoreBackendHost (Despacho de comandos y eventos)      │
│  - AppDatabase (SQLite único con sqflite / sqlite3 FFI)  │
│  - AudioEngineService (Crossfade dual con miniaudio)     │
│  - MetadataService (Orquestación Isolate.run / spawn)   │
│  - CoverCacheService (Extracción embebida y caché HQ/LQ) │
│  - QueueManager (Cola, shuffle Fisher-Yates, loop)       │
│  - LyricsService (Resolución jerárquica y caché origen)  │
└──────────────────────────────────────────────────────────┘
```

### 1. Main Isolate (Hilo Principal de UI)

- **Exclusivamente visual y reactivo:** Solo se encarga de renderizar la interfaz de usuario, escuchar cambios de estado y capturar la interacción del usuario.
- **Restricciones estrictas en el Main Isolate:**
  - **Cero acceso a Base de Datos:** No instancia ni consulta `AppDatabase` directamente.
  - **Cero reproductores de audio directos:** No maneja instancias de reproductores ni FFI de audio.
  - **Cero procesamiento de imágenes/metadatos:** No decodifica imágenes con `package:image` ni extrae tags ID3.
  - **Cero bloqueo (0 jank):** Mantiene una tasa estable de 60/120 fps sin jank.
- **Comunicación con el Backend:** Se realiza exclusivamente a través de la abstracción `TachyonBackendClient` (con `DirectTachyonBackendClient` para pruebas unitarias y cliente basado en puertos para el runtime).

### 2. Core Backend Host (Isolate de Servicios)

- Corre en un isolate dedicado, centralizando toda la lógica de negocio pesada:
  1. **Persistencia SQLite Centralizada (`AppDatabase`):** Todas las lecturas y escrituras relacionales se ejecutan exclusivamente en este isolate, garantizando concurrencia segura y eliminando bloqueos (`database is locked`).
  2. **Motor de Audio de Bajo Nivel (`AudioEngineService`):** Orquesta dos reproductores de audio (`miniaudio_player` con FFI nativo) mediante un ticker de 25 ms para crossfade real y fluido con curvas Equal-Power o Linear.
  3. **Servicio Unificado de Metadatos (`MetadataService`):**
     - Orquesta la extracción de metadatos de archivos únicos y generación de miniaturas usando `Isolate.run`.
     - Orquesta escaneos masivos recursivos de carpetas mediante `scan_isolate.dart` con `Isolate.spawn`.
     - **Regla de transferencia liviana:** Tanto el backend isolate como el main isolate **solo transmiten rutas en disco (`String`)**, **NUNCA** arreglos masivos de bytes crudos (`Uint8List`).
  4. **Gestión de Carátulas (`CoverCacheService`):**
     - Extrae preferentemente imágenes embebidas en los tags del archivo de audio mediante `audio_metadata_reader`.
     - **Respaldo en Directorio (Fallback):** Si el archivo no contiene carátula embebida, busca carátulas locales contiguas en su directorio (`cover.jpg`, `folder.jpg`, `front.jpg`, etc.) o de artista (`artist.jpg`, `band.jpg`, etc.).
     - Caché dual con hash SHA-256 en disco:
       - **HQ (High Quality):** Máximo 500x500 píxeles con recorte central cuadrado sin distorsión.
       - **LQ (Low Quality):** Exactamente 80x80 píxeles con recorte central cuadrado sin distorsión.
  5. **Gestor de Cola (`QueueManager`):** Mantiene el historial, pista actual, cola de reproducción, modo shuffle (Fisher-Yates) y modos de repetición.
  6. **Servicio de Letras (`LyricsService`):** Resolución de letras jerárquica con caché persistente y rate limiting.

---

## 🎵 Subsistema de Letras (Lyrics Subsystem)

El sistema de letras de Tachyon está diseñado bajo una arquitectura jerárquica con caché persistente y manejo defensivo de APIs remotas:

### 1. Jerarquía Estricta de Búsqueda

1. **Letras embebidas:** Tags de audio (USLT, LYRICS) extraídas por `audio_metadata_reader`.
2. **Archivo local `.lrc`:** Archivos `.lrc` o `.LRC` contiguos a la pista en su directorio (`<nombre_archivo>.lrc`).
3. **API Primaria (`lrclib.net`):** Letras sincronizadas y en texto plano vía `GET /api/get` (con título, artista, álbum y duración con margen $\pm 2$ s).
4. **API Secundaria / Respaldo (`lyrics.ovh`):** Letras en texto plano sin marcas de tiempo vía `GET https://api.lyrics.ovh/v1/{artist}/{title}`.

### 2. Disparador Exclusivo Bajo Demanda

- La búsqueda y consulta de letras a las fuentes **está delegada al ciclo de vida de renderizado del widget `LyricsView`** (cuando se monta en pantalla porque el usuario activó `_showLyrics == true` en `NowPlayingScreen`).
- `LyricsController` **no** debe buscar letras de forma automática ni anticipada en segundo plano simplemente porque una canción empiece a reproducirse en la vista estándar de reproducción (_Play View_ con carátula y controles, `_showLyrics == false`).
- Al montarse o estar visible `LyricsView`, este solicita la carga de letras para la pista activa. Si la canción cambia mientras `LyricsView` permanece en pantalla, este mismo solicita la letra de la nueva canción.

### 3. Persistencia con Estado por Origen en SQLite

En la tabla `lyrics_source_cache` se registra el resultado individual por cada fuente (`embedded`, `lrc_file`, `lrclib`, `lyrics_ovh`):

- `FOUND`: Letra encontrada y guardada.
- `NOT_FOUND`: La fuente confirmó que la letra no existe (ej. HTTP 404 en `lrclib.net`). Se guarda para no volver a solicitar esa canción a ese servicio.
- `TEMPORARY_ERROR`: Si la petición falló por error de red, respuesta 5xx o rate limit (HTTP 429), **no** se marca como `NOT_FOUND`, permitiendo reintentos futuros.

### 4. Rate Limiting, Umbrales y Control de Concurrencia

- **lrclib.net:** Intervalo mínimo de 500 ms entre peticiones consecutivas e identificación de cliente mediante cabecera `User-Agent`.
- **Manejo de HTTP 429 (`Retry-After`):**
  - Si el tiempo de espera es $\le 10$ segundos: Mostrar banner o mensaje en pantalla con cuenta regresiva en vivo y reintentar automáticamente al completarse el tiempo.
  - Si el tiempo de espera es $> 10$ segundos (ej. cooldown de 3 minutos): Recurrir de inmediato al servicio de respaldo (`lyrics.ovh`) para mostrar texto plano.
- **Cooldown en memoria:** Si el cooldown expira mientras el usuario sigue en la misma canción, re-consultar `lrclib.net` y actualizar la visualización a letras sincronizadas. Si el usuario cambió de canción durante el bloqueo, omitir `lrclib.net`, consultar el respaldo y reintentar `lrclib.net` para la canción activa al vencer el tiempo.
- **Salto rápido en cola:** Si el usuario adelanta varias canciones seguidas (ej. 1 → 2 → 3 → 4 → 5), descartar inmediatamente las peticiones intermedias (2, 3, 4) y procesar directamente la canción 5.

---

## 🛠️ Flujo de Creación de Características (Feature Workflow)

Al implementar una nueva funcionalidad o modificar una existente, respeta el siguiente flujo arquitectónico por capas:

### 1. Capa de Datos (SQLite)

- Si la funcionalidad requiere persistencia relacional, modifica `AppDatabase` (`lib/core/database/app_database.dart`).
- Agrega las consultas correspondientes y migraciones de esquema seguras.

### 2. Capa de Servicios Backend

- Ubica la lógica en `lib/core/backend/services/`.
- No mezcles lógica de UI ni imports de Flutter visual en esta capa.

### 3. Protocolo de Comunicación

- Define los mensajes/comandos en `backend_protocol.dart`.
- Agrega el handler correspondiente en `CoreBackendHost` (`backend_host.dart`).
- Expón el método correspondiente en `TachyonBackendClient` (`backend_client.dart`) e impleméntalo en `DirectTachyonBackendClient` (`direct_backend_client.dart`) para tests.

### 4. Capa de Presentación (UI y Controladores)

- **Invariante Crítica:** **NO alteres arbitrariamente los constructores de los controladores existentes** en `lib/features/*/presentation/` para evitar romper la inyección de dependencias en `main.dart` o en las pruebas.
- Los controladores extienden de `ChangeNotifier` y consumen `TachyonBackendClient`.
- Flujo unidireccional: la UI observa el estado mediante `context.watch<T>()` o `Selector`, y despacha acciones mediante `context.read<T>()`.
- Los métodos `build()` de los widgets deben ser funciones puras de renderizado: cero llamadas a disco o red en `build()`.

---

## 🌐 Internacionalización Obligatoria (i18n)

> [!IMPORTANT]
> **REGLA ESTRICTA: CERO cadenas de texto hardcodeadas (_zero hardcoded strings_) en widgets, pantallas, diálogos, tooltips o mensajes de error visibles.**

Todo texto visible en la aplicación debe estar internacionalizado siguiendo este procedimiento de 4 pasos:

1. **Añadir la clave y traducción** en `i18n/en.jsonc` (inglés) e `i18n/es.jsonc` (español).
2. **Añadir el getter fuertemente tipado** en `AppStringKey` (`lib/features/locales/domain/locale.dart`).
3. **Registrar la clave** en la lista estática `_allAppStrings` dentro de `AppStringKey`.
4. **Consumir en la UI** mediante:

   ```dart
   context.watch<LocaleController>().localeStrings.<nombreDelGetter>
   ```

- El test estático `test/ast_i18n_test.dart` audita el árbol de widgets para verificar que no existan cadenas literales sin traducir.

---

## ⚡ Rendimiento, Plataformas y Cero Subprocesos CLI

1. **Cero Binarios Nativos Externos:**
   - **PROHIBIDO** invocar herramientas de línea de comandos externas como `ffmpeg` o `ffprobe` vía `Process.run`.
   - La lectura y procesamiento de metadatos se realiza 100% en Dart (`audio_metadata_reader`).
   - La reproducción de audio de bajo nivel se realiza vía `miniaudio_player` embebido vía FFI.

2. **Multiplataforma Nativa:**
   - Soporte para Linux, Windows, macOS, Android e iOS.
   - El código debe ser agnóstico del sistema operativo, utilizando rutas normalizadas con `package:path` y adaptadores FFI cuando sea necesario.

3. **Optimización de Memoria y RAM:**
   - No mantener búferes de imágenes decodificadas en memoria sin límite.
   - Usar miniaturas LQ (80x80) para listas y grillas de álbumes/canciones.
   - Usar miniaturas HQ (500x500) únicamente para la vista activa de reproducción (_Now Playing_).

---

## 🚀 Flujo y Comandos Clave Permitidos (CLI)

- **Instalar dependencias:**

  ```bash
  flutter pub get
  ```

- **Ejecutar análisis estático (debe mantenerse con 0 errores y 0 warnings en todo momento):**

  ```bash
  dart analyze .
  ```

- **Ejecutar suite de pruebas:**

  ```bash
  flutter test
  ```

- **Ejecutar aplicación en modo desarrollo:**

  ```bash
  flutter run -d linux   # o -d windows, -d android
  ```

---

## 📋 Resumen de Reglas de Comportamiento para Agentes

1. **PROHIBICIÓN TOTAL DE GIT:** Nunca ejecutes `git add`, `git commit`, `git push`, `git pull` ni alteres el repositorio o ramas.
2. **GESTIÓN DE CARÁTULAS:** En `CoverCacheService`, prioriza imágenes embebidas en los tags de audio y utiliza carátulas locales de directorio (`cover.jpg`, `folder.jpg`, etc.) como fallback sin invocar subprocesos CLI.
3. **RESPETAR DESACOPLAMIENTO DE ISOLATES:** La UI solo interactúa con el backend a través de `TachyonBackendClient`. No instancies `AppDatabase` ni players en la UI.
4. **TRANSMISIÓN DE RUTAS, NO BYTES:** Los isolates se comunican con rutas de archivos en disco (`String`), nunca con bytes (`Uint8List`).
5. **VERIFICACIÓN ESTÁTICA Y TESTS:** Tras cualquier modificación, corre siempre `dart analyze .` (0 errores, 0 warnings) y valida con `flutter test`.
6. **NO ROMPER I18N:** Nunca introduzcas cadenas de texto en crudo en la interfaz. Registra siempre las claves en `en.jsonc`, `es.jsonc` y `AppStringKey`.
7. **INVARIANTE DE CONSTRUCTORES:** No modifiques las firmas de constructor de los controladores de UI en `lib/`.
