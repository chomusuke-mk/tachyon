# 🤖 Guía para Agentes de IA en Tachyon

¡Bienvenido! Eres un agente de inteligencia artificial (IA) o asistente de código colaborando en el proyecto **Tachyon**. Esta guía contiene las instrucciones normativas, convenciones de arquitectura, reglas de código y flujos del proyecto para que puedas trabajar con máxima precisión y coherencia.

---

## 🎯 Objetivo General del Proyecto

**Tachyon** es un reproductor de música moderno, refinado, multiplataforma (Linux, Windows, macOS, Android, iOS) y 100% libre desarrollado en **Flutter (Dart)**. Su propósito es brindar una experiencia de reproducción de audio fluida, estética (Material 3 con esquema de color dinámico y modo OLED), con soporte nativo de crossfade continuo, biblioteca musical local ultrarrápida, y visualización sincronizada de letras con respaldo inteligente en APIs remotas.

---

## 🏛️ Principios Críticos de Arquitectura

El proyecto fue refactorizado para eliminar dependencias de herramientas externas nativas del sistema operativo (`ffmpeg`, `ffprobe` por CLI). La arquitectura se basa en las siguientes decisiones fundamentales:

1. **Extracción de Metadatos 100% en Dart e Isolate:**
   - La lectura de etiquetas ID3/FLAC/Vorbis y metadatos se realiza mediante el paquete Dart `audio_metadata_reader`.
   - El escaneo recursivo de directorios y la lectura de metadatos se ejecutan en un **Isolate secundario** (`lib/core/services/scan_isolate.dart`), comunicándose por mensajes con `MetadataExtractor`.
   - **Cero bloqueos de UI (0 jank):** Todo el trabajo pesado de disco y parseo ocurre fuera del hilo principal.
   - **Escrituras seguras en SQLite:** Solo el isolate principal realiza inserciones en la base de datos (`AppDatabase`) para evitar errores de bloqueo (`database is locked`).

2. **Caché de Carátulas (Cover Art):**
   - Las imágenes embebidas extraídas por `audio_metadata_reader` o las carátulas locales (`cover.jpg`, `folder.jpg`, `front.jpg`) son escritas directamente a disco mediante `CoverCacheService` sin invocar ningún subproceso.

3. **Motor de Reproducción y Crossfade Continuo:**
   - Construido sobre `just_audio` respaldado por `just_audio_media_kit` (`JustAudioMediaKit.ensureInitialized` en plataformas de escritorio).
   - Coordinación de dos reproductores (`Player A` y `Player B`) en `AudioEngineService` para ejecutar crossfade real mediante un ticker periódico de 25 ms con curvas Equal-Power o Linear.

4. **Persistencia Local Relacional:**
   - Base de datos SQLite gestionada con `sqflite` (y `sqflite_common_ffi` con `sqlite3` en escritorio).
   - Tablas normalizadas: `tracks`, `albums`, `artists`, `genres`, `playlists`, `playlist_tracks`, `lyrics_cache`.

5. **Internacionalización Obligatoria (i18n):**
   - Todos los textos de la interfaz deben estar localizados en `i18n/en.jsonc` y `i18n/es.jsonc`, y expuestos a través de getters fuertemente tipados en `AppStringKey` (`lib/features/locales/domain/locale.dart`).
   - **Regla estricta:** CERO cadenas de texto hardcodeadas (*zero hardcoded strings*) en widgets o diálogos.

---

## 🎵 Subsistema de Letras (Lyrics Subsystem)

El sistema de letras de Tachyon está diseñado bajo una arquitectura jerárquica con caché persistente y manejo defensivo de APIs remotas:

### 1. Jerarquía Estricta de Búsqueda
1. **Letras embebidas:** Tags de audio (USLT, LYRICS) extraídas por `audio_metadata_reader`.
2. **Archivo local `.lrc`:** Archivos `.lrc` o `.LRC` contiguos a la pista en su directorio (`<nombre_archivo>.lrc`).
3. **API Primaria (`lrclib.net`):** Letras sincronizadas y en texto plano vía `GET /api/get` (con título, artista, álbum y duración con margen $\pm 2$ s).
4. **API Secundaria / Respaldo (`lyrics.ovh`):** Letras en texto plano sin marcas de tiempo vía `GET https://api.lyrics.ovh/v1/{artist}/{title}`.

### 2. Disparador de Consultas
- La búsqueda y consulta de letras a las fuentes (especialmente APIs remotas) **está delegada al ciclo de vida de renderizado del widget `LyricsView`** (cuando se monta en pantalla porque el usuario activó `_showLyrics == true` en `NowPlayingScreen`).
- `LyricsController` **no** debe buscar letras de forma automática ni anticipada en segundo plano simplemente porque una canción empiece a reproducirse en la vista estándar de reproducción (*Play View* con carátula y controles, `_showLyrics == false`).
- Al montarse o estar visible `LyricsView`, este solicita la carga de letras para la pista activa. Si la canción cambia mientras `LyricsView` permanece en pantalla, este mismo solicita la letra de la nueva canción.

### 3. Persistencia con Estado por Origen en SQLite
En la tabla de caché de letras de la base de datos se debe registrar el resultado individual por cada fuente (`embedded`, `lrc_file`, `lrclib`, `lyrics_ovh`):
- `FOUND`: Letra encontrada y guardada.
- `NOT_FOUND`: La fuente confirmó que la letra no existe (ej. HTTP 404 en `lrclib.net`). Se guarda para no volver a solicitar esa canción a ese servicio.
- `TEMPORARY_ERROR`: Si la petición falló por error de red, respuesta 5xx o rate limit (HTTP 429), **no** se marca como `NOT_FOUND`, permitiendo reintentos futuros.

### 4. Rate Limiting, Umbrales y Control de Concurrencia
- **lrclib.net:** Intervalo mínimo de 500 ms entre peticiones consecutivas e identificación de cliente mediante cabecera `User-Agent`.
- **Manejo de HTTP 429 (`Retry-After`):**
  - Si el tiempo de espera es $\le 10$ segundos: Mostrar banner o mensaje en pantalla ("Threshold de lrclib.net detectado esperando X segundos...") con cuenta regresiva en vivo y reintentar automáticamente al completarse el tiempo.
  - Si el tiempo de espera es $> 10$ segundos (ej. cooldown de 3 minutos): Recurrir de inmediato al servicio de respaldo (`lyrics.ovh`) para mostrar texto plano.
- **Cooldown en memoria:** Si el cooldown expira mientras el usuario sigue en la misma canción, re-consultar `lrclib.net` y actualizar la visualización a letras sincronizadas. Si el usuario cambió de canción durante el bloqueo, omitir `lrclib.net`, consultar el respaldo y reintentar `lrclib.net` para la canción activa al vencer el tiempo.
- **Salto rápido en cola:** Si el usuario adelanta varias canciones seguidas (ej. 1 → 2 → 3 → 4 → 5), descartar inmediatamente las peticiones intermedias (2, 3, 4) y procesar directamente la canción 5.

### 5. Controles de UI en la Pantalla de Letras
La barra superior de la vista de letras cuenta con 3 controles:
1. **Botón de traducción:** Traducir las letras a través de un endpoint público gratuito sin credenciales.
2. **Configuración de fuentes:** Diálogo flotante con switches individuales para prender/apagar:
   - Archivos locales (embebido y `.lrc`).
   - Servidor 1 (`lrclib.net`).
   - Servidor 2 (`lyrics.ovh`).
   Y un botón para re-buscar con la selección actual.
3. **Botón de re-búsqueda ("Volver a buscar"):** Fuerza una nueva consulta en las fuentes activas ignorando estados temporales.

---

## 📂 Estructura de Directorios

```
lib/
├── app.dart                                # MaterialApp entry (tema, rutas, soporte de localización)
├── main.dart                               # Inicialización de servicios y MultiProvider
├── core/
│   ├── constants/
│   │   └── app_defaults.dart              # Constantes de audio, volumen y tiempos
│   ├── database/
│   │   └── app_database.dart              # Esquema SQLite, migraciones, consultas y caché de letras
│   ├── services/
│   │   ├── audio_engine_service.dart      # Orquestador de crossfade dual (Player A & Player B)
│   │   ├── audio_player_adapter.dart      # Adaptador de just_audio / just_audio_media_kit
│   │   ├── audio_session_manager.dart     # Manejo de foco de audio e interrupciones
│   │   ├── cover_cache_service.dart       # Extracción y almacenamiento en disco de carátulas
│   │   ├── lrc_parser.dart                # Parseo de LRC y SplayTreeMap O(log n)
│   │   ├── lyrics_service.dart            # Servicio de resolución de letras multiorigen
│   │   ├── metadata_extractor.dart        # Puente entre el isolate de escaneo y el isolate principal
│   │   ├── queue_manager.dart             # Lógica de cola, shuffle Fisher-Yates y loop
│   │   └── scan_isolate.dart              # Isolate de escaneo en segundo plano con audio_metadata_reader
├── features/
│   ├── library/                           # Gestión y vistas de biblioteca (Tracks, Albums, Artists, Folders)
│   ├── locales/                           # Sistema tipado de i18n JSONC (AppStringKey)
│   ├── playback/                          # Now Playing, controles de transporte, lyrics_view y efectos
│   ├── playlists/                         # CRUD y reordenamiento de listas de reproducción
│   ├── search/                            # Búsqueda global en tiempo real
│   ├── settings/                          # Pantalla y repositorio de configuración SharedPreferences
│   └── shell/                             # Shell adaptativo (Desktop NavigationRail vs Mobile NavigationBar)
└── shared/
    ├── theme/                             # Sistema Material 3 con 5 niveles de superficie
    └── widgets/                           # Componentes reutilizables (AlbumArtImage, SettingRow, TrackTile)
```

---

## 🛠️ Estándares y Convenciones de Código

### 1. Gestión de Estado (`Provider`)
- Se utiliza el paquete `provider` con clases `ChangeNotifier`.
- Respetar el flujo unidireccional: la UI escucha cambios con `context.watch<T>()` o `Selector`, y despacha eventos con `context.read<T>()`.
- No colocar lógica de negocio compleja ni llamadas directas de red/disco dentro de los métodos `build()` de los widgets.

### 2. Internacionalización (i18n)
- Archivos fuente: `i18n/en.jsonc` e `i18n/es.jsonc`.
- Clase de acceso: `AppStringKey` en `lib/features/locales/domain/locale.dart`.
- Al agregar cualquier texto nuevo a la UI:
  1. Agrega la clave y traducción en `i18n/en.jsonc` e `i18n/es.jsonc`.
  2. Añade el getter tipado en `AppStringKey`.
  3. Registra la clave en la lista interna `_allAppStrings`.
  4. Úsalo en la UI como `context.watch<LocaleController>().localeStrings.<clave>`.

### 3. Rendimiento y Operaciones Asíncronas
- **Nunca** ejecutes tareas intensivas de lectura de archivos o decodificación masiva en el hilo principal de la UI. Emplea `Isolate` o delegados en background.
- Maneja siempre `try / catch` de forma defensiva para peticiones de red o acceso a archivos.
- Evita llamadas duplicadas o innecesarias a la base de datos utilizando la caché en memoria cuando sea apropiado.

---

## 🚀 Flujo y Comandos Clave (CLI)

- **Instalar dependencias:**
  ```bash
  flutter pub get
  ```
- **Ejecutar análisis estático (debe mantenerse con 0 errores y 0 warnings):**
  ```bash
  dart analyze
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

## 🤖 Reglas de Comportamiento para Agentes

1. **Consistencia de Arquitectura:** No introduzcas binarios nativos externos o procesos CLI (`ffmpeg`/`ffprobe`). Utiliza las bibliotecas existentes de Dart puro (`audio_metadata_reader`, `just_audio_media_kit`).
2. **Verificación Estática:** Siempre corre `dart analyze` tras modificar código Dart para asegurar que no queden errores ni advertencias de linting.
3. **No romper i18n:** Todo nuevo string visible en la UI debe contar con su correspondiente clave en `i18n/en.jsonc` y `i18n/es.jsonc` y getter en `AppStringKey`.
4. **Reutilización:** Antes de crear nuevos componentes, revisa `lib/shared/widgets/` y `lib/core/services/` para aprovechar los servicios y widgets existentes.
