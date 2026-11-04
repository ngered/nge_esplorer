-- Référentiels du domaine immeuble, repris des listes GraceTHD v2.0.1 (libellés en clair).

INSERT INTO DEF_IMB_HABITAT (HAB_ID, HAB_CODE, HAB_LIB) VALUES (1, 'P', 'Pavillon'), (2, 'I', 'Immeuble');

INSERT INTO DEF_IMB_ETAT (IETAT_ID, IETAT_CODE, IETAT_LIB) VALUES
    (1, 'CI', 'Cible'), (2, 'SI', 'Signé'), (3, 'EC', 'En cours de déploiement'), (4, 'DE', 'Déployé'),
    (5, 'AB', 'Abandonné');

INSERT INTO DEF_LOC_TYPE (LTYP_ID, LTYP_CODE, LTYP_LIB) VALUES
    (1, 'R', 'Résidentiel'), (2, 'P', 'Professionnel'), (3, 'O', 'Opérateur'), (4, 'T', 'Technique');

INSERT INTO DEF_LOC_RACCO (RACCO_ID, RACCO_CODE, RACCO_LIB) VALUES
    (1, 'PR', 'Programmé'), (2, 'RD', 'Raccordable sur demande'), (3, 'RB', 'Raccordable'), (4, 'EL', 'Éligible'),
    (5, 'EM', 'Éligible mutualisé'), (6, 'RA', 'Raccordé'), (7, 'AB', 'Abonné');
