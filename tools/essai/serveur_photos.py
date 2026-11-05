"""Serveur local des photos d'un projet BE pour la version web du terminal (développement).

Le paquet transmet le chemin de chaque photo dans le projet (`FIC_CHEMIN`, ex. photos/NCY/C17480/….jpg) ; une photo
non embarquée est lue ici quand l'application est ouverte avec `?photos=<port>` (ou l'adresse complète). Seul le
dossier `photos/` du projet est servi, sur la boucle locale uniquement. Avec --paquet, le paquet de zone est aussi
servi, à l'adresse /paquet.zip : l'application ouverte avec `?paquet=<port>` (ou `--dart-define=PAQUET=<port>`) le
charge au démarrage.

Usage :
  python -I tools/essai/serveur_photos.py <dossier projet> [port, 8090 par défaut] [--paquet <paquet.zip>]
"""
import functools, http.server, os, sys

sys.stdout.reconfigure(encoding='utf-8')


class Photos(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, paquet=None, **kwargs):
        self.paquet = paquet
        super().__init__(*args, **kwargs)

    def end_headers(self):
        # page de l'application servie sur un autre port : lecture autorisée par CORS ; photos immuables, paquet relu
        # à chaque ouverture (republié entre deux lancements)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Cache-Control', 'no-store' if self.path == '/paquet.zip' else 'max-age=86400')
        super().end_headers()

    def send_head(self):
        if self.path == '/paquet.zip' and self.paquet:
            f = open(self.paquet, 'rb')
            self.send_response(200)
            self.send_header('Content-Type', 'application/zip')
            self.send_header('Content-Length', str(os.fstat(f.fileno()).st_size))
            self.end_headers()
            return f
        if not self.path.startswith('/photos/') or self.path.endswith('/'):
            self.send_error(404)
            return None
        return super().send_head()

    def log_message(self, format, *args):
        # une ligne par demande (diagnostic : l'application demande-t-elle les photos ?)
        print(f'{self.log_date_time_string()} {format % args}', flush=True)


def main():
    args = sys.argv[1:]
    paquet = None
    if '--paquet' in args:
        i = args.index('--paquet')
        paquet = args[i + 1] if i + 1 < len(args) else None
        del args[i:i + 2]
    if not args or not os.path.isdir(os.path.join(args[0], 'photos')) or (paquet is not None and
                                                                           not os.path.isfile(paquet or '')):
        print(__doc__)
        sys.exit(1)
    port = int(args[1]) if len(args) > 1 else 8090
    # sous Windows, la réutilisation d'adresse laisserait un second serveur écouter le même port
    http.server.ThreadingHTTPServer.allow_reuse_address = False
    try:
        serveur = http.server.ThreadingHTTPServer(
            ('127.0.0.1', port), functools.partial(Photos, directory=os.path.abspath(args[0]),
                                                   paquet=paquet and os.path.abspath(paquet)))
    except OSError:
        # relance depuis VS Code : le serveur précédent tourne encore
        print(f'Photos de {args[0]} : port {port} déjà occupé, serveur supposé déjà lancé (servies sur '
              f'http://localhost:{port}/)', flush=True)
        return
    if paquet:
        print(f'Paquet {paquet} servi sur http://localhost:{port}/paquet.zip (application : ?paquet={port})', flush=True)
    print(f'Photos de {args[0]} servies sur http://localhost:{port}/ (application : ?photos={port})', flush=True)
    serveur.serve_forever()


if __name__ == '__main__':
    main()
