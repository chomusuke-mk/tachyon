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
