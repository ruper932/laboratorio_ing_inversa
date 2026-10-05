import socket
import nacl.secret

KEY = b"clave_secreta_de_32_bytes_exacto"
box = nacl.secret.SecretBox(KEY)

SERVER = "127.0.0.1"
PORT = 5000

def main():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.connect((SERVER, PORT))
        print(f"Conectado al servidor {SERVER}:{PORT}")
        while True:
            msg = input("Mensaje a enviar (Ctrl+C para salir): ")
            ciphertext = box.encrypt(msg.encode("utf-8"))
            s.sendall(ciphertext)
            resp = s.recv(4096)
            try:
                plaintext = box.decrypt(resp).decode("utf-8")
                print("Respuesta del servidor:", plaintext)
            except Exception:
                print("No se pudo descifrar la respuesta.")

if __name__ == "__main__":
    main()
