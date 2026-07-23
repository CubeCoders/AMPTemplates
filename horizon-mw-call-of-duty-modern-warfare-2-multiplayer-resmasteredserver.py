import os
import hashlib
import requests
from urllib.parse import urljoin

# URLs
MANIFEST_URL = "https://delboy.b-cdn.net/hmw/manifest.json"
BASE_DOWNLOAD_URL = "https://delboy.b-cdn.net/hmw/"

def calculate_sha256(file_path):
    """
    Berechnet den SHA-256-Hash einer Datei.
    """
    sha256_hash = hashlib.sha256()
    try:
        with open(file_path, "rb") as f:
            for byte_block in iter(lambda: f.read(4096), b""):
                sha256_hash.update(byte_block)
        return sha256_hash.hexdigest()
    except FileNotFoundError:
        return None

def download_file(file_url, local_path):
    """
    Lädt eine Datei von der angegebenen URL herunter und speichert sie lokal.
    """
    os.makedirs(os.path.dirname(local_path), exist_ok=True)
    try:
        response = requests.get(file_url, stream=True)
        response.raise_for_status()
        with open(local_path, "wb") as f:
            for chunk in response.iter_content(chunk_size=8192):
                f.write(chunk)
        print(f"Heruntergeladen: {local_path}")
    except Exception as e:
        print(f"Fehler beim Herunterladen von {file_url}: {e}")

def process_manifest(manifest):
    """
    Verarbeitet das Manifest, überprüft und lädt Dateien bei Bedarf herunter.
    """
    for module in manifest.get("Modules", []):
        print(f"Verarbeite Modul: {module['Name']} (Version {module['Version']})")
        files_with_hashes = module.get("FilesWithHashes", {})
        download_path = module.get("DownloadInfo", {}).get("DownloadPath", "")

        for file_path, expected_hash in files_with_hashes.items():
            # Überprüft Dateien im aktuellen Ordner
            local_path = os.path.join(os.getcwd(), file_path)
            actual_hash = calculate_sha256(local_path)

            if actual_hash == expected_hash:
                print(f"Datei ist aktuell: {local_path}")
            else:
                print(f"Datei fehlt oder ist veraltet: {local_path}")
                # Download-URL basierend auf mod-1.0 erstellen
                file_url = urljoin(BASE_DOWNLOAD_URL, os.path.join(download_path, file_path).replace("\\", "/"))
                download_file(file_url, local_path)

def main():
    try:
        # Manifest.json herunterladen
        response = requests.get(MANIFEST_URL)
        response.raise_for_status()
        manifest = response.json()

        # Manifest verarbeiten
        process_manifest(manifest)

    except requests.RequestException as e:
        print(f"Fehler beim Abrufen von manifest.json: {e}")
    except ValueError as e:
        print(f"Ungültiges Format von manifest.json: {e}")

if __name__ == "__main__":
    main()
