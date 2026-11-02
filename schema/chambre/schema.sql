-- Domaine chambre : chambre (métier porté par un nœud), faces, masques logiques, positions des conduites dans
-- les masques. Fichier attaché au noyau sous le nom « chambre ». Références vers le noyau et l'infra :
-- voir manifest.json.

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
    CHB_ROTATION    REAL,               -- orientation de la face A sur la carte (grades)
    CHB_NIVEAU      INTEGER NOT NULL DEFAULT 0 CHECK (CHB_NIVEAU IN (0, 1, 2)),  -- non relevée, partielle, complète
    CHB_COMMENT     TEXT,
    DATE_CREA       TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    DATE_MODIF      TEXT,
    SRC_MODIF       TEXT,
    DATE_ABD        TEXT,
    SRC_ABD         TEXT
);

-- Face (masque) : grille de NB_COL x NB_LIG cellules, parcourue par déplacement si elle dépasse l'écran.
CREATE TABLE CHB_FACE (
    FAC_ID          INTEGER PRIMARY KEY AUTOINCREMENT,
    CHB_KEY         INTEGER NOT NULL REFERENCES CHB_CHAMBRE (CHB_ID),
    FAC_CODE        TEXT NOT NULL CHECK (FAC_CODE IN ('A', 'B', 'C', 'D')),
    FAC_NB_COL      INTEGER,
    FAC_NB_LIG      INTEGER,
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

-- Position d'une conduite dans la face d'une chambre. Une même conduite a une position dans chacune des deux
-- chambres qu'elle relie : c'est le miroir.
CREATE TABLE CHB_POSITION (
    POS_ID          INTEGER PRIMARY KEY AUTOINCREMENT,
    FAC_KEY         INTEGER NOT NULL REFERENCES CHB_FACE (FAC_ID),
    CD_KEY          INTEGER NOT NULL,   -- infra INF_CONDUITE
    POS_X           REAL NOT NULL,      -- colonne (en cellules, depuis la gauche)
    POS_Y           REAL NOT NULL,      -- ligne (en cellules, depuis le haut)
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
