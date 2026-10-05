#!/usr/bin/env bash
# =============================================================================
# LABORATORIO DE INGENIERÍA INVERSA - SNIFFING Y DESCIFRADO DE TRÁFICO CIFRADO
# =============================================================================
# Este script automatiza un ataque Man-in-the-Middle (MitM) pasivo en un 
# entorno controlado. Demuestra cómo un atacante puede:
#   1. Capturar tráfico cifrado de red
#   2. Obtener la clave de cifrado mediante ingeniería inversa
#   3. Descifrar los mensajes interceptados
#
# MATERIA: Sistemas de Comunicaciones
# AUTOR: Laboratorio de Ciberseguridad
# FECHA: Octubre 2026
# =============================================================================

set -e  # Detener el script si algún comando falla

# -----------------------------------------------------------------------------
# COLOR Y FORMATO PARA SALIDAS
# -----------------------------------------------------------------------------
# Definimos códigos de color ANSI para hacer la salida más legible
RED='\033[0;31m'      # Rojo para errores
GREEN='\033[0;32m'    # Verde para éxitos
YELLOW='\033[1;33m'   # Amarillo para advertencias
BLUE='\033[0;34m'     # Azul para información
CYAN='\033[0;36m'     # Cyan para títulos
NC='\033[0m'          # Reset (volver al color normal)

# Función para imprimir mensajes con formato
print_header() {
    echo -e "${CYAN}"
    echo "============================================================================="
    echo -e "$1"
    echo "============================================================================="
    echo -e "${NC}"
}

print_step() {
    echo -e "${BLUE}[*]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[+]${NC} $1"
}

print_error() {
    echo -e "${RED}[-]${NC} $1"
}

print_info() {
    echo -e "${YELLOW}[i]${NC} $1"
}

# =============================================================================
# INICIO DEL SCRIPT
# =============================================================================

print_header "LABORATORIO DE INGENIERÍA INVERSA - SNIFFING + DESCIFRADO"

# -----------------------------------------------------------------------------
# PASO 1: ACTIVAR IP FORWARDING
# -----------------------------------------------------------------------------
print_step "PASO 1: Activando IP forwarding en el kernel..."
print_info "El IP forwarding permite que el sistema reenvíe paquetes entre interfaces."
print_info "Esto es necesario para ataques Man-in-the-Middle (MitM) activos."
print_info "En este laboratorio usamos sniffing pasivo, pero lo activamos por completitud."

echo 1 > /proc/sys/net/ipv4/ip_forward

# Verificamos que se activó correctamente
if [ "$(cat /proc/sys/net/ipv4/ip_forward)" = "1" ]; then
    print_success "IP forwarding activado correctamente (valor: 1)"
else
    print_error "No se pudo activar IP forwarding"
    exit 1
fi

echo ""

# -----------------------------------------------------------------------------
# PASO 2: LIMPIAR CAPTURA PREVIA
# -----------------------------------------------------------------------------
print_step "PASO 2: Limpiando archivos de captura previos..."

if [ -f /tmp/lab.pcap ]; then
    print_info "Se encontró un archivo pcap previo: /tmp/lab.pcap"
    print_info "Eliminándolo para evitar mezclar capturas de diferentes sesiones..."
    rm -f /tmp/lab.pcap
    print_success "Archivo previo eliminado"
else
    print_info "No hay archivos pcap previos que limpiar"
fi

echo ""

# -----------------------------------------------------------------------------
# PASO 3: INICIAR CAPTURA DE TRÁFICO CON TCPDUMP
# -----------------------------------------------------------------------------
print_step "PASO 3: Iniciando captura de tráfico de red..."
print_info "Usaremos tcpdump para capturar paquetes en la interfaz de loopback (lo)"
print_info "Filtro: solo paquetes TCP en el puerto 5000 (servicio de chat cifrado)"
print_info ""
print_info "Comando: tcpdump -i lo -w /tmp/lab.pcap port 5000"
print_info "  -i lo       : Interfaz de loopback (localhost)"
print_info "  -w FILE     : Escribir paquetes en archivo (formato pcap)"
print_info "  port 5000   : Filtrar solo tráfico en puerto 5000"
echo ""

# Iniciamos tcpdump en segundo plano (&) y guardamos su PID
tcpdump -i lo -w /tmp/lab.pcap port 5000 &
TCPDUMP_PID=$!

print_success "tcpdump iniciado en segundo plano (PID: $TCPDUMP_PID)"
print_info "La captura está activa. Ahora debes generar tráfico cifrado."
echo ""

# -----------------------------------------------------------------------------
# PASO 4: ESPERAR QUE EL USUARIO GENERE TRÁFICO
# -----------------------------------------------------------------------------
print_header "GENERANDO TRÁFICO CIFRADO"

print_info "INSTRUCCIONES:"
echo "  1. Abre OTRA terminal en tu host"
echo "  2. Ejecuta el cliente de chat:"
echo "     docker exec -it container-a python3 /root/chat_client.py"
echo "  3. Envía al menos 3 mensajes (ej: 'hola', 'prueba', 'laboratorio')"
echo "  4. Presiona Ctrl+C en el cliente cuando termines"
echo "  5. Vuelve a esta terminal y presiona ENTER"
echo ""

read -p ">>> Presiona ENTER cuando hayas terminado de enviar mensajes... "

print_info "Usuario confirmó. Deteniendo la captura..."
echo ""

# -----------------------------------------------------------------------------
# PASO 5: DETENER TCPDUMP
# -----------------------------------------------------------------------------
print_step "PASO 5: Deteniendo la captura de tráfico..."

# Enviamos señal SIGTERM al proceso tcpdump
kill $TCPDUMP_PID 2>/dev/null || true

# Esperamos a que termine completamente (asegura que el archivo se cierre bien)
wait $TCPDUMP_PID 2>/dev/null || true

print_success "Captura detenida correctamente"
echo ""

# -----------------------------------------------------------------------------
# PASO 6: VERIFICAR ARCHIVO CAPTURADO
# -----------------------------------------------------------------------------
print_step "PASO 6: Verificando archivo de captura..."

if [ ! -f /tmp/lab.pcap ]; then
    print_error "ERROR: No se generó el archivo /tmp/lab.pcap"
    print_info "Posibles causas:"
    echo "  - No se envió tráfico durante la captura"
    echo "  - tcpdump no pudo escribir en /tmp/"
    echo "  - El puerto 5000 no tiene tráfico"
    exit 1
fi

# Mostramos información del archivo
PCAP_SIZE=$(ls -lh /tmp/lab.pcap | awk '{print $5}')
print_success "Archivo de captura generado: /tmp/lab.pcap"
print_info "Tamaño del archivo: $PCAP_SIZE"

# Mostramos estadísticas básicas con tcpdump
echo ""
print_info "Mostrando resumen de paquetes capturados:"
tcpdump -r /tmp/lab.pcap -q 2>/dev/null | head -5 || print_info "(No se pudo leer el pcap)"

echo ""

# -----------------------------------------------------------------------------
# PASO 7: INGENIERÍA INVERSA - OBTENCIÓN DE LA CLAVE
# -----------------------------------------------------------------------------
print_header "INGENIERÍA INVERSA - OBTENCIÓN DE LA CLAVE PRECOMPARTIDA"

print_info "En un escenario real, un atacante obtendría la clave mediante:"
echo "  1. Análisis estático del código fuente o binario"
echo "  2. Uso de herramientas como: strings, radare2, ghidra, objdump"
echo "  3. Búsqueda de cadenas constantes en el binario"
echo "  4. Análisis de llamadas a funciones criptográficas"
echo ""

print_info "SIMULACIÓN DE INGENIERÍA INVERSA:"
print_info "=================================="
echo ""

print_step "Paso 7.1: Analizando el código del servidor (chat_server.py)..."
print_info "Buscamos patrones de inicialización de cifrado..."
echo ""

# Simulamos el proceso de análisis estático
print_info "Comando simulado: grep -n 'SecretBox' chat_server.py"
echo ""
echo "  Línea encontrada:"
echo "  ─────────────────────────────────────────────────────────────────"
echo "  5: KEY = b"clave_secreta_de_32_bytes_exacto""
echo "  6: box = nacl.secret.SecretBox(KEY)"
echo "  ─────────────────────────────────────────────────────────────────"
echo ""

print_success "¡CLAVE ENCONTRADA EN EL CÓDIGO!"
echo ""

print_info "Análisis de la clave:"
echo "  - Tipo: Bytes (prefijo 'b' en Python)"
echo "  - Longitud: 32 bytes (256 bits)"
echo "  - Algoritmo: NaCl SecretBox (XSalsa20 + Poly1305)"
echo "  - Vulnerabilidad: Clave HARDCODEADA en el código fuente"
echo ""

print_info "En un escenario real, usaríamos:"
echo "  $ strings chat_server.py | grep -A 2 -B 2 'clave'"
echo "  O con ghidra/radare2 para binarios compilados"
echo ""

# Guardamos la clave "descubierta" en una variable
CLAVE_DESCUBIERTA="clave_secreta_de_32_bytes_exacto"

print_success "Clave extraída: $CLAVE_DESCUBIERTA"
echo ""

read -p ">>> Presiona ENTER para continuar con el descifrado... "

echo ""

# -----------------------------------------------------------------------------
# PASO 8: CREAR SCRIPT DE DESCIFRADO CON LA CLAVE OBTENIDA
# -----------------------------------------------------------------------------
print_step "PASO 8: Creando script de descifrado con la clave obtenida..."

cat > /root/decrypt.py << PYEOF
#!/usr/bin/env python3
# =============================================================================
# SCRIPT DE DESCIFRADO - INGENIERÍA INVERSA APLICADA
# =============================================================================
# Este script descifra mensajes capturados usando la clave obtenida mediante
# ingeniería inversa del código del servidor/cliente.
#
# ALGORITMO: NaCl SecretBox (XSalsa20 para cifrado + Poly1305 para autenticación)
# CLAVE: 32 bytes (256 bits) - obtenida del análisis estático del código
# =============================================================================

from scapy.all import rdpcap, TCP
import nacl.secret
import sys

# -----------------------------------------------------------------------------
# CLAVE OBTENIDA MEDIANTE INGENIERÍA INVERSA
# -----------------------------------------------------------------------------
# Esta clave fue extraída del análisis del código fuente chat_server.py
# Línea: KEY = b"clave_secreta_de_32_bytes_exacto"
# -----------------------------------------------------------------------------
KEY = b"clave_secreta_de_32_bytes_exacto"

print(f"[*] Inicializando SecretBox con clave: {KEY}")
print(f"[*] Longitud de clave: {len(KEY)} bytes ({len(KEY)*8} bits)")

# Creamos el objeto SecretBox con la clave
try:
    box = nacl.secret.SecretBox(KEY)
    print("[+] SecretBox inicializado correctamente")
except Exception as e:
    print(f"[-] Error al inicializar SecretBox: {e}")
    sys.exit(1)

# -----------------------------------------------------------------------------
# LECTURA DEL ARCHIVO CAPTURADO
# -----------------------------------------------------------------------------
PCAP_FILE = "/tmp/lab.pcap"

print(f"\n[*] Leyendo archivo capturado: {PCAP_FILE}")

try:
    pkts = rdpcap(PCAP_FILE)
    print(f"[+] Se leyeron {len(pkts)} paquetes del archivo")
except Exception as e:
    print(f"[-] Error al leer el pcap: {e}")
    sys.exit(1)

# -----------------------------------------------------------------------------
# PROCESAMIENTO Y DESCIFRADO DE PAQUETES
# -----------------------------------------------------------------------------
print("\n" + "="*70)
print("INICIANDO DESCIFRADO DE MENSAJES")
print("="*70)

mensajes_encontrados = 0
mensajes_fallidos = 0

for i, p in enumerate(pkts):
    # Filtramos solo paquetes TCP
    if TCP not in p:
        continue

    # Filtramos solo paquetes del puerto 5000 (chat cifrado)
    if p[TCP].dport != 5000 and p[TCP].sport != 5000:
        continue

    # Extraemos el payload (datos) del paquete TCP
    payload = bytes(p[TCP].payload)

    # Saltamos paquetes sin datos (ej: solo handshakes TCP, ACKs vacíos)
    if not payload:
        continue

    # Intentamos descifrar el payload
    try:
        # decrypt() lanza excepción si el MAC no coincide o el formato es inválido
        msg = box.decrypt(payload).decode("utf-8")

        # Si llegamos aquí, el descifrado fue exitoso
        mensajes_encontrados += 1
        print(f"\n[PAQUETE {i}] Mensaje descifrado:")
        print(f"  Dirección: {p[IP].src}:{p[TCP].sport} -> {p[IP].dst}:{p[TCP].dport}")
        print(f"  Payload crudo (hex): {payload[:50].hex()}...")
        print(f"  MENSAJE: {msg}")

    except Exception as e:
        # El descifrado falló (posible ruido, handshake, o datos no cifrados)
        mensajes_fallidos += 1
        # print(f"[PAQUETE {i}] No se pudo descifrar: {e}")  # Comentado para no saturar

# -----------------------------------------------------------------------------
# RESUMEN FINAL
# -----------------------------------------------------------------------------
print("\n" + "="*70)
print("RESUMEN DEL DESCIFRADO")
print("="*70)
print(f"Paquetes totales en el pcap: {len(pkts)}")
print(f"Paquetes procesados (puerto 5000 con datos): {mensajes_encontrados + mensajes_fallidos}")
print(f"Mensajes descifrados exitosamente: {mensajes_encontrados}")
print(f"Mensajes que fallaron al descifrar: {mensajes_fallidos}")
print("="*70)

if mensajes_encontrados == 0:
    print("\n[!] ADVERTENCIA: No se pudo descifrar ningún mensaje")
    print("Posibles causas:")
    print("  - La clave es incorrecta")
    print("  - El tráfico capturado no es del protocolo esperado")
    print("  - Los paquetes no contienen payloads cifrados válidos")
else:
    print("\n[+] ¡INGENIERÍA INVERSA EXITOSA!")
    print("[+] Se recuperaron mensajes originales del tráfico cifrado")

print("\n" + "="*70)
PYEOF

print_success "Script de descifrado creado: /root/decrypt.py"
echo ""

# -----------------------------------------------------------------------------
# PASO 9: EJECUTAR DESCIFRADO
# -----------------------------------------------------------------------------
print_step "PASO 9: Ejecutando script de descifrado..."
echo ""

python3 /root/decrypt.py

# -----------------------------------------------------------------------------
# PASO 10: MENSAJE FINAL Y CONCLUSIONES
# -----------------------------------------------------------------------------
echo ""
print_header "LABORATORIO COMPLETADO"

print_success "El laboratorio de ingeniería inversa ha finalizado correctamente"
echo ""

print_info "CONCLUSIONES DEL LABORATORIO:"
echo "  1. El sniffing pasivo permite capturar TODO el tráfico de red"
echo "  2. El cifrado por sí solo NO es suficiente si la clave es débil"
echo "  3. Las claves hardcodeadas en el código son VULNERABLES"
echo "  4. La ingeniería inversa puede extraer secretos de binarios"
echo ""

print_info "RECOMENDACIONES DE SEGURIDAD:"
echo "  ✓ Usar intercambio de claves seguro (Diffie-Hellman, TLS)"
echo "  ✓ No hardcodear claves en el código fuente"
echo "  ✓ Usar sistemas de gestión de secretos (Vault, AWS Secrets)"
echo "  ✓ Implementar cifrado de extremo a extremo real"
echo "  ✓ Realizar auditorías de código y análisis de binarios"
echo ""

print_info "ARCHIVOS GENERADOS:"
echo "  - /tmp/lab.pcap      : Captura de tráfico cifrado"
echo "  - /root/decrypt.py   : Script de descifrado con la clave obtenida"
echo ""

print_success "¡Laboratorio de Ingeniería Inversa completado!"
