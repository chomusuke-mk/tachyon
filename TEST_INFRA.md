# Infraestructura de Pruebas: Tachyon Music Player

**Estado:** En transición / Activa para Arquitectura v2  
**Versión de Especificación:** 2.0.0  
**Plataformas Objetivo:** Linux, Windows, macOS, Android, iOS  
**Ejecutor de Pruebas:** Flutter Test (`flutter test`)  
**Análisis Estático:** `dart analyze` (0 errores, 0 warnings requeridos)

---

## 1. Filosofía de Pruebas y Evolución de Arquitectura

El reproductor **Tachyon** fue refactorizado masivamente (commits `b0df372` a `5e0d28b`) para eliminar el acoplamiento a binarios nativos externos (`ffprobe`, `ffmpeg` por subprocesos) y migrar el motor de audio a `just_audio` + `just_audio_media_kit`.

La suite previa de pruebas (v1) dependía de fixtures y wrappers de procesos nativos que fueron descontinuados. La nueva infraestructura de pruebas (v2) se construye sobre pruebas unitarias y de componentes en Dart puro con aislamiento de dependencias:
- **Sin binarios externos:** Mocks para clientes HTTP y adaptadores de audio.
- **Aislamiento de persistencia:** Pruebas de SQLite ejecutadas sobre bases de datos en memoria (`in-memory database` vía `sqflite_common_ffi`).
- **Verificación determinista:** Pruebas matemáticas de curvas de crossfade y resolución temporal $O(\log n)$ con `SplayTreeMap`.

---

## 2. Niveles de Prueba de la Arquitectura v2

```
┌────────────────────────────────────────────────────────────────────────┐
│                   Nivel 4: Integración UI y Flujos de Usuario          │
│  Pruebas de widgets para Now Playing, vista de letras y diálogos       │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
┌───────────────────────────────────┴────────────────────────────────────┐
│              Nivel 3: Subsistema de Letras y Red Defensiva            │
│  Manejo de HTTP 429 (Retry-After), rate limit 500ms, fallback de APIs │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
┌───────────────────────────────────┴────────────────────────────────────┐
│                Nivel 2: Motor de Audio y Concurrencia en Isolate       │
│  Protocolo de scan_isolate, curvas de crossfade, cola Fisher-Yates     │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
┌───────────────────────────────────┴────────────────────────────────────┐
│                  Nivel 1: Dominio y Persistencia Local                 │
│  Esquema SQLite, caché de letras por fuente, modelos inmutables, i18n  │
└────────────────────────────────────────────────────────────────────────┘
```

### Nivel 1: Dominio y Persistencia Local
- Esquema de base de datos relacional (`AppDatabase`): inserción por lotes, búsqueda y relaciones.
- Tabla `lyrics_cache`: persistencia de estados por origen (`FOUND`, `NOT_FOUND`, `TEMPORARY_ERROR`).
- Serialización de entidades (`Track`, `Album`, `Artist`, `QueueItem`, `PlaybackState`).
- Verificación del catálogo de cadenas `AppStringKey` en `i18n/en.jsonc` y `i18n/es.jsonc`.

### Nivel 2: Motor de Audio y Concurrencia
- Comunicación bidireccional del `scan_isolate.dart` con `MetadataExtractor`.
- Cálculo matemático de curvas de volumen en crossfade:
  - Curva Equal-Power: $V_A(t) = \cos(\frac{\pi}{2} t)$, $V_B(t) = \sin(\frac{\pi}{2} t)$.
  - Curva Lineal: $V_A(t) = 1 - t$, $V_B(t) = t$.
- Algoritmo de barajado Fisher-Yates en `QueueManager` (índice 0 preservado).

### Nivel 3: Subsistema de Letras y Red Defensiva
- Consulta jerárquica: Embebido → `.lrc` local → `lrclib.net` → `lyrics.ovh`.
- Cumplimiento de rate limit de 500 ms en solicitudes a `lrclib.net`.
- Manejo de cabecera `Retry-After`:
  - $\le 10$ s: Estado de espera y reintento diferido.
  - $> 10$ s: Fallback inmediato a texto plano de `lyrics.ovh`.
- Cancelación y descarte de peticiones intermedias ante saltos continuos en la cola.

### Nivel 4: Componentes de UI
- `LyricsView`: visualización y auto-desplazamiento de líneas activas.
- Diálogo de configuración de fuentes y re-búsqueda.
- Control interactivo de tap-to-seek sobre líneas sincronizadas.

---

## 3. Comandos de Ejecución de Pruebas

```bash
# Ejecutar todas las pruebas unitarias y de widgets
flutter test

# Ejecutar con salida detallada
flutter test -v

# Ejecutar análisis estático obligatorio
dart analyze
```
