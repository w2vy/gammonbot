#!/usr/bin/python
'''This module is a single file that supports the loading of secrets into a Flux Node'''
import binascii
import json
import sys
import os
import time
import socketserver
import threading
import socket
import requests
from Crypto.PublicKey import RSA
from Crypto.Random import get_random_bytes
from Crypto.Cipher import AES, PKCS1_OAEP

VAULT_NAME = ""
BOOTFILES = []
FILE_DIR = ""

MAX_MESSAGE = 8192

def encrypt_data(keypem, data):
    '''Used by the Vault to create and send a AES session key protected by RSA'''
    key = RSA.import_key(keypem)
    session_key = get_random_bytes(16)
    # Encrypt the session key with the public RSA key
    cipher_rsa = PKCS1_OAEP.new(key)
    enc_session_key = cipher_rsa.encrypt(session_key)

    # Encrypt the data with the AES session key
    cipher_aes = AES.new(session_key, AES.MODE_EAX)
    ciphertext, tag = cipher_aes.encrypt_and_digest(data)

    msg = {
        "enc_session_key":enc_session_key.hex(),
        "nonce": cipher_aes.nonce.hex(),
        "tag": tag.hex(),
        "cipher": ciphertext.hex()
    }
    return msg

def decrypt_data(keypem, cipher):
    '''Used by Node to decrypt the Session key'''
    private_key = RSA.import_key(keypem)
    enc_session_key = bytes.fromhex(cipher["enc_session_key"])
    nonce = bytes.fromhex(cipher["nonce"])
    tag = bytes.fromhex(cipher["tag"])
    ciphertext = bytes.fromhex(cipher["cipher"])

    # Decrypt the session key with the private RSA key
    cipher_rsa = PKCS1_OAEP.new(private_key)
    session_key = cipher_rsa.decrypt(enc_session_key)

    # Decrypt the data with the AES session key
    cipher_aes = AES.new(session_key, AES.MODE_EAX, nonce)
    data = cipher_aes.decrypt_and_verify(ciphertext, tag)
    return data

def send_aeskey(keypem, aeskey):
    '''Encrypt data with the AES key to be sent'''
    message = encrypt_data(keypem, aeskey)
    return message

def receive_aeskey(keypem, message):
    '''Decrypt received data using teh AES key'''
    cipher = json.loads(message)
    data = decrypt_data(keypem, cipher)
    data = data.decode("utf-8")
    return data

def decrypt_aes_data(key, data):
    '''Decrypt data with AES key'''
    jdata = json.loads(data)
    nonce = bytes.fromhex(jdata["nonce"])
    tag = bytes.fromhex(jdata["tag"])
    ciphertext = bytes.fromhex(jdata["ciphertext"])

    # let's assume that the key is somehow available again
    cipher = AES.new(key, AES.MODE_EAX, nonce)
    msg = cipher.decrypt_and_verify(ciphertext, tag)
    return json.loads(msg)

def encrypt_aes_data(key, message):
    '''Encrypt message with AES key'''
    msg = json.dumps(message)
    cipher = AES.new(key, AES.MODE_EAX)
    ciphertext, tag = cipher.encrypt_and_digest(msg.encode("utf-8"))
    jdata = {
        "nonce": cipher.nonce.hex(),
        "tag": tag.hex(),
        "ciphertext": ciphertext.hex()
    }
    data = json.dumps(jdata)
    return data

def send_receive(sock, request):
    '''Send and receive a message'''
    request += "\n"

    try:
        sock.sendall(request.encode("utf-8"))
    except socket.error:
        print('Send failed')
        sys.exit()

    # Receive data
    reply = sock.recv(MAX_MESSAGE)
    reply = reply.decode("utf-8")
    return reply

def receive_only(sock):
    '''Receive a message'''
    # Receive data
    reply = sock.recv(MAX_MESSAGE)
    reply = reply.decode("utf-8")
    return reply

CONNECTED = "CONNECTED"
KEYSENT = "KEYSENT"
STARTAES = "STARTAES"
READY = "READY"
REQUEST = "REQUEST"
DONE = "DONE"
AESKEY = "AESKEY"

 # A server program which accepts requests from clients to capitalize strings. When
 # clients connect, a new thread is started to handle a client. The receiving of the
 # client data, the capitalizing, and the sending back of the data is handled on the
 # worker thread, allowing much greater throughput because more clients can be handled
 # concurrently.

def create_send_public_key(nkdata):
    '''
    # New incoming connection from Vault
    # Create a new RSA key and send the Public Key the Vault
    # We appear to ignore any initial data
    '''
    nkdata["RSAkey"] = RSA.generate(2048)
    nkdata["Private"] = nkdata["RSAkey"].export_key()
    nkdata["Public"] = nkdata["RSAkey"].publickey().export_key()
    nkdata["State"] = KEYSENT
    jdata = { "State": KEYSENT, "PublicKey": nkdata["Public"].decode("utf-8")}
    reply = json.dumps(jdata) + "\n"
    return reply

def file_request_or_done(nkdata, boot_files, data):
    '''Create File Request or Done message'''
    if len(data) == 0:
        jdata = {"State": READY}
    else:
        jdata = decrypt_aes_data(nkdata["AESKEY"], data)
    if jdata["State"] == "DATA":
        if jdata["Status"] == "Success":
            open(FILE_DIR+boot_files[0], "w").write(jdata["Body"])
        boot_files.pop(0)
    # Send request for first (or next file)
    # If no more we are Done (close connection?)
    random = get_random_bytes(16).hex()
    if len(boot_files) == 0:
        jdata = { "State": DONE, "fill": random }
    else:
        try:
            content = open(FILE_DIR+boot_files[0]).read()
            crc = binascii.crc32(content.encode("utf-8"))
            # File exists
        except FileNotFoundError:
            crc = 0
        jdata = { "State": REQUEST,
                    "FILE": boot_files[0],
                    "crc32": crc, "fill": random }
    reply = encrypt_aes_data(nkdata["AESKEY"], jdata)
    return reply

class ThreadedTCPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    '''Define threaded server'''
    daemon_threads = True
    allow_reuse_address = True

class NodeKeyClient(socketserver.StreamRequestHandler):
    '''Server Thread one per connection'''
    def handle(self):
        client = f'{self.client_address} on {threading.currentThread().getName()}'
        print(f'Connected: {client}')
        peer_ip = self.connection.getpeername()
        result = socket.gethostbyname(VAULT_NAME)
        if peer_ip[0] != result:
            print("Reject Connection, wrong IP:", peer_ip[0], result)
            time.sleep(15)
            return
        nkdata = { "State": CONNECTED }
        # Copy file list into local variable
        boot_files = BOOTFILES.copy()

        while True:
            try:
                reply = ""
                if nkdata["State"] == CONNECTED:
                    reply = create_send_public_key(nkdata)
                    self.wfile.write(reply.encode("utf-8"))
                    continue
                data = self.rfile.readline()
                if not data:
                    break
                if nkdata["State"] == KEYSENT:
                    jdata = json.loads(data)
                    if jdata["State"] != AESKEY:
                        break # Tollerate no errors
                    nkdata["AESKEY"] = decrypt_data(nkdata["Private"], jdata)
                    nkdata["State"] = STARTAES
                    random = get_random_bytes(16).hex()
                    jdata = { "State": STARTAES, "Text": "Test", "fill": random}
                    reply = encrypt_aes_data(nkdata["AESKEY"], jdata) + "\n"
                    self.wfile.write(reply.encode("utf-8"))
                    continue
                if nkdata["State"] == STARTAES:
                    jdata = decrypt_aes_data(nkdata["AESKEY"], data)
                    if jdata["State"] == STARTAES and jdata["Text"] == "Passed":
                        nkdata["State"] = READY # We are good to go!
                        data = ""
                    else:
                        break # Failed
                if nkdata["State"] == READY:
                    reply = file_request_or_done(nkdata, boot_files, data) +"\n"
                    self.wfile.write(reply.encode("utf-8"))
                    continue
                break # Unhandled case, abort
            except ValueError:
                print("try failed")
                break
        print(f'Closed: {client}')

def node_server(port, vaultname, bootfiles, base):
    '''This server runs on the Node, waiting for the Vault to connect'''
    global VAULT_NAME
    global BOOTFILES
    global FILE_DIR

    VAULT_NAME = vaultname
    BOOTFILES = bootfiles
    FILE_DIR = base
    print("node_server ", VAULT_NAME)
    if len(BOOTFILES) > 0:
        with ThreadedTCPServer(('', port), NodeKeyClient) as server:
            print("The NodeKeyClient server is running on port " + str(port))
            server.serve_forever()
    else:
        print("BOOTFILES missing from comamnd line, see usage")

def open_connection(port, appip):
    '''Open socket to Node'''
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    except socket.error:
        print('Failed to create socket')
        return None

    try:
        remote_ip = socket.gethostbyname( appip )
    except socket.gaierror:
        print('Hostname could not be resolved')
        return None

    # Set short timeout
    sock.settimeout(5)

    # Connect to remote serverAESData
    try:
        print('# Connecting to server, ' + appip + ' (' + remote_ip + ')')
        sock.connect((remote_ip , port))
    except ConnectionRefusedError:
        print("connection refused")
        sock.close()
        return None
    except socket.timeout:
        print("Connect timed out")
        sock.close()
        return None

    sock.settimeout(None)
    return sock

def send_files(sock, jdata, aeskey, file_dir):
    '''Send files to node'''
    while True:
        data = encrypt_aes_data(aeskey, jdata)
        reply = send_receive(sock, data)
        jdata = decrypt_aes_data(aeskey, reply)
        reply = ""
        if jdata["State"] == DONE:
            break
        if jdata["State"] == REQUEST:
            fname = jdata["FILE"]
            crc = int(jdata["crc32"])
            jdata["State"] = "DATA"
            try:
                secret = open(file_dir+fname).read()
                mycrc = binascii.crc32(secret.encode("utf-8"))
                if crc == mycrc:
                    print("File ", fname, " Match!")
                    jdata["Status"] = "Match"
                    jdata["Body"] = ""
                else:
                    print("File ", fname, " sent!")
                    jdata["Body"] = secret
                    jdata["Status"] = "Success"
            except FileNotFoundError:
                print("File Not Found: " + file_dir+fname)
                jdata["Body"] = ""
                jdata["Status"] = "FileNotFound"
        else:
            jdata["Body"] = ""
            jdata["Status"] = "Unknown Command"

def node_vault_ip(port, appip, file_dir):
    '''We have a node try sending it config data'''

    sock = open_connection(port, appip)
    if sock is None:
        return
    
    reply = receive_only(sock)

    try:
        jdata = json.loads(reply)
        public_key = jdata["PublicKey"].encode("utf-8")
    except ValueError:
        print("No Public Key received:", reply)
        return
    # Generate and send AES Key encrypted with PublicKey
    aeskey = get_random_bytes(16).hex().encode("utf-8")
    jdata = send_aeskey(public_key, aeskey)
    jdata["State"] = AESKEY
    data = json.dumps(jdata)
    reply = send_receive(sock, data)
    # AES Encryption should be started now
    jdata = decrypt_aes_data(aeskey, reply)
    if jdata["State"] != STARTAES:
        print("StartAES not found")
        return
    if jdata["Text"] != "Test":
        print("StartAES Failed")
        return
    jdata["Text"] = "Passed"

    send_files(sock, jdata, aeskey, file_dir)
    sock.close()
    return

def node_vault(port, appname, file_dir):
    '''Vault runs this to poll every node running their app'''
    url = "https://api.runonflux.io/apps/location/" + appname
    req = requests.get(url)
    if req.status_code == 200:
        values = json.loads(req.text)
        if values["status"] == "success":
            nodes = values["data"]
            for node in nodes:
                ipadr = node['ip'].split(':')[0]
                print(node['name'], ipadr)
                node_vault_ip(port, ipadr, file_dir)
        else:
            print("Error", req.text)
    else:
        print("Error", url, "Status", req.status_code)

def usage(argv):
    '''Display command usage'''
    print("Usage:")
    print(argv[0] + " Node --port port --vault VaultDomain [--dir dirname] file1 [file2 file3 ...]")
    print("")
    print("Run on node with the port and Domain/IP of the Vault and the list of files")
    print("")
    print(argv[0] + " Vault --port port --app AppName --dir dirname")
    print("")
    print("Run on Vault the AppName will be used to get the list of nodes where the App is running")
    print("The vault will connect to each node : Port and provide the files requested")
    print("")
    print(argv[0] + " VaultIP --port port --ip IPadr [--dir dirname]")
    print("")
    print("The Vault will connect to a single ip : Port to provide files")
    print("")

# node_server port VaultDomain
# node_vault port NodeIP

NODE_OPTS = ["--port", "--vault", "--dir"]
VAULT_OPTS = ["--port", "--app", "--ip", "--dir"]

def main():
    '''Main function'''
    files = []
    myport = -1
    vault = ""
    base_dir = ""
    ipadr = ""
    app_name = ""
    error = False

    if sys.argv[1].upper() == "NODE":
        args = sys.argv[2:]
        while len(args) > 0:
            if args[0] in NODE_OPTS:
                if args[0].lower() == "--port":
                    try:
                        myport = int(args[1])
                        args.pop(0)
                        args.pop(0)
                        continue
                    except ValueError:
                        print(args[1] + " invalid port number")
                        sys.exit()
                if args[0].lower() == "--vault":
                    vault = args[1]
                    args.pop(0)
                    args.pop(0)
                    continue
                if args[0].lower() == "--dir":
                    base_dir = args[1]
                    if base_dir.endswith("/") is False:
                        base_dir = base_dir + "/"
                    args.pop(0)
                    args.pop(0)
                    continue
            else:
                files = args
                break
        if len(base_dir) > 0 and os.path.isdir(base_dir) is False:
            print(base_dir + " is not a directory or does not exist")
            error = True
        if myport == -1:
            print("Port number must be specified like --port 31234")
            error = True
        if len(vault) == 0:
            print("Vault Domain or IP must be set like:",
                " --vault 1.2.3.4 or --vault my.vault.host.io")
            error = True
        if len(files) == 0:
            print("Secret files must be listed after all other arguments")
            error = True
        if error is True:
            usage(sys.argv)
        else:
            node_server(myport, vault, files, base_dir)
        sys.exit()

    if sys.argv[1].upper() == "VAULT":
        args = sys.argv[2:]
        while len(args) > 0:
            if args[0] in VAULT_OPTS:
                if args[0].lower() == "--port":
                    try:
                        myport = int(args[1])
                        args.pop(0)
                        args.pop(0)
                        continue
                    except ValueError:
                        print(args[1] + " invalid port number")
                        sys.exit()
                if args[0].lower() == "--app":
                    app_name = args[1]
                    args.pop(0)
                    args.pop(0)
                    continue
                if args[0].lower() == "--ip":
                    ipadr = args[1]
                    args.pop(0)
                    args.pop(0)
                    continue
                if args[0].lower() == "--dir":
                    base_dir = args[1]
                    if base_dir.endswith("/") is False:
                        base_dir = base_dir + "/"
                    args.pop(0)
                    args.pop(0)
                    continue
            else:
                print("Unknown option: ", args[0])
                args.pop(0)
        if len(base_dir) > 0 and os.path.isdir(base_dir) is False:
            print(base_dir + " is not a directory or does not exist")
            error = True
        if myport == -1:
            print("Port number must be specified like --port 31234")
            error = True
        if len(app_name) == 0 and len(ipadr) == 0:
            print("Application Name OR IP must be set but not Both!",
                " like: --appname myapp or --ip 2.3.45.6")
            error = True
        if len(app_name) > 0 and len(ipadr) > 0:
            print("Application Name OR IP must be set but not Both!",
                " like: --appname myapp or --ip 2.3.45.6")
            error = True
        if error is True:
            usage(sys.argv)
        else:
            if len(app_name) > 0:
                node_vault(myport, app_name, base_dir)
            else:
                node_vault_ip(myport, ipadr, base_dir)
        sys.exit()

main()
