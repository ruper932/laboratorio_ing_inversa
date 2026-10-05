#!/usr/bin/env bash
set -e

echo "Creando punto de acceso Wi‑Fi (canal 6, 2.4 GHz)..."
sudo create_ap -m bridge -c 6 wlan0 enp3s0 MiLabSec 1232456789
