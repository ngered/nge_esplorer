-- Noyau NgeEsPlorer : projet, référentiels communs, géométries (zones, adresses, nœuds, linéaires),
-- interventions, fichiers et commentaires. Base SpatiaLite (mod_spatialite chargé), Lambert 93 (EPSG:2154).
-- Conventions : XXX_ID clé primaire (entier long auto-incrémenté), XXX_KEY clé étrangère,
-- XXX_CODE_EXT identifiant stable unique dans le projet, XXX_LIB libellé. Dates ISO 8601 UTC.

SELECT InitSpatialMetadata(1);

-- Projet et modules -----------------------------------------------------------------------------

CREATE TABLE SYS_PROJET (
    PRJ_ID          INTEGER PRIMARY KEY AUTOINCREMENT,
    PRJ_CODE_EXT    TEXT NOT NULL UNIQUE,
    PRJ_LIB         TEXT NOT NULL,
    PRJ_SRID        INTEGER NOT NULL DEFAULT 2154,
    MODELE_VERSION  TEXT NOT NULL,
    DATE_CREA       TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- Modules attachés : le fichier est relatif au dossier du projet ; le nom de schéma d'attachement est MOD_CODE.
CREATE TABLE SYS_MODULE (
    MOD_ID          INTEGER PRIMARY KEY AUTOINCREMENT,
    MOD_CODE        TEXT NOT NULL UNIQUE,
    MOD_VERSION     TEXT NOT NULL,
    MOD_FICHIER     TEXT NOT NULL,
    DATE_ATTACH     TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- Tables métier pouvant porter des fichiers ou des interventions (noyau et modules).
CREATE TABLE DEF_ENTITE (
    ENT_ID          INTEGER PRIMARY KEY AUTOINCREMENT,
    ENT_TABLE       TEXT NOT NULL UNIQUE,
    MOD_CODE        TEXT NOT NULL,
    ENT_LIB         TEXT NOT NULL
);

-- Référentiels communs ------------------------------------------------------------------------

-- Arborescence des types de nœuds et de linéaires (identifiants FOA Explorer conservés quand ils existent).
CREATE TABLE DEF_TYPE (
    TYPE_ID         INTEGER PRIMARY KEY,
    TYPE_CODE       TEXT NOT NULL UNIQUE,
    TYPE_LIB        TEXT NOT NULL,
    TYPE_PARENT_KEY INTEGER REFERENCES DEF_TYPE (TYPE_ID),
    TYPE_GEOM       TEXT NOT NULL CHECK (TYPE_GEOM IN ('POINT', 'LINESTRING')),
    MOD_CODE        TEXT,           -- module qui porte le métier de ce type
    GRACE_CODE      TEXT,           -- correspondance GraceTHD v2 (pt_typephy, cm_typ_imp…)
    ACTIF           INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE DEF_AVANCEMENT (           -- GraceTHD l_avancement
    AVCT_ID         INTEGER PRIMARY KEY,
    AVCT_CODE       TEXT NOT NULL UNIQUE,
    AVCT_LIB        TEXT NOT NULL
);

CREATE TABLE DEF_IMPLANTATION (         -- GraceTHD l_implantation_type
    IMPL_ID         INTEGER PRIMARY KEY,
    IMPL_CODE       TEXT NOT NULL UNIQUE,
    IMPL_LIB        TEXT NOT NULL
);

CREATE TABLE DEF_GEOL_CLASSE (          -- GraceTHD l_geoloc_classe (classes de précision DT-DICT)
    CLASSE_ID       INTEGER PRIMARY KEY,
    CLASSE_CODE     TEXT NOT NULL UNIQUE,
    CLASSE_LIB      TEXT NOT NULL
);

CREATE TABLE DEF_GEOL_MODE (            -- GraceTHD l_geoloc_mode
    GMOD_ID         INTEGER PRIMARY KEY,
    GMOD_CODE       TEXT NOT NULL UNIQUE,
    GMOD_LIB        TEXT NOT NULL
);

CREATE TABLE DEF_ORGANISME (            -- propriétaires, gestionnaires (GraceTHD t_organisme)
    ORG_ID          INTEGER PRIMARY KEY AUTOINCREMENT,
    ORG_CODE        TEXT NOT NULL UNIQUE,
    ORG_LIB         TEXT NOT NULL,
    ORG_SIREN       TEXT
);

CREATE TABLE DEF_FABRICANT (            -- FOA DEF_FABRICANTS
    FAB_ID          INTEGER PRIMARY KEY,
    FAB_LIB         TEXT NOT NULL
);

-- Vues photographiées attendues par type de support (écran « visuels » du socle).
CREATE TABLE DEF_VUE (
    VUE_ID          INTEGER PRIMARY KEY AUTOINCREMENT,
    TYPE_KEY        INTEGER NOT NULL REFERENCES DEF_TYPE (TYPE_ID),
    VUE_CODE        TEXT NOT NULL,
    VUE_LIB         TEXT NOT NULL,
    VUE_ORDRE       INTEGER NOT NULL,
    VUE_OBLIGATOIRE TEXT NOT NULL DEFAULT 'NON' CHECK (VUE_OBLIGATOIRE IN ('OUI', 'NON', 'SI_MASQUE')),
    VUE_ACTION      TEXT,           -- action propre au module : MASQUE, ROSACE…
    MOD_CODE        TEXT NOT NULL,
    UNIQUE (TYPE_KEY, VUE_CODE)
);

-- Géométries ----------------------------------------------------------------------------------

CREATE TABLE PRJ_ZONE (
    ZONE_ID         INTEGER PRIMARY KEY AUTOINCREMENT,
    ZONE_CODE_EXT   TEXT NOT NULL UNIQUE,
    ZONE_LIB        TEXT NOT NULL,
    ZONE_PARENT_KEY INTEGER REFERENCES PRJ_ZONE (ZONE_ID),
    DATE_CREA       TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    DATE_MODIF      TEXT,
    SRC_MODIF       TEXT,
    DATE_ABD        TEXT,
    SRC_ABD         TEXT
);
SELECT AddGeometryColumn('PRJ_ZONE', 'GEOMETRY', 2154, 'MULTIPOLYGON', 'XY', 0);

CREATE TABLE PRJ_ADRESSE (
    ADR_ID          INTEGER PRIMARY KEY AUTOINCREMENT,
    ADR_CODE_EXT    TEXT NOT NULL UNIQUE,
    ADR_BAN_ID      TEXT,
    ADR_NUMERO      INTEGER,
    ADR_REP         TEXT,
    ADR_VOIE        TEXT,
    ADR_CP          TEXT,
    ADR_INSEE       TEXT,
    ADR_COMMUNE     TEXT,
    ADR_COMMENT     TEXT,
    DATE_CREA       TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    DATE_MODIF      TEXT,
    SRC_MODIF       TEXT,
    DATE_ABD        TEXT,
    SRC_ABD         TEXT
);
SELECT AddGeometryColumn('PRJ_ADRESSE', 'GEOMETRY', 2154, 'POINT', 'XY', 0);

CREATE TABLE PRJ_NOE (
    NOE_ID          INTEGER PRIMARY KEY AUTOINCREMENT,
    NOE_CODE_EXT    TEXT NOT NULL UNIQUE,
    NOE_LIB         TEXT,           -- étiquette terrain (n° de chambre, n° d'appui Orange…)
    TYPE_KEY        INTEGER NOT NULL REFERENCES DEF_TYPE (TYPE_ID),
    ADR_KEY         INTEGER REFERENCES PRJ_ADRESSE (ADR_ID),
    ZONE_KEY        INTEGER REFERENCES PRJ_ZONE (ZONE_ID),
    AVCT_KEY        INTEGER REFERENCES DEF_AVANCEMENT (AVCT_ID),
    GEOL_QLT        REAL,           -- précision estimée (m)
    GEOL_MOD_KEY    INTEGER REFERENCES DEF_GEOL_MODE (GMOD_ID),
    GEOL_CLASSE_KEY INTEGER REFERENCES DEF_GEOL_CLASSE (CLASSE_ID),
    GEOL_SRC        TEXT,
    DATE_CREA       TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    DATE_MODIF      TEXT,
    SRC_MODIF       TEXT,
    DATE_ABD        TEXT,
    SRC_ABD         TEXT
);
SELECT AddGeometryColumn('PRJ_NOE', 'GEOMETRY', 2154, 'POINT', 'XY', 1);

CREATE TABLE PRJ_LINEAIRE (
    LIN_ID          INTEGER PRIMARY KEY AUTOINCREMENT,
    LIN_CODE_EXT    TEXT NOT NULL UNIQUE,
    LIN_LIB         TEXT,
    TYPE_KEY        INTEGER NOT NULL REFERENCES DEF_TYPE (TYPE_ID),
    IMPL_KEY        INTEGER REFERENCES DEF_IMPLANTATION (IMPL_ID),
    NOE1_KEY        INTEGER NOT NULL REFERENCES PRJ_NOE (NOE_ID),
    NOE2_KEY        INTEGER NOT NULL REFERENCES PRJ_NOE (NOE_ID),
    ZONE_KEY        INTEGER REFERENCES PRJ_ZONE (ZONE_ID),
    AVCT_KEY        INTEGER REFERENCES DEF_AVANCEMENT (AVCT_ID),
    LIN_LNG         REAL,           -- longueur relevée (m) ; la longueur cartographique se calcule
    LIN_COMMENT     TEXT,
    GEOL_QLT        REAL,
    GEOL_MOD_KEY    INTEGER REFERENCES DEF_GEOL_MODE (GMOD_ID),
    GEOL_CLASSE_KEY INTEGER REFERENCES DEF_GEOL_CLASSE (CLASSE_ID),
    GEOL_SRC        TEXT,
    DATE_CREA       TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    DATE_MODIF      TEXT,
    SRC_MODIF       TEXT,
    DATE_ABD        TEXT,
    SRC_ABD         TEXT,
    CHECK (NOE1_KEY <> NOE2_KEY)
);
SELECT AddGeometryColumn('PRJ_LINEAIRE', 'GEOMETRY', 2154, 'LINESTRING', 'XY', 1);

-- Interventions (qui, quand, quelle mission, quels objets) ------------------------------------

CREATE TABLE PRJ_INTERVENTION (
    INT_ID          INTEGER PRIMARY KEY AUTOINCREMENT,
    INT_CODE_EXT    TEXT NOT NULL UNIQUE,
    INT_LIB         TEXT,
    ACT_CODE        TEXT NOT NULL,  -- activité (RELEVE_CHB, RELEVE_POT…)
    INT_COMMANDE    TEXT,           -- mission / commande
    INT_AUTEUR      TEXT NOT NULL,  -- compte abonné
    INT_TERMINAL    TEXT,
    DATE_DEBUT      TEXT NOT NULL,
    DATE_FIN        TEXT,
    INT_STATUT      TEXT NOT NULL DEFAULT 'EN_COURS'
                    CHECK (INT_STATUT IN ('EN_COURS', 'TRANSMISE', 'VALIDEE', 'REJETEE', 'INTEGREE')),
    INT_COMMENT     TEXT,
    DATE_CREA       TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    DATE_MODIF      TEXT
);

CREATE TABLE PRJ_INT_OBJET (
    IOB_ID          INTEGER PRIMARY KEY AUTOINCREMENT,
    INT_KEY         INTEGER NOT NULL REFERENCES PRJ_INTERVENTION (INT_ID),
    ENT_KEY         INTEGER NOT NULL REFERENCES DEF_ENTITE (ENT_ID),
    OBJ_KEY         INTEGER NOT NULL,
    IOB_ACTION      TEXT NOT NULL CHECK (IOB_ACTION IN ('C', 'M', 'A')),   -- création, modification, abandon
    DATE_ACTION     TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- Fichiers (photos et pièces jointes) ---------------------------------------------------------

CREATE TABLE PRJ_FICHIER (
    FIC_ID          INTEGER PRIMARY KEY AUTOINCREMENT,
    FIC_CODE_EXT    TEXT NOT NULL UNIQUE,
    ENT_KEY         INTEGER NOT NULL REFERENCES DEF_ENTITE (ENT_ID),
    OBJ_KEY         INTEGER NOT NULL,
    VUE_KEY         INTEGER REFERENCES DEF_VUE (VUE_ID),
    VIS_CODE        TEXT,           -- visuel libre (VUE_KEY nul) : identifiant commun à ses photos (UUID)
    VIS_LIB         TEXT,           -- titre du visuel libre, saisi sur le terrain
    FIC_RANG        INTEGER NOT NULL DEFAULT 1,
    FIC_PRINCIPALE  INTEGER NOT NULL DEFAULT 0 CHECK (FIC_PRINCIPALE IN (0, 1)),
    FIC_NOM         TEXT NOT NULL,
    FIC_CHEMIN      TEXT NOT NULL,  -- relatif au dossier du projet
    FIC_TYPE        TEXT,           -- type MIME
    FIC_TAILLE      INTEGER,
    FIC_SHA256      TEXT,
    DATE_PRISE      TEXT,
    FIC_COMMENT     TEXT,
    DATE_CREA       TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    DATE_MODIF      TEXT,
    SRC_MODIF       TEXT,
    DATE_ABD        TEXT,
    SRC_ABD         TEXT
);
-- une seule photo principale par objet et par vue
CREATE UNIQUE INDEX UX_FICHIER_PRINCIPALE ON PRJ_FICHIER (ENT_KEY, OBJ_KEY, VUE_KEY) WHERE FIC_PRINCIPALE = 1;

-- Commentaires (journal daté et signé) --------------------------------------------------------

-- Remplace les champs libres du support (NOE_COMMENT, CHB_COMMENT, POT_COMMENT jusqu'à la version 0.1.0).
-- Types de FibReady, par gravité décroissante : alert (Alerte), minor (Mineur), standard, great (Bon point).
-- Une entrée n'est modifiable ou supprimable que par son auteur, tant que le paquet de retour qui la contient
-- n'est pas exporté ; elle est ensuite figée. Au BE, une entrée se retire par abandon (DATE_ABD, SRC_ABD).
-- Texte et auteur non blancs, comme le contrôle du paquet (tools/geojson/paquet.py verifier) : blancs = espace,
-- tabulation, saut de ligne, retour chariot, tabulation verticale, saut de page, espace insécable.
CREATE TABLE PRJ_COMMENTAIRE (
    COM_ID          INTEGER PRIMARY KEY AUTOINCREMENT,
    COM_CODE_EXT    TEXT NOT NULL UNIQUE,    -- UUID stable
    ENT_KEY         INTEGER NOT NULL REFERENCES DEF_ENTITE (ENT_ID),
    OBJ_KEY         INTEGER NOT NULL,        -- objet commenté (PRJ_NOE, PRJ_LINEAIRE, PRJ_ADRESSE), comme PRJ_FICHIER
    INT_KEY         INTEGER REFERENCES PRJ_INTERVENTION (INT_ID),   -- intervention terrain qui l'a saisi
    COM_TYPE        TEXT NOT NULL DEFAULT 'standard' CHECK (COM_TYPE IN ('alert', 'minor', 'standard', 'great')),
    COM_TEXTE       TEXT NOT NULL,
    COM_AUTEUR      TEXT NOT NULL,           -- nom de l'utilisateur ; « FOA » ou « BE » pour un texte repris
    COM_ORIGINE     TEXT,                    -- vide : saisi ; 'FOA', 'GRACE', 'BE' : texte repris ; 'CTRL_n' : contrôle
    DATE_CREA       TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    DATE_MODIF      TEXT,
    SRC_MODIF       TEXT,
    DATE_ABD        TEXT,
    SRC_ABD         TEXT,
    CHECK (trim(COM_TEXTE, char(32, 9, 10, 13, 11, 12, 160)) <> ''),
    CHECK (trim(COM_AUTEUR, char(32, 9, 10, 13, 11, 12, 160)) <> '')
);

-- Index des clés étrangères ----------------------------------------------------------------------

CREATE INDEX IX_TYPE_PARENT ON DEF_TYPE (TYPE_PARENT_KEY);
CREATE INDEX IX_ZONE_PARENT ON PRJ_ZONE (ZONE_PARENT_KEY);
CREATE INDEX IX_NOE_TYPE ON PRJ_NOE (TYPE_KEY);
CREATE INDEX IX_NOE_ADR ON PRJ_NOE (ADR_KEY);
CREATE INDEX IX_NOE_ZONE ON PRJ_NOE (ZONE_KEY);
CREATE INDEX IX_LIN_TYPE ON PRJ_LINEAIRE (TYPE_KEY);
CREATE INDEX IX_LIN_NOE1 ON PRJ_LINEAIRE (NOE1_KEY);
CREATE INDEX IX_LIN_NOE2 ON PRJ_LINEAIRE (NOE2_KEY);
CREATE INDEX IX_LIN_ZONE ON PRJ_LINEAIRE (ZONE_KEY);
CREATE INDEX IX_IOB_INT ON PRJ_INT_OBJET (INT_KEY);
CREATE INDEX IX_IOB_OBJ ON PRJ_INT_OBJET (ENT_KEY, OBJ_KEY);
CREATE INDEX IX_FIC_OBJ ON PRJ_FICHIER (ENT_KEY, OBJ_KEY);
CREATE INDEX IX_COM_OBJ ON PRJ_COMMENTAIRE (ENT_KEY, OBJ_KEY);
CREATE INDEX IX_COM_INT ON PRJ_COMMENTAIRE (INT_KEY);

SELECT CreateSpatialIndex('PRJ_ZONE', 'GEOMETRY');
SELECT CreateSpatialIndex('PRJ_ADRESSE', 'GEOMETRY');
SELECT CreateSpatialIndex('PRJ_NOE', 'GEOMETRY');
SELECT CreateSpatialIndex('PRJ_LINEAIRE', 'GEOMETRY');
