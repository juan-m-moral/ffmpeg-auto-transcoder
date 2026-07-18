# FFmpeg Auto Transcoder

Sistema automático de transcodificación de películas mediante FFmpeg y NVIDIA NVENC.

El servicio permanece en ejecución continuamente, detecta nuevas películas automáticamente y las procesa sin intervención del usuario. Incluye un monitor en tiempo real para consultar el estado de la codificación.

El proyecto nace con el objetivo de automatizar por completo el procesamiento de una biblioteca de películas. Analiza cada vídeo, calcula automáticamente el bitrate más adecuado, procesa el contenido a HEVC (H.265), lo reescala a 4K cuando es necesario, conserva la información multimedia original y organiza el resultado para su integración en una biblioteca Jellyfin.

Además, obtiene automáticamente información desde TMDb y OMDb para renombrar las películas y preparar la biblioteca para Jellyfin.

Todo el proceso está pensado para ejecutarse de forma desatendida, incluyendo monitorización en tiempo real, registro de errores y organización automática de los archivos.

Este proyecto ha sido desarrollado con un enfoque práctico, priorizando la automatización, la estabilidad y la facilidad de mantenimiento sobre la complejidad innecesaria.

---

## Características

- Transcodificación automática mediante FFmpeg.
- Aceleración por GPU NVIDIA (NVENC).
- Espera permanente de nuevas películas.
- Inicio automático mediante systemd.
- Monitor independiente en tiempo real.
- Cálculo de ETA y progreso.
- Información de GPU (uso, temperatura, VRAM, encoder...).
- Conservación de audio y subtítulos.
- Obtención automática de metadatos desde TMDb y OMDb.
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

## Instalación del servicio

Copiar el servicio:

```bash
sudo cp procesar.service /etc/systemd/system/
```

Recargar systemd:

```bash
sudo systemctl daemon-reload
```

Activarlo para que arranque con el sistema:

```bash
sudo systemctl enable procesar.service
```

Iniciarlo:

```bash
sudo systemctl start procesar.service
```

---

## Administración del servicio

Consultar estado:

```bash
systemctl status procesar.service
```

Detener:

```bash
sudo systemctl stop procesar.service
```

Iniciar:

```bash
sudo systemctl start procesar.service
```

Reiniciar:

```bash
sudo systemctl restart procesar.service
```

---

## Monitor

El monitor es completamente independiente del servicio.

Puede abrirse y cerrarse en cualquier momento:

```bash
./monitor.sh
```

No es necesario iniciarlo al arrancar el servicio. Puede ejecutarse en cualquier momento para consultar el estado del transcodificador.

El monitor distingue tres estados:

- Servicio detenido.
- Esperando nuevas películas.
- Codificando una película.

## Configuración

Toda la configuración del proyecto se encuentra centralizada en el archivo:

```text
config.sh
```

---


## Estructura del proyecto

```text
ffmpeg-auto-transcoder/
│
├── config.sh              Configuración general
├── procesar.sh            Motor principal de transcodificación
├── monitor.sh             Monitor en tiempo real
├── procesar.service      Servicio systemd
├── tmdb.sh                Acceso a la API de TMDb
├── omdb.sh                Acceso a la API de OMDb
├── Dockerfile             Imagen Docker
├── docker-compose.yml     Despliegue mediante Docker
├── README.md              Documentación principal
├── .gitignore             Exclusiones de Git
│
└── docs/                  Documentación adicional (próximamente)
```

---

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

## Funcionamiento continuo

Una vez instalado el servicio mediante systemd, el transcodificador permanece siempre en ejecución.

Cuando detecta una nueva película en el directorio de entrada, inicia automáticamente el proceso de análisis y codificación.

Al finalizar vuelve al modo espera sin necesidad de intervención del usuario.

El monitor puede ejecutarse en cualquier momento para consultar el estado del servicio y de la codificación.

## Organización de directorios

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
```

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

Esta estructura permite mantener organizada la biblioteca multimedia y facilita la recuperación ante posibles errores durante el proceso.
---

## Estado del proyecto

El proyecto es plenamente funcional y continúa en desarrollo para incorporar nuevas características y optimizaciones.


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
- ✔ Ejecución permanente mediante systemd.

### Próximas mejoras

- Documentación técnica.
- Soporte mediante Docker.
- Instalador automático.
- Optimización continua del proceso de transcodificación.```

