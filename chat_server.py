import socket
import nacl.secret

# Clave precompartida (32 bytes exactos)
KEY = b"clave_secreta_de_32_bytes_exacto"
box = nacl.secret.SecretBox(KEY)

HOST = "0.0.0.0"
PORT = 5000

def main():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind((HOST, PORT))
        s.listen()
        print(f"Servidor de chat cifrado escuchando en {HOST}:{PORT}")
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
                        # Respuesta cifrada
                        resp = box.encrypt(f"Eco: {msg}".encode("utf-8"))
                        conn.sendall(resp)
                    except Exception:
                        print("No se pudo descifrar el mensaje (¿ataque?)")
                        conn.sendall(b"[ERROR] decryption failed\n")

if __name__ == "__main__":
    main()