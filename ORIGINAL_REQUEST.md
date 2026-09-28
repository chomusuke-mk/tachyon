# Registro Histórico de Solicitudes y Requerimientos (Tachyon)

Este documento registra cronológicamente las especificaciones de desarrollo, solicitudes de usuario y notas de evolución arquitectónica del proyecto **Tachyon**.

---

## 1. Solicitud Fundacional (2026-09-18T05:56:57Z)

> **Nota de Evolución Arquitectónica (Commit `b0df372` a `5e0d28b`):**  
> Los requerimientos originales hacían referencia a la ejecución de procesos CLI de `ffprobe` y `ffmpeg` para la extracción de metadatos y carátulas, y al uso directo de `media_kit` con instancias de `libmpv`. Durante los refactors posteriores, **se eliminaron totalmente las dependencias de binarios nativos externos** en favor de la biblioteca en Dart puro `audio_metadata_reader` ejecutada en un `Isolate` en segundo plano (`scan_isolate.dart`), y el motor de audio se migró a `just_audio` con el adaptador `just_audio_media_kit`.

### Requerimientos Iniciales
- **R1. Motor de Reproducción con Crossfade Continuo y Cola de Reproducción:**
  - Soporte para formatos comunes (MP3, FLAC, WAV, AAC, OGG, M4A).
  - Crossfade continuo nativo y suave por defecto entre pistas sucesivas (duración 1s–12s con curvas Equal-Power o Linear).
  - Gestión avanzada de cola: agregar, reordenar, remover, limpiar, modos de repetición (`off`, `one`, `all`) y shuffle Fisher-Yates preservando la pista actual.
  - Emisión reactiva de estado (`PlaybackState`).
- **R2. Escaneo de Archivos y Extracción de Metadatos:**
  - Servicio de escaneo asíncrono y recursivo de directorios de música seleccionados por el usuario.
  - Extracción de metadatos (título, artista, álbum, año, pista, género, duración, bitrate, carátula) sin generar jank en el hilo principal de la UI.
  - Almacenamiento en caché de miniaturas de carátulas en disco.
- **R3. Persistencia de Biblioteca Local y Preferencias:**
  - Base de datos local SQLite (`sqflite`/`sqlite3`) con esquema relacional para pistas, álbumes, artistas, géneros, carpetas y listas de reproducción.
  - Consultas optimizadas con índices B-Tree para catálogos extensos.
  - Persistencia de preferencias mediante `SharedPreferences`.
- **R4. Interfaz de Usuario Moderna y Adaptativa:**
  - Diseño Material 3 responsivo para escritorio (`NavigationRail`) y móvil (`NavigationBar` + `MiniPlayerBar`).
  - Pantallas de Biblioteca: Pistas virtualizadas, Cuadrícula de Álbumes, Artistas, Géneros, Explorador de Carpetas, Playlists.
  - Búsqueda Global en tiempo real.
  - Pantalla Now Playing inmersiva con barra de progreso tipo onda, controles completos y visor de letras sincronizadas (LRC).
  - Pantalla de Configuración modular con `SettingRow`.
- **R5. Localización (i18n):**
  - Soporte bilingüe (inglés/español) en archivos JSONC (`i18n/en.jsonc`, `i18n/es.jsonc`) con getters tipados en `AppStringKey`. Cero cadenas hardcodeadas.
- **R6. Calidad y Documentación:**
  - Cumplimiento de análisis estático con `dart analyze` (0 errores, 0 warnings).
  - Documentación técnica exhaustiva en Markdown.

---

## 2. Refactorización Masiva y Versión 2 (2026-09-19 a 2026-09-23)

Historial de cambios mayores consolidados:
1. **Commit `b0df372` (*remove ffmpeg ffprobe*):**
   - Eliminación de wrappers nativos (`process_executor.dart`, `ffprobe_metadata_parser.dart`, `native_binary_locator.dart`).
   - Adopción de `audio_metadata_reader` para lectura directa de metadatos en Dart puro.
   - Guardado directo de imágenes en disco en `CoverCacheService`.
   - Limpieza de tests E2E y unitarios acoplados a binarios nativos del sistema.
2. **Commit `728a4bd` (*version 2*):**
   - Creación de `scan_isolate.dart`: escaneo masivo multihilo en `Isolate` de segundo plano para garantizar 60 fps en la UI durante el indexado.
   - Refactor de `MetadataExtractor` para actuar como despachador de mensajes e inserciones en SQLite desde el isolate principal.
3. **Commit `c29b4ff` y `557fea4` (*move to new player / new player library*):**
   - Transición del motor de audio a `just_audio` + `just_audio_media_kit`.
   - Adaptador `AudioPlayerAdapter` con configuración de búfer de 8 MB y `JustAudioMediaKit.ensureInitialized` en plataformas de escritorio.
   - Unificación de `CrossfadeConfig` y simplificación de `PlaybackState`.
4. **Commit `5e0d28b` (*init refactor*):**
   - Refinamiento de controles de reproducción y widgets de Now Playing (`now_playing_screen.dart`, `audio_effects_sheet.dart`, `waveform_slider.dart`).

---

## 3. Solicitud Activa: Subsistema Integral de Letras (2026-09-23T05:37:55Z)

> **Estado:** Aprobado para ejecución  
> **Objetivo:** Implementación completa del subsistema de letras (*Lyrics*) con búsqueda jerárquica multiorigen, persistencia con estado por fuente en SQLite, control estricto de rate limit y umbrales con descarte de canciones en reproducción rápida, y controles interactivos en la interfaz.

### Requerimientos Específicos

#### R1. Jerarquía de Fuentes de Letras y Persistencia con Estado por Origen
- Consultar letras siguiendo un orden de prioridad estricto y configurable:
  1. Letras embebidas en el archivo de audio (metadatos/tags USLT/LYRICS).
  2. Archivo local `.lrc` contiguo a la pista (`<nombre_archivo>.lrc` o `.LRC`).
  3. API primaria: `lrclib.net` (soporta letras sincronizadas y sin sincronizar; consultar `GET /api/get` usando título, artista, álbum y duración con tolerancia $\pm 2$ s).
  4. API secundaria / respaldo: `lyrics.ovh` (letras en texto plano sin marcas de tiempo vía `GET https://api.lyrics.ovh/v1/{artist}/{title}`).
- Las consultas a APIs web remotas solo deben ejecutarse cuando una canción esté reproduciéndose y el usuario se encuentre específicamente en la vista de letras (**LyricsView**, cuando `_showLyrics == true` en Now Playing). Esta búsqueda queda formalmente **delegada al ciclo de vida de renderizado del propio widget `LyricsView`** (al montarse/renderizarse en pantalla), eliminando cualquier búsqueda anticipada o automática en segundo plano desde el listener global del controlador cuando el usuario solo está en la vista estándar de reproducción (*Play View* con carátula y controles, `_showLyrics == false`).
- Persistir en SQLite el contenido de la letra y el estado específico por cada fuente y canción:
  - `FOUND`: Letra obtenida exitosamente de esa fuente.
  - `NOT_FOUND`: La fuente o API confirmó que la letra no existe (ej. HTTP 404 de lrclib.net o sin resultados en lyrics.ovh), de modo que nunca se vuelva a pedir a ese servicio para esa pista.
  - `TEMPORARY_ERROR`: Si la consulta falló por error de red, respuesta 5xx o limitación de tasa (HTTP 429), la pista **no** debe registrarse como `NOT_FOUND`, permitiendo reintentos futuros.

#### R2. Rate Limiting, Cooldowns Globales y Concurrencia en Adelanto Rápido
- Cumplir las especificaciones de `lrclib.net`:
  - Intervalo mínimo de 500 ms entre peticiones consecutivas.
  - Envío de cabecera `User-Agent` identificando la aplicación cliente.
- Manejo reactivo de HTTP 429 (`Too Many Requests`) con lectura de la cabecera `Retry-After`:
  - Si el tiempo de espera indicado es $\le 10$ segundos: mostrar un aviso en pantalla indicando "Threshold de lrclib.net detectado esperando X segundos..." con cuenta regresiva en vivo, reintentando automáticamente al completarse el tiempo si la pantalla sigue abierta.
  - Si el tiempo de espera es $> 10$ segundos (ej. cooldown prolongado o 3 minutos): recurrir de inmediato al servicio secundario (`lyrics.ovh`) para obtener y mostrar texto plano.
- Cooldown en memoria y reintento diferido:
  - Si una canción usó el respaldo debido a un cooldown activo y el temporizador expira mientras el usuario sigue escuchando esa misma canción, solicitar automáticamente las letras a la API primaria y actualizar la vista a letras sincronizadas.
  - Si el usuario pasa a otra canción mientras el cooldown de la API primaria sigue activo, omitir la petición a la API primaria, usar directamente el respaldo disponible y programar la consulta a la API primaria para la canción que esté en reproducción activa en el momento en que venza el cooldown (siempre que Now Playing continúe abierto y no tenga ya una fuente de mayor prioridad).
- Concurrencia y ráfaga de saltos en playlist:
  - Si el usuario adelanta canciones rápidamente (ej. 1 → 2 → 3 → 4 → 5), mientras la canción 1 se está procesando o esperando, las peticiones intermedias (2, 3, 4) deben ser descartadas/canceladas inmediatamente, pasando a procesar directamente la pista 5 para evitar peticiones redundantes y prevenir bloqueos.

#### R3. Interfaz de Usuario y Controles en la Vista de Letras
- Incorporar en la parte superior de la vista de letras 3 controles principales:
  1. **Botón de traducción**: Traducir las letras a través de un endpoint público gratuito sin requerir credenciales, permitiendo visualizar la traducción intercalada o alternar entre el texto original y la traducción.
  2. **Configuración de fuentes**: Diálogo/modal flotante con switches individuales para habilitar/deshabilitar:
     - Archivos locales (embebido y archivo `.lrc`).
     - Servidor 1 (`lrclib.net`).
     - Servidor 2 (`lyrics.ovh`).
     E incluir dentro del diálogo una acción para volver a buscar con las fuentes configuradas.
  3. **Botón de re-búsqueda ("Volver a buscar")**: Fuerza una nueva búsqueda en las fuentes habilitadas para la canción actual, refrescando la caché y la interfaz.
- Notificaciones y banners visuales no invasivos para avisos de threshold/espera.
- Internacionalización completa mediante `i18n/*.jsonc` y el sistema tipado `AppStringKey` en `lib/features/locales/domain/locale.dart` (cero strings hardcodeados).

## 2026-09-23T06:11:11Z

[ACTUALIZACIÓN CRÍTICA DE REQUERIMIENTO - USUARIO]
El usuario ha emitido la siguiente directiva explícita para la obtención de letras:
"para hacer mas facil saber cuando buscar las letras sera utilizar lyrics view en lugar del play view ya que no siempre se esta buscando la letra"

ESPECIFICACIÓN FORMALIZADA:
1. El disparador (trigger) para buscar y solicitar letras (especialmente consultas a APIs remotas como lrclib.net y lyrics.ovh) NO debe ejecutarse por el mero hecho de que la pantalla Now Playing esté abierta en la vista principal de reproducción (play view / vista de carátula con controles).
2. La búsqueda y consulta de letras se debe disparar ÚNICAMENTE cuando el usuario se encuentre de manera efectiva y visible en la vista de letras (LyricsView, cuando _showLyrics == true en Now Playing).
3. Si el usuario está en Now Playing viendo la carátula y controles estándar (_showLyrics == false), NO se deben disparar peticiones ni búsquedas a las APIs.
4. Solo cuando se abre/activa LyricsView (o si ya está abierta mientras una canción se reproduce activamente), el controlador debe iniciar la resolución jerárquica de letras (embebidas -> local .lrc -> lrclib.net -> lyrics.ovh).

Por favor, incorporar este criterio en las especificaciones del Hito 2, Hito 3, Hito 4 y en las suites de prueba E2E / unitarias inmediatamente.

## 2026-09-23T06:12:50Z

[PRECISIÓN TÉCNICA DE IMPLEMENTACIÓN - USUARIO]
El usuario aclara la mecánica exacta de la directiva:

1. COMPORTAMIENTO PREVIO EN CÓDIGO:
Actualmente, `LyricsController` escucha a `PlaybackController` y dispara automáticamente `_loadLyricsForTrack` en segundo plano cada vez que cambia o se reproduce una canción, incluso si la vista de letras nunca se abre.

2. NUEVO COMPORTAMIENTO REQUERIDO:
- Eliminar la búsqueda automática reactiva en segundo plano desde el constructor/listener de reproducción cuando la vista de letras no está activa.
- La búsqueda de letras debe estar vinculada directamente a la presencia/renderizado de `LyricsView`.
- Dado que `NowPlayingScreen` renderiza condicionalmente `LyricsView` únicamente cuando el usuario solicita ver las letras (`_showLyrics ? LyricsView(...) : CoverArtHero(...)`), es el propio widget `LyricsView` (o su ciclo de vida al montarse/renderizarse mediante un método como `ensureLyricsLoaded()` o `loadLyrics()`) el encargado de solicitar las letras al controlador.
- De este modo, si el usuario nunca activa la vista de letras, nunca se ejecutan búsquedas ni peticiones a las APIs. Si la vista de letras ya está en pantalla y la canción cambia, `LyricsView` continúa montado y solicita las letras de la nueva canción.

Por favor, aplicar este patrón de diseño en el Hito 3 y Hito 4 (desacoplar el listener global de `PlaybackController` para carga de red y delegar la carga activa al montaje de `LyricsView`).

---

## 2026-09-24T05:33:05Z

[OPTIMIZACIÓN INTEGRAL Y MASIVA DE RENDIMIENTO EN LINUX]
Optimización integral y masiva del rendimiento de Tachyon en Linux: reducción drástica de memoria RAM (de ~450-480MB hacia el rango de ~20-50MB o piso mínimo del engine), minimización del consumo de CPU y GPU en reproducción, y eliminación completa del parpadeo (flickering) al redimensionar la ventana. El usuario solicita explícitamente: "lanzar varios equipos de ser necesario".

Working directory: /mnt/Proyectos/tachyon
Integrity mode: development

## Requirements

### R1. Reducción masiva del consumo de memoria RAM (Reposo y Reproducción)
Reducir de forma drástica el consumo de memoria RAM en modo release (actualmente ~450MB en reposo y ~480MB en reproducción) hacia el objetivo especificado por el usuario de ~20MB a 50MB (o el mínimo piso físico estricto que imponga el runtime del Flutter Engine/GTK3 en Linux), eliminando retenciones superfluas, ajustando agresivamente la memoria de caché de imágenes y optimizando el almacenamiento en memoria de colecciones y buffers.

### R2. Minimización de consumo de CPU y GPU durante la reproducción
Reducir el uso de CPU (del ~5% actual a niveles mínimos de reposo) y el uso de GPU (del 20-30% actual a menos del 3-5%) durante la reproducción activa de audio, eliminando repintados globales innecesarios y optimizando el renderizado de la barra de progreso y el `WaveformSlider` mediante aislamiento visual estricto y control de tasa de refresco.

### R3. Eliminación de parpadeo (flickering) en la interfaz al redimensionar
Eliminar los artefactos visuales, cuadros negros o parpadeos que ocurren al cambiar interactivamente el tamaño de la ventana en la pantalla de reproducción (`NowPlayingScreen`) o a lo largo del shell de la aplicación.

### R4. Preservación de estabilidad, contratos y compatibilidad
Garantizar que todas las características existentes (crossfade continuo sin interrupciones, letras sincronizadas y offline, escaneo incremental, persistencia SQLite en isolate principal y soporte i18n sin strings hardcodeados) permanezcan plenamente operativas y sin regresiones.

## Acceptance Criteria

### Rendimiento y Recursos (Métricas Objetivas)
- [ ] En modo release (`flutter run -d linux --release` o binario release compilado), la memoria RAM residente (RSS) en estado de reposo se reduce radicalmente desde los ~450MB actuales acercándose al rango objetivo de ~20-50MB (o la cota mínima física del Flutter Engine en Linux).
- [ ] Durante la reproducción continua de una pista de audio, el uso de CPU permanece por debajo del 2% y el uso de GPU se mantiene por debajo del 5%.
- [ ] Al redimensionar interactivamente la ventana de la aplicación en `NowPlayingScreen`, la interfaz se redibuja fluidamente sin parpadeos visuales ni saltos en negro.

### Calidad de Código y Regresiones
- [ ] `dart analyze` reporta 0 errores y 0 advertencias en todo el proyecto.
- [ ] El 100% de las pruebas unitarias y de integración existentes pasan exitosamente (`flutter test` sin fallos).
- [ ] No se agregan cadenas hardcodeadas en widgets ni se introducen procesos binarios externos incompatibles con la arquitectura de Tachyon.
