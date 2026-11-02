-- Référentiels du noyau. Les types, entités et vues propres aux modules viennent de leurs manifestes.

INSERT INTO DEF_TYPE (TYPE_ID, TYPE_CODE, TYPE_LIB, TYPE_PARENT_KEY, TYPE_GEOM, MOD_CODE, GRACE_CODE) VALUES
    (3,    'INF', 'Support d''infrastructure', NULL, 'POINT',      NULL, NULL),
    (999,  'AUT', 'Autre point',               NULL, 'POINT',      NULL, 'Z'),
    (1000, 'LIN', 'Linéaire',                  NULL, 'LINESTRING', NULL, NULL);

INSERT INTO DEF_AVANCEMENT (AVCT_ID, AVCT_CODE, AVCT_LIB) VALUES
    (1, 'E', 'Existant'), (2, 'C', 'À créer'), (3, 'T', 'Travaux'),
    (4, 'S', 'En service'), (5, 'H', 'Hors service'), (6, 'A', 'Abandonné');

INSERT INTO DEF_IMPLANTATION (IMPL_ID, IMPL_CODE, IMPL_LIB) VALUES
    (0, '0', 'Aérien télécom'), (1, '1', 'Aérien énergie'), (2, '2', 'Façade'), (3, '3', 'Immeuble'),
    (4, '4', 'Pleine terre'), (5, '5', 'Caniveau'), (6, '6', 'Galerie'), (7, '7', 'Conduite'),
    (8, '8', 'Égout'), (9, '9', 'Spécifique');

INSERT INTO DEF_GEOL_CLASSE (CLASSE_ID, CLASSE_CODE, CLASSE_LIB) VALUES
    (1, 'A', 'Classe de précision A'), (2, 'AP', 'Classe A, en planimétrie uniquement'),
    (3, 'B', 'Classe de précision B'), (4, 'C', 'Classe de précision C');

-- codes GraceTHD v2, plus TERM (position GPS du terminal, NgeEsPlorer)
INSERT INTO DEF_GEOL_MODE (GMOD_ID, GMOD_CODE, GMOD_LIB) VALUES
    (1, 'LTRO', 'Levé durant la pose'), (2, 'LVIS', 'Levé après la pose'), (3, 'DETC', 'Levé avec détection'),
    (4, 'FDPL', 'Cotation par rapport à un levé de géomètre'),
    (5, 'CBDU', 'Cotation par rapport à un fond de plan tiers type BDU'),
    (6, 'CADA', 'Positionnement sur cadastre'),
    (7, 'ORTO', 'Positionnement sur orthophotographie ou fond de plan cartographique'),
    (8, 'INDT', 'Indéterminé'), (9, 'TERM', 'Position GPS du terminal');
