#!/usr/bin/env bash

cd "$(dirname "$0")" || exit 1

echo
echo "Iniciando FFmpeg Auto Transcoder..."
echo

if ! pgrep -f "[p]rocesar.sh" >/dev/null; then
    nohup ./procesar.sh >/mnt/dd2/logs/nohup.log 2>&1 &
else
    echo "Procesar ya está en ejecución."
fi

sleep 1

exec ./monitor.sh
