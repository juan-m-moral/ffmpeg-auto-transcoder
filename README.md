# FFmpeg Auto Transcoder

Transcodificador automático de películas desarrollado en Bash utilizando FFmpeg y aceleración por hardware NVIDIA NVENC.

El proyecto nace con el objetivo de automatizar por completo el procesamiento de una biblioteca de películas. Analiza cada vídeo, calcula automáticamente el bitrate más adecuado, procesa el contenido a HEVC (H.265), lo reescala a 4K cuando es necesario, conserva la información multimedia original y organiza el resultado para su integración en una biblioteca Jellyfin.

Además, obtiene automáticamente información desde TMDb y OMDb para renombrar las películas y preparar la biblioteca para Jellyfin.

Todo el proceso está pensado para ejecutarse de forma desatendida, incluyendo monitorización en tiempo real, registro de errores y organización automática de los archivos.

Este proyecto ha sido desarrollado con un enfoque práctico, priorizando la automatización, la estabilidad y la facilidad de mantenimiento sobre la complejidad innecesaria.

---

## Características

- Transcodificación automática de películas.
- Codificación por hardware mediante NVIDIA NVENC.
- Reescalado automático a resolución 4K.
- Conservación de pistas de audio y subtítulos.
- Renombrado automático mediante TMDb y OMDb.
- Compatible con bibliotecas Jellyfin.
- Monitor en tiempo real con información de FFmpeg y de la GPU.
- Configuración centralizada mediante `config.sh`.
- Registro completo de todas las operaciones.
- Organización automática de películas procesadas y errores.
---

## Requisitos

Para utilizar este proyecto se necesita:

### 🐧 Sistema operativo

- Linux (desarrollado y probado en Linux Mint).

### 💻 Software

- 🐚 Bash
- 🎬 FFmpeg con soporte para NVIDIA NVENC
- 🔍 FFprobe
- 📦 jq
- 🌐 curl
- 🖥️ nvidia-smi

### 🖥️ Hardware

- 🟢 GPU NVIDIA compatible con NVENC.

### 🔑 APIs

Es necesario disponer de claves API para:

- 🎞️ TMDb
- 🎬 OMDb

---

## Instalación

Clona el repositorio:

```bash
git clone https://github.com/mcjmm1-gif/ffmpeg-auto-transcoder.git
```

Accede al directorio del proyecto:

```bash
cd ffmpeg-auto-transcoder
```

Configura el archivo `config.sh` según tu sistema:

- Ruta del disco de trabajo.
- Claves API de TMDb y OMDb.
- Resolución de salida.
- Parámetros de calidad.

Concede permisos de ejecución a los scripts si es necesario:

```bash
chmod +x *.sh
```

Ejecuta el transcodificador:

```bash
./procesar.sh
```

En otra terminal puedes iniciar el monitor:

```bash
./monitor.sh
---

## Configuración

Toda la configuración del proyecto se encuentra centralizada en el archivo:

```text
config.sh
---

## Estructura del proyecto

```text
ffmpeg-auto-transcoder/
│
├── config.sh              Configuración general
├── procesar.sh            Motor principal de transcodificación
├── monitor.sh             Monitor en tiempo real
├── tmdb.sh                Acceso a la API de TMDb
├── omdb.sh                Acceso a la API de OMDb
├── Dockerfile             Imagen Docker
├── docker-compose.yml     Despliegue mediante Docker
├── README.md              Documentación principal
├── .gitignore             Exclusiones de Git
│
└── docs/                  Documentación adicional (próximamente)
```

## Flujo de trabajo

El funcionamiento general del transcodificador es el siguiente:

```text
           Nueva película
                  │
                  ▼
     Análisis con FFprobe
                  │
                  ▼
    Obtención de metadatos
       (TMDb / OMDb)
                  │
                  ▼
 Cálculo dinámico del bitrate
                  │
                  ▼
 Reescalado y codificación
     FFmpeg + NVIDIA NVENC
                  │
                  ▼
 Monitorización en tiempo real
                  │
                  ▼
 Verificación del resultado
                  │
                  ▼
 Renombrado automático
                  │
                  ▼
 Copia a la biblioteca Jellyfin
                  │
                  ▼
 Organización de archivos
  (procesadas, errores, logs)
```

Todo el proceso está completamente automatizado. El sistema puede trabajar de forma desatendida durante largos periodos de tiempo procesando nuevas películas conforme aparecen en el directorio de entrada.
---

## Organización de directorios

El proyecto organiza automáticamente los archivos durante el proceso de transcodificación.

```text
DISCO/
│
├── entrada/
│     Películas pendientes de procesar.
│
├── procesadas/
│     Resultado temporal de la transcodificación.
│
├── jellyfin/
│     Biblioteca lista para Jellyfin.
│
├── terminadas/
│     Archivos originales ya procesados.
│
├── errores/
│     Archivos que no pudieron procesarse.
│
└── logs/
      Registros de ejecución, progreso y diagnóstico.
---

## Tecnologías utilizadas

- **Bash** como lenguaje principal.
- **FFmpeg** para el procesamiento de vídeo.
- **FFprobe** para el análisis multimedia.
- **NVIDIA NVENC** para la aceleración por hardware.
- **TMDb API** para la obtención de metadatos.
- **OMDb API** como fuente adicional de información.
- **Jellyfin** como destino de la biblioteca multimedia.
- **Docker** (opcional) para facilitar el despliegue.

Esta estructura permite mantener organizada la biblioteca multimedia y facilita la recuperación ante posibles errores durante el proceso.---

## Estado del proyecto

Actualmente el proyecto se encuentra en desarrollo activo.

### Funcionalidades implementadas

- ✔ Transcodificación automática mediante FFmpeg.
- ✔ Aceleración por hardware con NVIDIA NVENC.
- ✔ Cálculo dinámico del bitrate.
- ✔ Reescalado automático a 4K.
- ✔ Monitorización en tiempo real.
- ✔ Obtención de metadatos mediante TMDb y OMDb.
- ✔ Organización automática de archivos.
- ✔ Integración con Jellyfin.
- ✔ Configuración centralizada mediante `config.sh`.

### Próximas mejoras

- Documentación técnica.
- Soporte mediante Docker.
- Mejoras en la instalación.
- Optimización continua del proceso de transcodificación.```

