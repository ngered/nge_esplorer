"""Serveur local des photos d'un projet BE pour la version web du terminal (développement).

Le paquet transmet le chemin de chaque photo dans le projet (`FIC_CHEMIN`, ex. photos/NCY/C17480/….jpg) ; une photo
non embarquée est lue ici quand l'application est ouverte avec `?photos=<port>` (ou l'adresse complète). Seul le
dossier `photos/` du projet est servi, sur la boucle locale uniquement.

Usage :
  python -I tools/essai/serveur_photos.py <dossier projet> [port, 8090 par défaut]
"""
import functools, http.server, os, sys

sys.stdout.reconfigure(encoding='utf-8')


class Photos(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        # page de l'application servie sur un autre port : lecture autorisée par CORS ; photos immuables
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Cache-Control', 'max-age=86400')
        super().end_headers()

    def send_head(self):
        if not self.path.startswith('/photos/') or self.path.endswith('/'):
            self.send_error(404)
            return None
        return super().send_head()

    def log_message(self, format, *args):
        # une ligne par demande (diagnostic : l'application demande-t-elle les photos ?)
        print(f'{self.log_date_time_string()} {format % args}', flush=True)


def main():
    if len(sys.argv) < 2 or not os.path.isdir(os.path.join(sys.argv[1], 'photos')):
        print(__doc__)
        sys.exit(1)
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 8090
    # sous Windows, la réutilisation d'adresse laisserait un second serveur écouter le même port
    http.server.ThreadingHTTPServer.allow_reuse_address = False
    try:
        serveur = http.server.ThreadingHTTPServer(
            ('127.0.0.1', port), functools.partial(Photos, directory=os.path.abspath(sys.argv[1])))
    except OSError:
        # relance depuis VS Code : le serveur précédent tourne encore
        print(f'Photos de {sys.argv[1]} : port {port} déjà occupé, serveur supposé déjà lancé (servies sur '
              f'http://localhost:{port}/)', flush=True)
        return
    print(f'Photos de {sys.argv[1]} servies sur http://localhost:{port}/ (application : ?photos={port})', flush=True)
    serveur.serve_forever()


if __name__ == '__main__':
    main()
