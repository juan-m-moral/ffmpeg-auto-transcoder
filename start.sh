#!/usr/bin/env bash

cd "$(dirname "$0")" || exit 1

echo
echo "Iniciando FFmpeg Auto Transcoder..."
echo

nohup ./procesar.sh >/mnt/dd2/logs/nohup.log 2>&1 &

sleep 1

./monitor.sh
