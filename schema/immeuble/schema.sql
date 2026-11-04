-- Domaine immeuble : attributs d'une adresse relevés au BAL (logements et locaux professionnels, habitat, état,
-- convention avec le gestionnaire) et locaux qu'elle dessert (sites utilisateurs finals). L'immeuble est un nœud du
-- noyau (type IMM) à son adresse ; son local technique héberge le matériel (INF_EQUIPEMENT, emplacement dans
-- OPT_EQUIPEMENT). Modèle GraceTHD v2.0.1 (t_adresse ad_*, t_suf, t_sitetech de type BAT). Fichier attaché au noyau
-- sous le nom « immeuble ». Références vers le noyau et l'infra : voir manifest.json.

-- Référentiels --------------------------------------------------------------------------------

CREATE TABLE DEF_IMB_HABITAT (          -- GraceTHD l_immeuble_type
    HAB_ID          INTEGER PRIMARY KEY,
    HAB_CODE        TEXT NOT NULL UNIQUE,
    HAB_LIB         TEXT NOT NULL
);

CREATE TABLE DEF_IMB_ETAT (             -- GraceTHD l_adresse_etat
    IETAT_ID        INTEGER PRIMARY KEY,
    IETAT_CODE      TEXT NOT NULL UNIQUE,
    IETAT_LIB       TEXT NOT NULL
);

CREATE TABLE DEF_LOC_TYPE (             -- GraceTHD l_suf_type
    LTYP_ID         INTEGER PRIMARY KEY,
    LTYP_CODE       TEXT NOT NULL UNIQUE,
    LTYP_LIB        TEXT NOT NULL
);

CREATE TABLE DEF_LOC_RACCO (            -- GraceTHD l_suf_racco
    RACCO_ID        INTEGER PRIMARY KEY,
    RACCO_CODE      TEXT NOT NULL UNIQUE,
    RACCO_LIB       TEXT NOT NULL
);

-- Adresse (BAL) --------------------------------------------------------------------------------

-- Ce que l'adresse dessert et la convention de l'immeuble : nombres de logements et de locaux professionnels, de
-- prises à construire, raccordement prévu (DEF_IMPLANTATION : aérien, façade, immeuble, conduite…), code du bâtiment
-- dans le référentiel de l'opérateur.
CREATE TABLE IMB_ADRESSE (
    IAD_ID          INTEGER PRIMARY KEY AUTOINCREMENT,
    ADR_KEY         INTEGER NOT NULL UNIQUE,    -- noyau PRJ_ADRESSE
    HAB_KEY         INTEGER REFERENCES DEF_IMB_HABITAT (HAB_ID),
    IETAT_KEY       INTEGER REFERENCES DEF_IMB_ETAT (IETAT_ID),
    IAD_NB_LOG      INTEGER,
    IAD_NB_PRO      INTEGER,
    IAD_NB_PRISE_LOG INTEGER,
    IAD_NB_PRISE_PRO INTEGER,
    IAD_NEUF        INTEGER CHECK (IAD_NEUF IN (0, 1)),
    IAD_BATCODE     TEXT,
    IAD_BATIMENT    TEXT,                       -- nom du bâtiment
    IMPL_KEY        INTEGER,                    -- noyau DEF_IMPLANTATION
    GEST_KEY        INTEGER,                    -- noyau DEF_ORGANISME (gestionnaire, syndic)
    IAD_CONV_DATE   TEXT,                       -- signature de la convention
    IAD_ACCORD_GEST INTEGER CHECK (IAD_ACCORD_GEST IN (0, 1)),
    IAD_COMMENT     TEXT,
    DATE_CREA       TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    DATE_MODIF      TEXT,
    SRC_MODIF       TEXT,
    DATE_ABD        TEXT,
    SRC_ABD         TEXT
);

-- Local desservi par une adresse (logement, local professionnel ou technique) et son raccordement ; PBO qui le
-- dessert (zone du PBO).
CREATE TABLE IMB_LOCAL (
    LOC_ID          INTEGER PRIMARY KEY AUTOINCREMENT,
    LOC_CODE_EXT    TEXT NOT NULL UNIQUE,
    ADR_KEY         INTEGER NOT NULL,           -- noyau PRJ_ADRESSE
    LTYP_KEY        INTEGER REFERENCES DEF_LOC_TYPE (LTYP_ID),
    RACCO_KEY       INTEGER REFERENCES DEF_LOC_RACCO (RACCO_ID),
    LOC_BATIMENT    TEXT,
    LOC_ESCALIER    TEXT,
    LOC_ETAGE       TEXT,
    LOC_LIB         TEXT,                       -- désignation du local
    EQU_KEY         INTEGER,                    -- infra INF_EQUIPEMENT (PBO)
    LOC_COMMENT     TEXT,
    DATE_CREA       TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    DATE_MODIF      TEXT,
    SRC_MODIF       TEXT,
    DATE_ABD        TEXT,
    SRC_ABD         TEXT
);

CREATE INDEX IX_LOC_ADR ON IMB_LOCAL (ADR_KEY);
CREATE INDEX IX_LOC_EQU ON IMB_LOCAL (EQU_KEY);
