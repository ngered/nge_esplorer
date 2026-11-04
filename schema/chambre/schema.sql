-- Domaine chambre : chambre (métier porté par un nœud), faces, masques logiques, positions des conduites dans
-- les masques. Fichier attaché au noyau sous le nom « chambre ». Références vers le noyau et l'infra :
-- voir manifest.json. Commentaires de la chambre : journal du noyau (PRJ_COMMENTAIRE), rattaché au nœud.
-- Repère des masques (depuis la 0.3.0) : dimensions des faces et positions en m, voir schema/README.md.

CREATE TABLE MAT_CHAMBRE (              -- FOA MAT_CHAMBRE (dimensions en m)
    MAT_ID          INTEGER PRIMARY KEY,
    MAT_LIB         TEXT NOT NULL,      -- type (L1T, L2C, P3T…)
    FAB_KEY         INTEGER,            -- noyau DEF_FABRICANT
    POSE_KEY        INTEGER,            -- infra DEF_POSE
    CHB_TYPE_CODE   TEXT,
    CHB_LNG_EXT     REAL,
    CHB_LARG_EXT    REAL,
    CHB_HAUT_EXT    REAL,
    CHB_LNG_INT     REAL,
    CHB_LARG_INT    REAL,
    CHB_HAUT_INT    REAL
);

CREATE TABLE CHB_CHAMBRE (
    CHB_ID          INTEGER PRIMARY KEY AUTOINCREMENT,
    NOE_KEY         INTEGER NOT NULL UNIQUE,    -- noyau PRJ_NOE
    MAT_KEY         INTEGER REFERENCES MAT_CHAMBRE (MAT_ID),
    PROPRIO_KEY     INTEGER,            -- noyau DEF_ORGANISME
    GEST_KEY        INTEGER,            -- noyau DEF_ORGANISME
    IMPS_KEY        INTEGER,            -- infra DEF_SUPPORT_IMPLANT
    CHB_LNG         REAL,               -- dimensions relevées si elles diffèrent du catalogue (m)
    CHB_LARG        REAL,
    CHB_HAUT        REAL,
    CHB_ROTATION    REAL,               -- rotation FOA (attribut ROTATION du bloc AutoCAD FT_Chambre du PIT) en
                                        -- grades : axe A-B de la chambre à 200 grades près, sans dire quel bout est A
    CHB_NIVEAU      INTEGER NOT NULL DEFAULT 0 CHECK (CHB_NIVEAU IN (0, 1, 2)),  -- non relevée, partielle, complète
    DATE_CREA       TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    DATE_MODIF      TEXT,
    SRC_MODIF       TEXT,
    DATE_ABD        TEXT,
    SRC_ABD         TEXT
);

-- Face (masque) : paroi de FAC_LARG x FAC_HAUT m. Convention Orange (docs/Besoins_KIZEO.xlsx), dos à la voie :
-- A à gauche, B à droite, C côté voie (« dos route »), D en face (« face route ») ; chambre le long de la voie : A et B
-- petits côtés. A et B ont la largeur de la chambre, C et D sa longueur ; hauteur = hauteur (profondeur) de la
-- chambre. Face relevée dans FOA Explorer : fenêtre de dessin de FOA, 0,567 x 0,54 m.
CREATE TABLE CHB_FACE (
    FAC_ID          INTEGER PRIMARY KEY AUTOINCREMENT,
    CHB_KEY         INTEGER NOT NULL REFERENCES CHB_CHAMBRE (CHB_ID),
    FAC_CODE        TEXT NOT NULL CHECK (FAC_CODE IN ('A', 'B', 'C', 'D')),
    FAC_LARG        REAL NOT NULL CHECK (FAC_LARG > 0),     -- largeur (m)
    FAC_HAUT        REAL NOT NULL CHECK (FAC_HAUT > 0),     -- hauteur (m)
    FAC_COMMENT     TEXT,
    DATE_CREA       TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    DATE_MODIF      TEXT,
    SRC_MODIF       TEXT,
    UNIQUE (CHB_KEY, FAC_CODE)
);

-- Masque logique : groupe d'alvéoles repéré par une couleur (FOA PRJ_CHB_MLOGIC).
CREATE TABLE CHB_MASQUE_LOGIQUE (
    MLOG_ID         INTEGER PRIMARY KEY AUTOINCREMENT,
    CHB_KEY         INTEGER NOT NULL REFERENCES CHB_CHAMBRE (CHB_ID),
    MLOG_NUM        INTEGER NOT NULL,
    MLOG_LIB        TEXT,
    MLOG_COULEUR    TEXT,               -- #RRGGBB
    DATE_CREA       TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    DATE_MODIF      TEXT,
    SRC_MODIF       TEXT,
    UNIQUE (CHB_KEY, MLOG_NUM)
);

-- Position d'une conduite dans la face d'une chambre : centre de l'alvéole, en m depuis le bord gauche et depuis le
-- bord haut de la face. Une même conduite a une position dans chacune des deux chambres qu'elle relie : c'est le
-- miroir.
CREATE TABLE CHB_POSITION (
    POS_ID          INTEGER PRIMARY KEY AUTOINCREMENT,
    FAC_KEY         INTEGER NOT NULL REFERENCES CHB_FACE (FAC_ID),
    CD_KEY          INTEGER NOT NULL,   -- infra INF_CONDUITE
    POS_X           REAL NOT NULL,      -- centre de l'alvéole depuis le bord gauche de la face (m)
    POS_Y           REAL NOT NULL,      -- centre de l'alvéole depuis le bord haut de la face (m)
    MLOG_KEY        INTEGER REFERENCES CHB_MASQUE_LOGIQUE (MLOG_ID),
    POS_MIROIR      INTEGER NOT NULL DEFAULT 0 CHECK (POS_MIROIR IN (0, 1)),   -- créée en appliquant le miroir
    DATE_CREA       TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    DATE_MODIF      TEXT,
    SRC_MODIF       TEXT,
    DATE_ABD        TEXT,
    SRC_ABD         TEXT,
    UNIQUE (FAC_KEY, CD_KEY)
);

CREATE INDEX IX_CHB_MAT ON CHB_CHAMBRE (MAT_KEY);
CREATE INDEX IX_FAC_CHB ON CHB_FACE (CHB_KEY);
CREATE INDEX IX_MLOG_CHB ON CHB_MASQUE_LOGIQUE (CHB_KEY);
CREATE INDEX IX_POS_FAC ON CHB_POSITION (FAC_KEY);
CREATE INDEX IX_POS_CD ON CHB_POSITION (CD_KEY);
CREATE INDEX IX_POS_MLOG ON CHB_POSITION (MLOG_KEY);
