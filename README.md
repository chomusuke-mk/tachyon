# Tachyon Music Player 🎵⚡

**Tachyon** es un reproductor de música moderno, refinado, multiplataforma y de código abierto desarrollado con **Flutter (Dart)**. Diseñado con una arquitectura limpia (Clean Architecture), un motor de audio de alta fidelidad con **crossfade continuo real**, escaneo de biblioteca ultrarrápido en segundo plano sin dependencias de binarios nativos pesados, y un subsistema inteligente de letras sincronizadas con fallback automático en APIs web.

---

## ✨ Características Principales

### 🎧 Motor de Audio de Alta Fidelidad
- **Crossfade Continuo Real:** Superposición de audio fluida entre canciones consecutivas con duración personalizable (1s a 12s) usando curvas *Equal-Power* o *Linear* impulsadas por un ticker de 25 ms.
- **Reproducción Gapless:** Transición instantánea entre pistas sin cortes ni silencios.
- **Efectos y Calibración:** Control de velocidad de reproducción (0.5x–1.5x), desplazamiento de tono / pitch (0.5–1.5) y amplificación de volumen (*Volume Boost*) hasta 200%.
- **Gestión Avanzada de Cola:** Modos de repetición (`Off`, `One`, `All`), reproducción aleatoria (*Fisher-Yates shuffle*) que preserva la pista en curso en el índice 0, e inserción dinámica (*Play Next* / *Add to Queue*).

### ⚡ Extracción de Metadatos 100% en Dart
- **Sin binarios externos:** No requiere `ffmpeg` ni `ffprobe` instalados en el sistema operativo.
- **Escaneo no bloqueante en Isolate:** Procesamiento recursivo masivo de etiquetas ID3, FLAC y Vorbis mediante `audio_metadata_reader` en un `Isolate` dedicado (`scan_isolate.dart`), garantizando 60 fps estables en la interfaz.
- **Caché Inteligente de Carátulas:** Extracción directa de carátulas embebidas y detección de archivos locales (`cover.jpg`, `folder.jpg`) con almacenamiento optimizado en disco.

### 📜 Subsistema Inteligente de Letras (Lyrics)
- **Búsqueda Jerárquica Multiorigen:**
  1. Letras embebidas en metadatos del archivo de audio (USLT/LYRICS).
  2. Archivos locales `.lrc` contiguos a la pista.
  3. API primaria: **`lrclib.net`** (letras sincronizadas y texto plano, con tolerancia de duración $\pm 2$ s).
  4. API de respaldo: **`lyrics.ovh`** (texto plano sin marcas de tiempo).
- **Sincronización O(log n):** Resolución de la línea activa en tiempo real mediante `SplayTreeMap` con auto-desplazamiento suave y salto temporal interactivo (*Tap-to-Seek*).
- **Manejo Defensivo de APIs y Rate Limiting:**
  - Intervalo mínimo de 500 ms y User-Agent en `lrclib.net`.
  - Detección de umbrales HTTP 429 con `Retry-After`:
    - Espera $\le 10$ s: Mensaje visual en pantalla con cuenta regresiva y reintento automático.
    - Espera $> 10$ s: Fallback inmediato a texto plano sin bloquear al usuario.
  - Cancelación de peticiones intermedias al saltar pistas en ráfaga en la cola.
- **Controles en Pantalla:** Botón de traducción automática, diálogo flotante para activar/desactivar fuentes individuales y botón de re-búsqueda inmediata.

### 🎨 Diseño y Experiencia de Usuario
- **Material 3 Adaptativo:** Navegación en `NavigationRail` para escritorio y `NavigationBar` para móvil, con barra de transporte inferior y mini-reproductor anclado.
- **Esquema de Color Dinámico y OLED:** Jerarquía de 5 superficies con soporte para modo claro, oscuro y modo negro puro (OLED).
- **Internacionalización Completa (i18n):** Soporte bilingüe inglés/español sin textos hardcodeados mediante archivos JSONC (`i18n/*.jsonc`) y `AppStringKey`.

---

## 🏗️ Arquitectura y Tecnologías

| Capa | Tecnologías | Descripción |
|---|---|---|
| **UI & Presentación** | Flutter (Material 3), `provider` | Shell responsivo, vistas virtualizadas, Now Playing inmersivo, waveform slider |
| **Lógica de Estado** | `ChangeNotifier`, `BehaviorSubject` | Flujo unidireccional y reactivo para controladores de reproducción, biblioteca y letras |
| **Motor de Audio** | `just_audio`, `just_audio_media_kit` | Coordinación de dos reproductores para crossfade y control de efectos |
| **Metadatos** | Dart `Isolate`, `audio_metadata_reader` | Parseo concurrente de audio sin sobrecarga en la UI |
| **Persistencia** | SQLite (`sqflite`, `sqlite3`), `shared_preferences` | Tablas relacionales con índices B-Tree y caché de letras con estado por origen |
| **Internacionalización** | `jsonc`, `AppStringKey` | Carga de diccionarios JSONC en tiempo de ejecución con cambio dinámico de idioma |

Para detalles exhaustivos de desarrollo, convenciones y guía para agentes de IA, consulta:
- 📖 [AGENTS.md](file:///mnt/Proyectos/tachyon/AGENTS.md): Guía de desarrollo y estándares de codificación.
- 📐 [PROJECT.md](file:///mnt/Proyectos/tachyon/PROJECT.md): Especificación técnica, mapa de módulos, hitos e interfaces.
- 📋 [ORIGINAL_REQUEST.md](file:///mnt/Proyectos/tachyon/ORIGINAL_REQUEST.md): Registro histórico y requerimientos activos.

---

## 🚀 Inicio Rápido y Desarrollo

### Requisitos Previos
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart 3.x+)
- Bibliotecas del sistema para compilación de escritorio:
  - **Linux:** `libmpv-dev`, `libmpv2`, `build-essential`, `cmake`
  - **Windows:** Visual Studio con C++ Desktop Development tools
  - **macOS:** Xcode y herramientas de línea de comandos

### Comandos de Ejecución
```bash
# 1. Obtener dependencias
flutter pub get

# 2. Verificar análisis estático (0 errores, 0 warnings requeridos)
dart analyze

# 3. Ejecutar en tu plataforma preferida
flutter run -d linux      # Linux Desktop
flutter run -d windows    # Windows Desktop
flutter run -d macos      # macOS Desktop
flutter run -d android    # Dispositivo / Emulador Android
```

### Ejecución de Pruebas
```bash
flutter test
```

---

## 📄 Licencia

Este proyecto está bajo los términos de la licencia [GPL-3.0](file:///mnt/Proyectos/tachyon/LICENSE).
