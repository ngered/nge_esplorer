-- Référentiels propres au domaine infra (les catalogues FOA sont importés par l'outil de construction).

INSERT INTO DEF_CD_ETAT (ETAT_ID, ETAT_CODE, ETAT_LIB, ETAT_COULEUR, ETAT_FOA) VALUES
    (0, 'V',  'Vide',               '#FFFFFF', 0),
    (1, 'R',  'Réservée',           '#1E6FD9', 1),
    (2, 'X',  'Occupée',            '#F39C12', 2),
    (3, 'XR', 'Occupée et réservée', '#7FB3F5', 12),
    (4, 'M',  'Mauvaise (casse)',   '#E02424', 3);

-- CHS, TRT et FAC repris de FOA (DEF_POSEMODE) ; liste validée le 31 octobre 2026.
INSERT INTO DEF_SUPPORT_IMPLANT (IMPS_ID, IMPS_CODE, IMPS_LIB) VALUES
    (1, 'CHS', 'Chaussée'), (2, 'TRT', 'Trottoir'), (3, 'ACC', 'Accotement'),
    (4, 'TPL', 'Terre-plein'), (5, 'PRV', 'Domaine privé'), (6, 'FAC', 'Façade'), (9, 'AUT', 'Autre');
