-- Référentiels du domaine optique, repris des listes GraceTHD v2.0.1 (libellés en clair).

INSERT INTO DEF_OPT_EQUIP_TYPE (OTYP_ID, OTYP_CODE, OTYP_LIB) VALUES
    (1, 'BPE', 'Boîtier de protection d''épissures'), (2, 'PBO', 'Point de branchement optique'),
    (3, 'PTO', 'Point de terminaison optique'), (4, 'DTI', 'Dispositif de terminaison intérieur optique'),
    (5, 'BAIE', 'Baie'), (6, 'TIROIR', 'Tiroir optique');

INSERT INTO DEF_CAB_FONCTION (CFON_ID, CFON_CODE, CFON_LIB) VALUES
    (1, 'CO', 'Collecte'), (2, 'CT', 'Collecte et transport'), (3, 'CD', 'Collecte et distribution'),
    (4, 'CX', 'Collecte, transport et distribution'), (5, 'TR', 'Transport'), (6, 'TD', 'Transport et distribution'),
    (7, 'DI', 'Distribution'), (8, 'RA', 'Raccordement final'), (9, 'BM', 'Boucle métropolitaine'),
    (10, 'LH', 'Longue distance'), (99, 'NC', 'Non communiqué');

-- standard Orange (GraceTHD l_fo_color 1 à 12)
INSERT INTO DEF_FO_COULEUR (COUL_ID, COUL_CODE, COUL_LIB, COUL_RGB) VALUES
    (1, 'R', 'Rouge', '#FF0000'), (2, 'BL', 'Bleu', '#0070C0'), (3, 'VE', 'Vert', '#92D050'),
    (4, 'J', 'Jaune', '#FFFF00'), (5, 'V', 'Violet', '#7638A3'), (6, 'B', 'Blanc', '#FFFFFF'),
    (7, 'OR', 'Orange', '#FFC000'), (8, 'GR', 'Gris', '#C1C1C1'), (9, 'BR', 'Marron', '#993300'),
    (10, 'N', 'Noir', '#000000'), (11, 'TU', 'Turquoise', '#00B0F0'), (12, 'RS', 'Rose', '#FF65CC');

INSERT INTO DEF_CASSETTE_TYPE (CTYP_ID, CTYP_CODE, CTYP_LIB) VALUES
    (1, 'P', 'Plateau de lovage'), (2, 'E', 'Épissures'), (3, 'S', 'Coupleur'), (4, 'C', 'Connecteurs');

INSERT INTO DEF_POS_FONCTION (PFON_ID, PFON_CODE, PFON_LIB) VALUES
    (1, 'EP', 'Épissure'), (2, 'PA', 'Passage'), (3, 'AT', 'Attente'), (4, 'CO', 'Connecteur'), (5, 'PI', 'Pigtail');

INSERT INTO DEF_MES_METHODE (MMET_ID, MMET_CODE, MMET_LIB) VALUES
    (1, 'OTDR', 'Réflectométrie'), (2, 'PHOTO', 'Photométrie (puissance)'), (3, 'PERTE', 'Perte d''insertion');
