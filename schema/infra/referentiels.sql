-- Référentiels propres au domaine infra (les catalogues FOA sont importés par l'outil de construction).

INSERT INTO DEF_CD_ETAT (ETAT_ID, ETAT_CODE, ETAT_LIB, ETAT_COULEUR, ETAT_FOA) VALUES
    (0, 'V',  'Vide',               '#FFFFFF', 0),
    (1, 'R',  'Réservée',           '#1E6FD9', 1),
    (2, 'X',  'Occupée',            '#F39C12', 2),
    (3, 'XR', 'Occupée et réservée', '#7FB3F5', 12),
    (4, 'M',  'Mauvaise (casse)',   '#E02424', 3),
    (5, 'XM', 'Occupée et mauvaise', '#9B1C1C', 32);

-- Palette des alvéoles de FOA Explorer (20 à 150 mm) ; 20 à 33 mm proposés pour le sous-tubage (menu de FOA). Diamètres
-- intérieurs de 28 à 150 mm : ceux qu'encode l'abaque d'occupation de FOA (docs/cab_occupation.csv d'Infra Explorer,
-- rapport des sections (Ø câble / Ø intérieur)²) ; 20 → 16 et 24 → 20 : à confirmer (absents de l'abaque, FOA y
-- calcule 0 %).
INSERT INTO DEF_CD_DIAM (DIAM_ID, DIAM_NOMINAL, DIAM_INT, DIAM_SOUS_TUBE) VALUES
    (1, 20, 16, 1), (2, 24, 20, 1), (3, 28, 22, 1), (4, 33, 27, 1),
    (5, 45, 38, 0), (6, 60, 50, 0), (7, 80, 70, 0), (8, 100, 90, 0), (9, 150, 140, 0);

-- CHS, TRT et FAC repris de FOA (DEF_POSEMODE) ; liste validée le 31 octobre 2026.
INSERT INTO DEF_SUPPORT_IMPLANT (IMPS_ID, IMPS_CODE, IMPS_LIB) VALUES
    (1, 'CHS', 'Chaussée'), (2, 'TRT', 'Trottoir'), (3, 'ACC', 'Accotement'),
    (4, 'TPL', 'Terre-plein'), (5, 'PRV', 'Domaine privé'), (6, 'FAC', 'Façade'), (9, 'AUT', 'Autre');
