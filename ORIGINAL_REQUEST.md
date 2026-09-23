# Original User Request

## 2026-09-18T05:56:57Z

# Teamwork Project Prompt — Draft

> Status: Launched
> Goal: Craft prompt → get user approval → delegate to teamwork_preview
> Requested team: Full autonomous software engineering team

Tachyon es un reproductor de música moderno, completo, refinado y 100% libre desarrollado en Flutter (Dart) con soporte multiplataforma (Desktop y Mobile). Implementa un motor de reproducción de alto rendimiento con crossfade continuo por defecto, extracción de metadatos mediante `ffprobe`, indexación y persistencia en base de datos local SQLite, configuración persistente con `SharedPreferences`, soporte de internacionalización (i18n), verificador de actualizaciones, interfaz de usuario contemporánea y adaptativa basada en `docs-from-otro-player` y la arquitectura modular de referencia de `vidra`.

Working directory: /mnt/Proyectos/tachyon
Integrity mode: development

Reference materials:
- `/mnt/Proyectos/tachyon/docs-from-otro-player/` (Especificaciones de arquitectura, crossfade, reproducción, biblioteca, letras, efectos de audio y diseño de pantallas).
- `/mnt/Proyectos/vidra/` (Arquitectura de referencia para i18n JSONC con `AppStringKey`, cliente HTTP, verificador de actualizaciones, estructura de controladores y CI/CD).

## Requirements

### R1. Motor de Reproducción con Crossfade Continuo y Cola de Reproducción
- Motor de reproducción multimedia local (`media_kit`) capaz de manejar formatos comunes (MP3, FLAC, WAV, AAC, OGG, M4A).
- Soporte nativo de crossfade continuo y suave por defecto entre canciones (superposición de audio con fade in/fade out configurable sin cortes ni silencios).
- Gestión avanzada de cola de reproducción: agregar, reordenar, remover, limpiar, modos de repetición (desactivado, repetir todo, repetir una pista) y reproducción aleatoria (shuffle).
- Emisión reactiva de estado (posición, duración, volumen, velocidad, estado de reproducción, pista actual).

### R2. Escaneo de Archivos y Extracción de Metadatos con `ffprobe`
- Servicio de escaneo asíncrono y recursivo de directorios de música seleccionados por el usuario.
- Extracción de metadatos precisos (título, artista, álbum, año, track number, género, duración, bitrate, sample rate, portada embebida) ejecutando los binarios nativos de `ffprobe` de forma eficiente en segundo plano sin degradar la tasa de cuadros (jank) de la UI.
- Generación y almacenamiento en caché de miniaturas de carátulas (cover art).

### R3. Persistencia de Biblioteca Local y Preferencias
- Base de datos local SQLite estructurada (seleccionando la opción más robusta y mantenible, e.g. `drift` o `sqflite`) con esquema relacional para pistas, álbumes, artistas, géneros, carpetas y listas de reproducción (playlists) personalizadas.
- Consultas optimizadas con ordenamiento, agrupación y filtrado instantáneo para catálogos extensos (> 5,000 pistas).
- Persistencia de preferencias del usuario y estado de la aplicación mediante `SharedPreferences` (directorios seleccionados, volumen, duración de crossfade, último track/posición reproducida, tema, idioma).

### R4. Interfaz de Usuario Moderna, Adaptativa y Completa
- Diseño visual moderno, pulido y responsivo para escritorio y móvil (Material 3, tema oscuro y personalizable).
- Pantallas de Biblioteca:
  - Pistas (Tracks): lista virtualizada con información completa, menú contextual (reproducir siguiente, añadir a cola, añadir a playlist, ver detalles).
  - Álbumes: vista de cuadrícula con carátulas de alta resolución y vista detallada del álbum.
  - Artistas: vista de artistas y su discografía agrupada.
  - Géneros y Carpetas: exploración jerárquica del sistema de archivos.
  - Playlists: creación, edición, reordenamiento y eliminación de listas de reproducción.
- Búsqueda Global: búsqueda en tiempo real con resaltado por título, artista o álbum.
- Vista Now Playing:
  - Diseño inmersivo con visualización de portada, controles de transporte completos, deslizador de progreso interactivo y control de volumen.
  - Visor de letras sincronizadas (formato LRC) y no sincronizadas con desplazamiento suave.
  - Vista deslizable o modal de la cola de reproducción actual con reordenamiento interactivo.
- Pantalla de Configuración completa y modular:
  - Gestión de carpetas de música (añadir/remover rutas, botón de reescanear).
  - Ajustes de audio (duración de crossfade en segundos, ecualización/efectos si aplica).
  - Preferencias de apariencia (tema oscuro/claro/sistema, colores dinámicos).
  - Selección de idioma y sección "Acerca de" con verificación de versiones.

### R5. Localización (i18n) e Indicador de Actualizaciones
- Soporte multilenguaje completo (inglés y español de base) estructurado en archivos JSONC (`i18n/en.jsonc`, `i18n/es.jsonc`) gestionados mediante una clase centralizada de constantes/getters (`AppStringKey`), garantizando cero textos hardcodeados en la UI.
- Selector de idioma en tiempo real en la pantalla de ajustes sin necesidad de reiniciar la app.
- Servicio de verificación de actualizaciones contra GitHub Releases (o repositorio de la app), con notificación visual no intrusiva y registro de cambios (Changelog).

### R6. Pruebas Automatizadas, Workflows de CI/CD y Documentación
- Suite completa de pruebas unitarias y de widgets con `flutter test` que cubran el parseo de metadatos con `ffprobe`, la lógica de crossfade/cola y las operaciones CRUD de la base de datos local.
- Cumplimiento de análisis estático con `dart analyze` (0 errores, 0 warnings).
- Flujos de trabajo de GitHub Actions (`.github/workflows`) para integración continua (pruebas, análisis y compilación en plataformas soportadas).
- Documentación técnica exhaustiva en Markdown dentro del repositorio (arquitectura de la app, guía de módulos, instrucciones de compilación y pruebas).

## Acceptance Criteria

### Playback & Crossfade Engine
- [ ] Reproducción continua sin pausas ni ruidos de formatos de audio estándar (MP3, FLAC, WAV, AAC, OGG).
- [ ] Transición crossfade fluida entre pistas consecutivas con duración configurable (1s a 12s) verificable programáticamente.
- [ ] Comportamiento verificado de cola de reproducción: agregar al final, reproducir siguiente, shuffle sin repeticiones inmediatas y modos repeat.

### Metadata Extraction & Storage
- [ ] Parseo de metadatos con `ffprobe` extrae exitosamente etiquetas estándar y portadas de archivos reales.
- [ ] Operaciones de base de datos (inserción masiva, lectura, búsquedas y playlists) ejecutadas asíncronamente en SQLite.
- [ ] El proceso de escaneo y lectura de biblioteca mantiene 60 fps en la UI sin bloquear el hilo principal.

### User Interface & Experience
- [ ] Navegación completa y funcional entre todas las secciones (Pistas, Álbumes, Artistas, Géneros, Playlists, Búsqueda, Configuración, Now Playing).
- [ ] El reproductor Now Playing refleja en tiempo real el progreso de reproducción, la carátula y las letras sincronizadas cuando estén disponibles.
- [ ] Persistencia garantizada de configuraciones y volumen a través de `SharedPreferences`.

### Quality & Delivery
- [ ] Cambio dinámico de idioma entre inglés y español funcional en toda la interfaz sin reiniciar.
- [ ] El comprobador de actualizaciones consulta la versión remota y muestra el diálogo/banner correspondiente si existe una versión más reciente.
- [ ] `dart analyze` completa con 0 errores y 0 warnings.
- [ ] `flutter test` ejecuta y pasa todos los tests unitarios y de componentes.
- [ ] Documentación técnica completa (README, Architecture Guide, Build Instructions) generada en el repositorio.

## 2026-09-23T05:37:55Z

# Teamwork Project Prompt — Draft

> Status: Launched
> Goal: Craft prompt → get user approval → delegate to teamwork_preview
> Requested team: Equipo completo (Full Team)

Implementación integral del subsistema de letras (Lyrics) para el reproductor musical Tachyon, incorporando búsqueda jerárquica (embebidas, archivo local .lrc, APIs remotas lrclib.net y lyrics.ovh como respaldo), persistencia con rastreo de estado por origen en SQLite, control estricto de rate limit y umbrales con descarte de canciones en reproducción rápida, y controles interactivos en la interfaz (traducción, configuración de fuentes y re-búsqueda).

Working directory: /mnt/Proyectos/tachyon
Integrity mode: development

## Requirements

### R1. Jerarquía de Fuentes de Letras y Persistencia con Estado por Origen
- Consultar letras siguiendo un orden de prioridad estricto y configurable:
  1. Letras embebidas en el archivo de audio (metadatos/tags USLT/LYRICS).
  2. Archivo local `.lrc` contiguo a la pista (`<nombre_archivo>.lrc` o `.LRC`).
  3. API primaria: `lrclib.net` (soporta letras sincronizadas y sin sincronizar; consultar `GET /api/get` usando título, artista, álbum y duración con tolerancia ±2 s).
  4. API secundaria / respaldo: `lyrics.ovh` (letras en texto plano sin marcas de tiempo).
- Las consultas a APIs web remotas solo deben ejecutarse cuando una canción esté reproduciéndose y la pantalla de reproducción actual (Now Playing / Lyrics) se encuentre abierta y visible.
- Persistir en SQLite el contenido de la letra y el estado específico por cada fuente y canción:
  - `FOUND`: Letra obtenida exitosamente de esa fuente.
  - `NOT_FOUND`: La fuente o API confirmó que la letra no existe (ej. HTTP 404 de lrclib.net o sin resultados en lyrics.ovh), de modo que nunca se vuelva a pedir a ese servicio para esa pista.
  - `TEMPORARY_ERROR`: Si la consulta falló por error de red, respuesta 5xx o limitación de tasa (HTTP 429), la pista **no** debe registrarse como `NOT_FOUND`, permitiendo reintentos futuros.

### R2. Rate Limiting, Cooldowns Globales y Concurrencia en Adelanto Rápido
- Cumplir las especificaciones de `lrclib.net`:
  - Intervalo mínimo de 500 ms entre peticiones consecutivas.
  - Envío de cabecera `User-Agent` identificando la aplicación cliente.
- Manejo reactivo de HTTP 429 (`Too Many Requests`) con lectura de la cabecera `Retry-After`:
  - Si el tiempo de espera indicado es ≤ 10 segundos: mostrar un aviso en pantalla indicando "Threshold de lrclib.net detectado esperando X segundos..." con cuenta regresiva en vivo, reintentando automáticamente al completarse el tiempo si la pantalla sigue abierta.
  - Si el tiempo de espera es > 10 segundos (ej. cooldown prolongado o 3 minutos): recurrir de inmediato al servicio secundario (`lyrics.ovh`) para obtener y mostrar texto plano.
- Cooldown en memoria y reintento diferido:
  - Si una canción usó el respaldo debido a un cooldown activo y el temporizador expira mientras el usuario sigue escuchando esa misma canción, solicitar automáticamente las letras a la API primaria y actualizar la vista a letras sincronizadas.
  - Si el usuario pasa a otra canción mientras el cooldown de la API primaria sigue activo, omitir la petición a la API primaria, usar directamente el respaldo disponible y programar la consulta a la API primaria para la canción que esté en reproducción activa en el momento en que venza el cooldown (siempre que Now Playing continúe abierto y no tenga ya una fuente de mayor prioridad).
- Concurrencia y ráfaga de saltos en playlist:
  - Si el usuario adelanta canciones rápidamente (ej. 1 → 2 → 3 → 4 → 5), mientras la canción 1 se está procesando o esperando, las peticiones intermedias (2, 3, 4) deben ser descartadas/canceladas inmediatamente, pasando a procesar directamente la pista 5 para evitar peticiones redundantes y prevenir bloqueos.

### R3. Interfaz de Usuario y Controles en la Vista de Letras
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

## Acceptance Criteria

### Persistencia y Jerarquía de Fuentes
- [ ] La base de datos SQLite almacena el estado por fuente para cada pista, previniendo peticiones duplicadas cuando una fuente ya devolvió `NOT_FOUND`.
- [ ] Errores HTTP 429 o fallas de conexión no marcan la pista como `NOT_FOUND` en base de datos.
- [ ] La búsqueda de APIs externas no se dispara en segundo plano si la vista Now Playing / Lyrics está cerrada.
- [ ] Los switches de configuración de fuentes alteran de forma inmediata qué fuentes son consultadas.

### Rate Limiting, Cooldowns y Manejo de Concurrencia
- [ ] El cliente HTTP de `lrclib.net` mantiene un intervalo mínimo de 500 ms entre solicitudes salientes y envía el encabezado `User-Agent`.
- [ ] Respuestas HTTP 429 con `Retry-After <= 10s` activan el mensaje visual con temporizador y reintentan automáticamente.
- [ ] Respuestas HTTP 429 con `Retry-After > 10s` realizan fallback inmediato a `lyrics.ovh`.
- [ ] Durante un cooldown activo, nuevas canciones saltan la API bloqueada y consultan `lyrics.ovh`; al expirar el cooldown, la canción activa reintenta la API primaria.
- [ ] Ante saltos rápidos sucesivos de canciones en la cola (1 a 5), las peticiones intermedias son canceladas o descartadas, procesando únicamente la canción final.

### UI, Traducción e Internacionalización
- [ ] La barra superior de letras contiene los 3 botones operativos: Traducción, Diálogo flotante de fuentes con switches y botón de re-búsqueda, y Volver a buscar.
- [ ] La traducción traduce y presenta el texto en la interfaz.
- [ ] Todos los textos agregados en la UI cuentan con sus entradas en `en.jsonc` y `es.jsonc`, y sus correspondientes getters en `AppStringKey`.
- [ ] El código pasa `dart analyze` sin errores ni advertencias.
