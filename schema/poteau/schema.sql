-- Domaine poteau : poteau (métier porté par un nœud) et contrôles. Les portées et les câbles portés relèvent
-- du domaine infra (INF_PORTEE, INF_PORTEE_CABLE). Fichier attaché au noyau sous le nom « poteau ».
-- Références vers le noyau et l'infra : voir manifest.json. Commentaires du poteau : journal du noyau
-- (PRJ_COMMENTAIRE), rattaché au nœud.

CREATE TABLE DEF_POT_NAT (              -- FOA DEF_POT_NAT : nature (bois, métal…)
    NAT_ID          INTEGER PRIMARY KEY,
    NAT_LIB         TEXT NOT NULL
);

CREATE TABLE DEF_POT_STRUCT (           -- FOA DEF_POT_TYPE : structure (simple, moisé, couplé…)
    STRUCT_ID       INTEGER PRIMARY KEY,
    STRUCT_LIB      TEXT NOT NULL
);

CREATE TABLE DEF_POT_CARAC (            -- FOA DEF_POT_CARAC : ancré, hauban double…
    CARAC_ID        INTEGER PRIMARY KEY,
    CARAC_LIB       TEXT NOT NULL
);

CREATE TABLE MAT_POTEAU (               -- FOA MAT_POTEAU (catalogue, dont références GESPOT et COMAC)
    MAT_ID          INTEGER PRIMARY KEY,
    MAT_LIB         TEXT NOT NULL,      -- type (BS7, BC6 ANC…)
    MAT_DESC        TEXT,               -- référence lisible (« Bois BS7 Bois simple »)
    MAT_NAT         TEXT,
    MAT_CLASS       TEXT,
    MAT_STRUCT      TEXT,
    MAT_HAUT        REAL,
    MAT_EFF         REAL,
    CAR_TYPE        TEXT,
    CAR_ANCRE       INTEGER,
    CAR_HAUBAN      INTEGER,
    CAR_HAUBDBL     INTEGER,
    CAR_ENTRET      REAL,
    CAR_ENTRET_MIN  REAL,
    CAR_ENTRET_MAX  REAL,
    CAPFT_LIB       TEXT,
    GES_LIB         TEXT,
    GES_TYPE        TEXT,
    GES_NATURE      TEXT,
    GES_CARAC       TEXT
);

CREATE TABLE POT_POTEAU (
    POT_ID          INTEGER PRIMARY KEY AUTOINCREMENT,
    NOE_KEY         INTEGER NOT NULL UNIQUE,    -- noyau PRJ_NOE
    MAT_KEY         INTEGER REFERENCES MAT_POTEAU (MAT_ID),
    NAT_KEY         INTEGER REFERENCES DEF_POT_NAT (NAT_ID),
    STRUCT_KEY      INTEGER REFERENCES DEF_POT_STRUCT (STRUCT_ID),
    CARAC_KEY       INTEGER REFERENCES DEF_POT_CARAC (CARAC_ID),
    PROPRIO_KEY     INTEGER,            -- noyau DEF_ORGANISME
    GEST_KEY        INTEGER,            -- noyau DEF_ORGANISME
    IMPS_KEY        INTEGER,            -- infra DEF_SUPPORT_IMPLANT
    POT_HAUTEUR     REAL,               -- m
    POT_EFFORT      REAL,               -- daN
    POT_ANNEE       INTEGER,
    POT_HAUT_FT     REAL,               -- hauteur des câbles télécom (m)
    POT_BRAN_BT     TEXT,               -- branchement BT
    POT_ANG_CARTO   REAL,               -- axe du poteau (azimut en grades), pour son symbole
    POT_GESPOT_MAJ  INTEGER CHECK (POT_GESPOT_MAJ IN (0, 1)),
    POT_NIVEAU      INTEGER NOT NULL DEFAULT 0 CHECK (POT_NIVEAU IN (0, 1, 2)),
    DATE_CREA       TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    DATE_MODIF      TEXT,
    SRC_MODIF       TEXT,
    DATE_ABD        TEXT,
    SRC_ABD         TEXT
);

-- Contrôle d'un poteau (FOA PRJ_POT_NOE : CTL_*, ENV_*, SEC_*) ; 1 = conforme / oui, 0 = non, NULL = non vu.
CREATE TABLE POT_CONTROLE (
    CTL_ID              INTEGER PRIMARY KEY AUTOINCREMENT,
    POT_KEY             INTEGER NOT NULL REFERENCES POT_POTEAU (POT_ID),
    DATE_CTL            TEXT NOT NULL,
    CTL_VISUEL          INTEGER CHECK (CTL_VISUEL IN (0, 1)),
    CTL_PERCUSSION      INTEGER CHECK (CTL_PERCUSSION IN (0, 1)),
    CTL_SECOUSSE        INTEGER CHECK (CTL_SECOUSSE IN (0, 1)),
    CTL_POINTE_CARREE   INTEGER CHECK (CTL_POINTE_CARREE IN (0, 1)),
    CTL_TETE            INTEGER CHECK (CTL_TETE IN (0, 1)),
    ENV_SURPLOMB        INTEGER CHECK (ENV_SURPLOMB IN (0, 1)),
    ENV_ELAGAGE         INTEGER CHECK (ENV_ELAGAGE IN (0, 1)),
    ENV_NACELLE         INTEGER CHECK (ENV_NACELLE IN (0, 1)),
    ENV_BITUME          INTEGER CHECK (ENV_BITUME IN (0, 1)),
    SEC_VOISIN_ERDF     INTEGER CHECK (SEC_VOISIN_ERDF IN (0, 1)),
    SEC_FLAMBEMENT      INTEGER CHECK (SEC_FLAMBEMENT IN (0, 1)),
    SEC_VERTICALITE     INTEGER CHECK (SEC_VERTICALITE IN (0, 1)),
    SEC_ETIQUETTE       INTEGER CHECK (SEC_ETIQUETTE IN (0, 1)),
    SEC_UTILISABLE      INTEGER CHECK (SEC_UTILISABLE IN (0, 1)),
    CTL_COMMENT         TEXT,
    DATE_CREA           TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    DATE_MODIF          TEXT,
    SRC_MODIF           TEXT,
    DATE_ABD            TEXT,
    SRC_ABD             TEXT
);

CREATE INDEX IX_POT_MAT ON POT_POTEAU (MAT_KEY);
CREATE INDEX IX_CTL_POT ON POT_CONTROLE (POT_KEY);
