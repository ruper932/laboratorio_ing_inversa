# Laboratorio de Ingeniería Inversa y Análisis de Tráfico Cifrado en Sistemas de Comunicaciones

## 1. Introducción

Este laboratorio tiene como objetivo demostrar los principios de **ingeniería inversa**, **análisis de tráfico de red** y **criptografía aplicada** en el contexto de sistemas de comunicaciones. Se implementa un entorno controlado donde dos entidades (contenedores A y B) establecen comunicación cifrada, mientras una tercera entidad (contenedor C) realiza interceptación pasiva del tráfico para posteriormente descifrar los mensajes mediante técnicas de ingeniería inversa.

El laboratorio se ejecuta en un host con **Arch Linux kernel LTS**, utilizando **Docker** con configuración de red en modo host (`network_mode: host`) para evitar limitaciones del kernel relacionadas con interfaces virtuales `veth`.

---

## 2. Objetivos del Laboratorio

1. Implementar un sistema de comunicación cifrada entre dos nodos utilizando criptografía simétrica (NaCl SecretBox).
2. Capturar tráfico de red cifrado mediante técnicas de sniffing pasivo.
3. Aplicar ingeniería inversa para obtener la clave y el algoritmo de cifrado.
4. Descifrar los mensajes interceptados demostrando la vulnerabilidad de sistemas con claves hardcodeadas.

---

## 3. Arquitectura del Laboratorio

### 3.1. Diagrama de Red

```
┌─────────────────────────────────────────────────────────────────────┐
│                         HOST (Arch Linux LTS)                        │
│                      Red Wi‑Fi: MiLabSec (AP Bridge)                 │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                    Red Docker (network_mode: host)            │   │
│  │                                                               │   │
│  │   ┌──────────────┐      ┌──────────────┐      ┌──────────────┐│   │
│  │   │ Container‑A  │      │ Container‑B  │      │ Container‑C  ││   │
│  │   │  (Cliente)   │─────▶│  (Servidor)  │      │  (Atacante)  ││   │
│  │   │              │      │              │      │              ││   │
│  │   │ chat_client  │      │ chat_server  │      │ tcpdump +    ││   │
│  │   │ pynacl       │◀────▶│ pynacl       │      │ decrypt.py   ││   │
│  │   │              │      │              │      │              ││   │
│  │   │ 127.0.0.1    │      │ 0.0.0.0:5000 │      │ lo sniffing  ││   │
│  │   └──────────────┘      └──────────────┘      └──────────────┘│   │
│  │          │                     │                     │         │   │
│  │          └─────────────────────┴─────────────────────┘         │   │
│  │                         Puerto 5000 (TCP)                      │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  Clientes Wi‑Fi (MiLabSec) ───────────────────────────────────────►  │
│         Pueden acceder a servicios expuestos en el host             │
└─────────────────────────────────────────────────────────────────────┘
```

### 3.2. Descripción de Componentes

| Componente       | Función                                                    |
|------------------|------------------------------------------------------------|
| **Container‑A**  | Cliente SSH + cliente de chat cifrado (pynacl)             |
| **Container‑B**  | Servidor SSH + servidor de chat cifrado (pynacl, puerto 5000) |
| **Container‑C**  | Contenedor atacante con herramientas de sniffing (tcpdump, Wireshark, scapy, pynacl) |
| **Host (Arch)**  | Ejecuta Docker, crea punto de acceso Wi‑Fi (MiLabSec), provee red compartida |

---

## 4. Fundamentos Técnicos

### 4.1. Criptografía Simétrica con NaCl SecretBox

El laboratorio utiliza la biblioteca **PyNaCl** (Python bindings para libsodium), específicamente la primitiva `SecretBox`, que implementa:

- **Cifrado autenticado**: combina cifrado simétrico (XSalsa20) con autenticación (Poly1305).
- **Clave precompartida**: 32 bytes (256 bits) que deben ser conocidos por emisor y receptor.
- **Nonce aleatorio**: generado automáticamente para cada mensaje, garantizando que cifrados repetidos del mismo plaintext produzcan ciphertexts diferentes.

**Fórmula de cifrado:**

\[
C = \\text{SecretBox}\\_K(M, N)
\]

Donde:
- \( C \): ciphertext (mensaje cifrado + MAC)
- \( M \): mensaje en claro (plaintext)
- \( K \): clave secreta de 32 bytes
- \( N \): nonce de 24 bytes (generado aleatoriamente)

### 4.2. Captura de Tráfico (Sniffing)

El contenedor C utiliza `tcpdump` para capturar paquetes TCP en la interfaz de loopback (`lo`) filtrando por puerto 5000:

```bash
tcpdump -i lo -w /tmp/lab.pcap port 5000
```

Esto captura todos los paquetes que cumplen:
- Interfaz: `lo` (localhost, ya que todos los contenedores comparten la red del host)
- Puerto: 5000 (servicio de chat cifrado)

El archivo resultante (`.pcap`) puede ser analizado posteriormente con herramientas como Wireshark, tshark o scripts personalizados con `scapy`.

### 4.3. Ingeniería Inversa

La ingeniería inversa en este contexto consiste en:

1. **Análisis estático**: examinar el código fuente o binario del cliente/servidor para identificar:
   - Algoritmo de cifrado (NaCl SecretBox)
   - Clave precompartida (hardcodeada en el código)
   - Estructura del protocolo (puerto, formato de mensajes)

2. **Análisis dinámico**: ejecutar el programa y observar su comportamiento (tráfico de red, uso de memoria, etc.)

3. **Extracción de clave**: una vez identificada la clave en el código, se utiliza para descifrar el tráfico capturado.

---

## 5. Implementación Paso a Paso

### 5.1. Preparación del Entorno

#### 5.1.1. Punto de Acceso Wi‑Fi

Se crea un punto de acceso Wi‑Fi en modo bridge utilizando `create_ap`:

```bash
sudo create_ap -m bridge wlan0 enp3s0 MiLabSec 1232456789
```

- `wlan0`: interfaz Wi‑Fi que soporta modo AP
- `enp3s0`: interfaz con conexión a Internet (compartida en modo bridge)
- `MiLabSec`: SSID de la red
- `1232456789`: contraseña WPA2

Los clientes que se conecten a `MiLabSec` estarán en la misma red que el host, permitiendo acceso a servicios expuestos.

#### 5.1.2. Configuración de Docker

Se utiliza `docker-compose.yml` con `network_mode: host` para evitar creación de interfaces `veth` (no disponibles en kernel LTS):

```yaml

services:
  container-a:
    image: alpine:latest
    container_name: container-a
    network_mode: host
    privileged: true
    cap_add:
      - NET_ADMIN
      - NET_RAW
    command: >
      sh -c "
        apk add --no-cache openssh-client tcpdump iproute2 net-tools nmap python3 py3-pip &&
        pip3 install --break-system-packages pynacl &&
        ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519 -N '' -q &&
        mkdir -p /root/.ssh &&
        cat /root/.ssh/id_ed25519.pub > /root/.ssh/authorized_keys &&
        tail -f /dev/null
      "

  container-b:
    image: alpine:latest
    container_name: container-b
    network_mode: host
    privileged: true
    cap_add:
      - NET_ADMIN
      - NET_RAW
    volumes:
      - ./chat_server.py:/root/chat_server.py:ro
    command: >
      sh -c "
        apk add --no-cache openssh-server tcpdump iproute2 net-tools nmap python3 py3-pip &&
        pip3 install --break-system-packages pynacl &&
        ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N '' -q &&
        echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config &&
        echo 'PasswordAuthentication no' >> /etc/ssh/sshd_config &&
        echo 'PubkeyAuthentication yes' >> /etc/ssh/sshd_config &&
        mkdir -p /root/.ssh &&
        cat /etc/ssh/ssh_host_ed25519_key.pub > /root/.ssh/authorized_keys &&
        /usr/sbin/sshd &&
        python3 /root/chat_server.py
      "

  container-c:
    image: kalilinux/kali-rolling
    container_name: container-c
    network_mode: host
    privileged: true
    cap_add:
      - NET_ADMIN
      - NET_RAW
    command: >
      bash -c "
        apt-get update && apt-get install -y tcpdump wireshark dsniff iproute2 net-tools nmap python3 python3-pip scapy &&
        pip3 install --break-system-packages pynacl &&
        echo 1 > /proc/sys/net/ipv4/ip_forward &&
        tail -f /dev/null
      "
```

### 5.2. Implementación del Chat Cifrado

#### 5.2.1. Servidor (chat_server.py)

```python
import socket
import nacl.secret

KEY = b"clave_secreta_de_32_bytes_exacto"
box = nacl.secret.SecretBox(KEY)

HOST = "0.0.0.0"
PORT = 5000

def main():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind((HOST, PORT))
        s.listen()
        print(f"Servidor escuchando en {HOST}:{PORT}")
        while True:
            conn, addr = s.accept()
            with conn:
                print("Conexión desde", addr)
                while True:
                    data = conn.recv(4096)
                    if not data:
                        break
                    try:
                        msg = box.decrypt(data).decode("utf-8")
                        print("Mensaje descifrado:", msg)
                        resp = box.encrypt(f"Eco: {msg}".encode("utf-8"))
                        conn.sendall(resp)
                    except Exception:
                        print("No se pudo descifrar (¿ataque?)")
                        conn.sendall(b"[ERROR] decryption failed\n")

if __name__ == "__main__":
    main()
```

#### 5.2.2. Cliente (chat_client.py)

```python
import socket
import nacl.secret

KEY = b"clave_secreta_de_32_bytes_exacto"
box = nacl.secret.SecretBox(KEY)

SERVER = "127.0.0.1"
PORT = 5000

def main():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.connect((SERVER, PORT))
        print(f"Conectado a {SERVER}:{PORT}")
        while True:
            msg = input("Mensaje: ")
            ciphertext = box.encrypt(msg.encode("utf-8"))
            s.sendall(ciphertext)
            resp = s.recv(4096)
            try:
                plaintext = box.decrypt(resp).decode("utf-8")
                print("Respuesta:", plaintext)
            except Exception:
                print("No se pudo descifrar la respuesta.")

if __name__ == "__main__":
    main()
```

### 5.3. Captura y Descifrado (Container‑C)

#### 5.3.1. Script Automatizado (lab_mitm.sh)

```bash
#!/usr/bin/env bash
set -e

echo "=== Laboratorio de Ingenieria Inversa - Sniffing + Descifrado ==="

# Activar IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward
echo "[+] IP forwarding activado"

# Limpiar pcap previo
rm -f /tmp/lab.pcap

# Iniciar captura
echo "[*] Iniciando captura en puerto 5000..."
tcpdump -i lo -w /tmp/lab.pcap port 5000 &
TCPDUMP_PID=$!

echo "[*] Enviando mensajes desde el cliente (presiona Enter cuando termines)..."
read -p "Presiona Enter cuando hayas terminado..."

# Detener captura
echo "[*] Deteniendo captura..."
kill $TCPDUMP_PID 2>/dev/null || true
wait $TCPDUMP_PID 2>/dev/null || true

# Verificar pcap
if [ ! -f /tmp/lab.pcap ]; then
    echo "[-] Error: no se generó el pcap"
    exit 1
fi

echo "[+] Captura guardada en /tmp/lab.pcap"
ls -lh /tmp/lab.pcap

# Script de descifrado
cat > /root/decrypt.py << 'PYEOF'
from scapy.all import rdpcap, TCP
import nacl.secret

KEY = b"clave_secreta_de_32_bytes_exacto"
box = nacl.secret.SecretBox(KEY)

pkts = rdpcap("/tmp/lab.pcap")

print("\n=== Mensajes descifrados ===")
for p in pkts:
    if TCP in p and (p[TCP].dport == 5000 or p[TCP].sport == 5000):
        payload = bytes(p[TCP].payload)
        if not payload:
            continue
        try:
            msg = box.decrypt(payload).decode("utf-8")
            print("Mensaje descifrado:", msg)
        except Exception:
            pass
print("\n=== Fin ===")
PYEOF

# Ejecutar descifrado
echo "[*] Descifrando mensajes..."
python3 /root/decrypt.py

echo "[+] Laboratorio completado"
```

---

## 6. Análisis de Resultados

### 6.1. Tráfico Capturado

El archivo `lab.pcap` contiene paquetes TCP con payloads cifrados. Cada paquete incluye:

- **Header Ethernet/IP/TCP**: información de red (direcciones IP, puertos, secuencias, etc.)
- **Payload cifrado**: datos encriptados con NaCl SecretBox (ciphertext + nonce + MAC)

### 6.2. Descifrado Exitoso

Al ejecutar `decrypt.py`, se obtienen los mensajes originales:

```text
=== Mensajes descifrados ===
Mensaje descifrado: hola
Mensaje descifrado: este es un mensaje de prueba
Mensaje descifrado: laboratorio de ingenieria inversa
=== Fin ===
```

Esto demuestra que:

1. El sniffing pasivo fue exitoso.
2. La clave hardcodeada permitió el descifrado.
3. El protocolo es vulnerable si el atacante obtiene acceso al código/binario.

---

## 7. Consideraciones de Seguridad

### 7.1. Vulnerabilidades Demostradas

1. **Claves hardcodeadas**: cualquier atacante con acceso al código puede extraer la clave.
2. **Sin intercambio de claves dinámico**: no hay mecanismo como Diffie-Hellman para generar claves efímeras.
3. **Sniffing pasivo**: el tráfico puede ser capturado sin necesidad de ataques activos (ARP spoofing, MITM).

### 7.2. Mejoras Recomendadas

1. **Intercambio de claves seguro**: usar protocolos como TLS, Signal, o Diffie-Hellman.
2. **Almacenamiento seguro de claves**: usar sistemas de gestión de secretos (HashiCorp Vault, AWS Secrets Manager).
3. **Cifrado de extremo a extremo**: garantizar que solo los extremos puedan descifrar, no intermediarios.
4. **Detección de sniffing**: implementar técnicas para detectar anomalías en la red (latencia, duplicación de paquetes).

---

## 8. Conclusiones

Este laboratorio demuestra de manera práctica los conceptos de:

- **Criptografía simétrica aplicada** en comunicaciones de red.
- **Captura de tráfico** mediante herramientas estándar (tcpdump, scapy).
- **Ingeniería inversa** para extraer claves y algoritmos de software.
- **Vulnerabilidades de seguridad** en sistemas con implementaciones ingenuas de cifrado.

Para la materia de **Sistemas de Comunicaciones**, este ejercicio ilustra la importancia de diseñar protocolos seguros desde el inicio, considerando no solo el cifrado, sino también la gestión de claves, la autenticación y la protección contra ataques pasivos y activos.

---

## 9. Referencias

1. NaCl Library: https://nacl.cr.yp.to/
2. PyNaCl Documentation: https://pynacl.readthedocs.io/
3. tcpdump Manual: https://www.tcpdump.org/
4. Scapy Documentation: https://scapy.readthedocs.io/
5. Docker Networking: https://docs.docker.com/network/

---

**Entorno**: Arch Linux LTS, Docker, Python 3, PyNaCl, Scapy
