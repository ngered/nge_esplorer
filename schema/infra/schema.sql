-- Domaine infra : parcours souterrain (conduites, sous-tubage, occupation par câbles), parcours aérien
-- (portées, câbles portés), matériel posé sur les supports, catalogues de câbles et d'équipements.
-- Fichier attaché au noyau sous le nom « infra ». Les références vers le noyau (…_KEY vers PRJ_NOE,
-- PRJ_LINEAIRE, DEF_FABRICANT) ne sont pas déclarées en SQL : elles figurent dans manifest.json.

-- Référentiels --------------------------------------------------------------------------------

CREATE TABLE DEF_CD_ETAT (              -- état d'une alvéole ou d'un tube (FOA : 1 R, 2 X, 12 XR, 3 M)
    ETAT_ID         INTEGER PRIMARY KEY,
    ETAT_CODE       TEXT NOT NULL UNIQUE,
    ETAT_LIB        TEXT NOT NULL,
    ETAT_COULEUR    TEXT NOT NULL,
    ETAT_FOA        INTEGER         -- valeur ALV_ETAT de FOA Explorer
);

CREATE TABLE DEF_SUPPORT_IMPLANT (      -- implantation d'un support (chambre, poteau)
    IMPS_ID         INTEGER PRIMARY KEY,
    IMPS_CODE       TEXT NOT NULL UNIQUE,
    IMPS_LIB        TEXT NOT NULL
);

CREATE TABLE DEF_POSE (                 -- FOA DEF_POSEMODE
    POSE_ID         INTEGER PRIMARY KEY,
    POSE_LIB        TEXT NOT NULL,
    POSE_CODE       TEXT
);

CREATE TABLE MAT_CAB_COMAC (            -- FOA MAT_CAB_COMAC (paramètres de calcul COMAC)
    COMAC_ID        INTEGER PRIMARY KEY,
    COMAC_CODE      TEXT,
    COMAC_NOM       TEXT NOT NULL,
    COMAC_TYPE      TEXT,
    COMAC_VOLT      TEXT,
    DIAMETRE        REAL,
    SECTION_REELLE  REAL,
    SECTION_NOMINALE REAL,
    MASSE_LINEIQUE  REAL,
    MODULE_YOUNG    REAL,
    COEFF_DILATATION REAL,
    CHARGE_RUPT_NOMINALE REAL,
    TENSION_CONS_RIGIDE_AGGLO REAL,
    TENSION_CONS_RIGIDE_ECART REAL,
    PARAM_CONSEILLE_SUSPENDU REAL,
    TENSION_CONS_RIGIDE_AGGLO_ZVF REAL,
    TENSION_CONS_RIGIDE_ECART_ZVF REAL,
    PARAM_CONS_SUSPENDU_ZVF REAL,
    AUTRE_PARAM_ZVF REAL,
    AUTRE_PARAM_ZVN1 REAL,
    AUTRE_PARAM_ZVN2 REAL,
    ELEMENT_DE_BASE INTEGER,
    CACHE           INTEGER
);

CREATE TABLE MAT_CABLE (                -- FOA MAT_CABLE
    MAT_ID          INTEGER PRIMARY KEY,
    MAT_LIB         TEXT NOT NULL,
    MAT_REF         TEXT,
    FAB_KEY         INTEGER,        -- noyau DEF_FABRICANT
    CAB_NB_FIB      INTEGER,
    CAB_MODULO      TEXT,
    CAB_TYPE        TEXT,
    CAB_USAGE       TEXT CHECK (CAB_USAGE IN ('RESEAU', 'BRANCHEMENT')),  -- indicatif (trait de la rosace)
    POSE_KEY        INTEGER REFERENCES DEF_POSE (POSE_ID),
    COMAC_KEY       INTEGER REFERENCES MAT_CAB_COMAC (COMAC_ID),   -- rapproché par le nom du câble
    COMAC_FOA       INTEGER,        -- FOA COMAC_KEY d'origine (pointe vers une table COMAC plus complète)
    COD_COUL_FOA    INTEGER,        -- FOA COD_COUL_KEY (code couleur fibres, domaine optique)
    FIBTYPE_FOA     INTEGER,        -- FOA FIBTYPE_KEY (type de fibre, domaine optique)
    FIC_FOA         INTEGER         -- FOA FIC_KEY
);

CREATE TABLE MAT_EQUIP (                -- FOA MAT_EQUIP (boîtes, manchons…)
    MAT_ID          INTEGER PRIMARY KEY,
    MAT_LIB         TEXT NOT NULL,
    MAT_REF         TEXT,
    FAB_KEY         INTEGER,        -- noyau DEF_FABRICANT
    POSE_KEY        INTEGER REFERENCES DEF_POSE (POSE_ID),
    MAT_LARG        REAL,
    MAT_LONG        REAL,
    MAT_HAUT        REAL,
    MAT_NBPORTS     INTEGER,
    MAT_CAPAK7      INTEGER,
    MAT_CAPAEPIS    INTEGER,
    TYPE_FOA        INTEGER         -- FOA TYPE_KEY (DEF_ALLTYPES), non repris dans DEF_TYPE
);

-- Parcours souterrain -------------------------------------------------------------------------

-- Alvéole ou tube : portée par le linéaire qui relie deux nœuds ; un sous-tube a pour parent son alvéole.
CREATE TABLE INF_CONDUITE (
    CD_ID           INTEGER PRIMARY KEY AUTOINCREMENT,
    CD_CODE_EXT     TEXT NOT NULL UNIQUE,
    LIN_KEY         INTEGER NOT NULL,   -- noyau PRJ_LINEAIRE
    CD_PARENT_KEY   INTEGER REFERENCES INF_CONDUITE (CD_ID),
    CD_NUM          INTEGER,
    CD_DIAM         REAL,               -- diamètre nominal (mm)
    ETAT_KEY        INTEGER REFERENCES DEF_CD_ETAT (ETAT_ID),
    CD_OCCUP        REAL,               -- taux d'occupation (%)
    CD_COMMENT      TEXT,
    DATE_CREA       TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    DATE_MODIF      TEXT,
    SRC_MODIF       TEXT,
    DATE_ABD        TEXT,
    SRC_ABD         TEXT
);

-- Occupation d'une conduite : câbles constatés (non identifiés individuellement).
CREATE TABLE INF_CD_CABLE (
    CDC_ID          INTEGER PRIMARY KEY AUTOINCREMENT,
    CD_KEY          INTEGER NOT NULL REFERENCES INF_CONDUITE (CD_ID),
    MAT_KEY         INTEGER REFERENCES MAT_CABLE (MAT_ID),
    CDC_NB          INTEGER NOT NULL DEFAULT 1,
    CDC_DIAM        REAL,               -- diamètre constaté (mm)
    CDC_COMMENT     TEXT,
    DATE_CREA       TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    DATE_MODIF      TEXT,
    SRC_MODIF       TEXT,
    DATE_ABD        TEXT,
    SRC_ABD         TEXT
);

-- Parcours aérien -----------------------------------------------------------------------------

-- Portée : détail aérien d'un linéaire ; angles relevés sur la rosace de chaque extrémité, orientée au nord
-- (azimut en grades, 0 = nord, sens horaire).
CREATE TABLE INF_PORTEE (
    PRT_ID          INTEGER PRIMARY KEY AUTOINCREMENT,
    LIN_KEY         INTEGER NOT NULL UNIQUE,    -- noyau PRJ_LINEAIRE
    PRT_ANG1        REAL CHECK (PRT_ANG1 >= 0 AND PRT_ANG1 < 400),     -- au nœud NOE1
    PRT_ANG2        REAL CHECK (PRT_ANG2 >= 0 AND PRT_ANG2 < 400),     -- au nœud NOE2
    PRT_LNG         REAL,
    PRT_COMMENT     TEXT,
    DATE_CREA       TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    DATE_MODIF      TEXT,
    SRC_MODIF       TEXT,
    DATE_ABD        TEXT,
    SRC_ABD         TEXT
);

-- Câbles portés (données COMAC, guide Enedis-MOP-RES_010E). Nappe : câbles d'une même traverse sur la portée
-- (3 traverses télécom au plus sur un appui Enedis). Tension : standard selon la zone (agglomération, écart),
-- ou flèche réelle relevée avec la température ambiante (portée molle). Question ouverte : longueur par câble
-- ou par portée.
CREATE TABLE INF_PORTEE_CABLE (
    PCB_ID          INTEGER PRIMARY KEY AUTOINCREMENT,
    PRT_KEY         INTEGER NOT NULL REFERENCES INF_PORTEE (PRT_ID),
    PCB_RANG        INTEGER NOT NULL,
    MAT_KEY         INTEGER REFERENCES MAT_CABLE (MAT_ID),
    PCB_LNG         REAL,
    PCB_NAPPE       INTEGER CHECK (PCB_NAPPE >= 1),      -- n° de traverse (nappe) sur l'appui
    PCB_TENSION     TEXT NOT NULL DEFAULT 'STD_AGGLO'
                    CHECK (PCB_TENSION IN ('STD_AGGLO', 'STD_ECART', 'RELEVE')),
    PCB_FLECHE      REAL,               -- flèche relevée (m), si PCB_TENSION = RELEVE
    PCB_TEMP        REAL,               -- température ambiante au relevé (°C), si PCB_TENSION = RELEVE
    PCB_COMMENT     TEXT,
    DATE_CREA       TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    DATE_MODIF      TEXT,
    SRC_MODIF       TEXT,
    DATE_ABD        TEXT,
    SRC_ABD         TEXT,
    UNIQUE (PRT_KEY, PCB_RANG)
);

-- Matériel posé sur un support (chambre : manchon… ; poteau : boîte…) --------------------------

CREATE TABLE INF_EQUIPEMENT (
    EQU_ID          INTEGER PRIMARY KEY AUTOINCREMENT,
    EQU_CODE_EXT    TEXT NOT NULL UNIQUE,
    NOE_KEY         INTEGER NOT NULL,   -- noyau PRJ_NOE
    MAT_KEY         INTEGER REFERENCES MAT_EQUIP (MAT_ID),
    EQU_QTE         INTEGER NOT NULL DEFAULT 1,
    EQU_COMMENT     TEXT,
    DATE_CREA       TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    DATE_MODIF      TEXT,
    SRC_MODIF       TEXT,
    DATE_ABD        TEXT,
    SRC_ABD         TEXT
);

CREATE INDEX IX_CD_LIN ON INF_CONDUITE (LIN_KEY);
CREATE INDEX IX_CD_PARENT ON INF_CONDUITE (CD_PARENT_KEY);
CREATE INDEX IX_CDC_CD ON INF_CD_CABLE (CD_KEY);
CREATE INDEX IX_PCB_PRT ON INF_PORTEE_CABLE (PRT_KEY);
CREATE INDEX IX_EQU_NOE ON INF_EQUIPEMENT (NOE_KEY);
CREATE INDEX IX_MAT_CABLE_COMAC ON MAT_CABLE (COMAC_KEY);
