-- Domaine optique : contenu optique du matériel posé (boîtiers, baies, tiroirs), câbles identifiés et leur parcours,
-- lovages, fibres, cassettes et positions (épissures, passages, attentes, connecteurs), routes optiques, mesures.
-- Modèle GraceTHD v2.0.1 (t_ebp, t_baie, t_tiroir, t_cable, t_cab_cond, t_love, t_fibre, t_cassette, t_position,
-- t_ropt), conventions NgeEsPlorer. Fichier attaché au noyau sous le nom « optique ». Références vers le noyau et
-- l'infra : voir manifest.json. Le matériel reste dans l'infra (INF_EQUIPEMENT, catalogue MAT_EQUIP) et le câble porté
-- ou passé dans une conduite aussi (INF_PORTEE_CABLE, INF_CD_CABLE) : le module optique les identifie et les relie.
-- Base SpatiaLite depuis la version 0.3.0 (tracé propre des câbles de raccordement, Lambert 93 : EPSG:2154), sans
-- les EPSG inutiles : la base ne déclare que le Lambert 93.

SELECT InitSpatialMetadata(1, 'NONE');
SELECT InsertEpsgSrid(2154);

-- Référentiels --------------------------------------------------------------------------------

CREATE TABLE DEF_OPT_EQUIP_TYPE (       -- fonction d'un matériel optique (GraceTHD l_bp_type_log, t_baie, t_tiroir)
    OTYP_ID         INTEGER PRIMARY KEY,
    OTYP_CODE       TEXT NOT NULL UNIQUE,
    OTYP_LIB        TEXT NOT NULL
);

CREATE TABLE DEF_CAB_FONCTION (         -- fonction d'un câble (GraceTHD l_infra_type_log)
    CFON_ID         INTEGER PRIMARY KEY,
    CFON_CODE       TEXT NOT NULL UNIQUE,
    CFON_LIB        TEXT NOT NULL
);

CREATE TABLE DEF_FO_COULEUR (           -- code couleur des fibres et des tubes (GraceTHD l_fo_color, standard Orange)
    COUL_ID         INTEGER PRIMARY KEY,    -- rang dans le code (1 à 12)
    COUL_CODE       TEXT NOT NULL UNIQUE,
    COUL_LIB        TEXT NOT NULL,
    COUL_RGB        TEXT NOT NULL           -- #RRGGBB
);

CREATE TABLE DEF_CASSETTE_TYPE (        -- GraceTHD l_cassette_type
    CTYP_ID         INTEGER PRIMARY KEY,
    CTYP_CODE       TEXT NOT NULL UNIQUE,
    CTYP_LIB        TEXT NOT NULL
);

CREATE TABLE DEF_POS_FONCTION (         -- rôle d'une position de cassette (GraceTHD l_position_fonction)
    PFON_ID         INTEGER PRIMARY KEY,
    PFON_CODE       TEXT NOT NULL UNIQUE,
    PFON_LIB        TEXT NOT NULL
);

CREATE TABLE DEF_MES_METHODE (          -- méthode de mesure optique
    MMET_ID         INTEGER PRIMARY KEY,
    MMET_CODE       TEXT NOT NULL UNIQUE,
    MMET_LIB        TEXT NOT NULL
);

-- Matériel optique ----------------------------------------------------------------------------

-- Contenu optique d'un équipement posé (INF_EQUIPEMENT) : étiquette, fonction, capacité ; un tiroir a pour parent sa
-- baie. Emplacement dans un local technique (immeuble, site) : bâtiment, escalier, étage, en clair.
CREATE TABLE OPT_EQUIPEMENT (
    EQO_ID          INTEGER PRIMARY KEY AUTOINCREMENT,
    EQU_KEY         INTEGER NOT NULL UNIQUE,    -- infra INF_EQUIPEMENT
    EQO_LIB         TEXT,                       -- étiquette terrain (PBO-2-02HG-1015…)
    OTYP_KEY        INTEGER REFERENCES DEF_OPT_EQUIP_TYPE (OTYP_ID),
    EQO_PARENT_KEY  INTEGER REFERENCES OPT_EQUIPEMENT (EQO_ID),
    EQO_CAPA        INTEGER,                    -- capacité en fibres
    EQO_TAILLE      INTEGER,                    -- hauteur en unités de baie (U)
    EQO_EMPLACEMENT TEXT,
    AVCT_KEY        INTEGER,                    -- noyau DEF_AVANCEMENT
    PROPRIO_KEY     INTEGER,                    -- noyau DEF_ORGANISME
    EQO_COMMENT     TEXT,
    DATE_CREA       TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    DATE_MODIF      TEXT,
    SRC_MODIF       TEXT,
    DATE_ABD        TEXT,
    SRC_ABD         TEXT
);

-- Câbles --------------------------------------------------------------------------------------

-- Câble identifié, d'un nœud à l'autre (le même pour un câble de colonne dans un immeuble), raccordé à ses
-- extrémités dans un équipement. Pas de géométrie : son tracé est celui des linéaires de son parcours. Câble de
-- raccordement final (fonction RA, depuis la version 0.3.0) : du PBO (NOE1_KEY, EQU1_KEY) à l'adresse desservie
-- (ADR2_KEY, sans NOE2_KEY : la boîte aux lettres est portée par l'adresse, pas par un nœud), avec son tracé propre
-- (GEOMETRY, ligne en Lambert 93), seule exception aux câbles sans géométrie : il ne suit pas les linéaires.
CREATE TABLE OPT_CABLE (
    CAB_ID          INTEGER PRIMARY KEY AUTOINCREMENT,
    CAB_CODE_EXT    TEXT NOT NULL UNIQUE,
    CAB_LIB         TEXT,                       -- étiquette (CDI-2-02HG-1015…)
    MAT_KEY         INTEGER,                    -- infra MAT_CABLE
    CFON_KEY        INTEGER REFERENCES DEF_CAB_FONCTION (CFON_ID),
    CAB_CAPA        INTEGER,                    -- nombre de fibres
    CAB_MODULO      INTEGER,                    -- fibres par tube
    NOE1_KEY        INTEGER NOT NULL,           -- noyau PRJ_NOE, extrémité amont
    NOE2_KEY        INTEGER,                    -- noyau PRJ_NOE, extrémité aval (vide : raccordement d'une adresse)
    ADR2_KEY        INTEGER,                    -- noyau PRJ_ADRESSE, adresse desservie par un câble de raccordement
    EQU1_KEY        INTEGER,                    -- infra INF_EQUIPEMENT raccordant l'extrémité amont
    EQU2_KEY        INTEGER,                    -- infra INF_EQUIPEMENT raccordant l'extrémité aval
    CAB_LNG         REAL,                       -- longueur réelle (m), lovages compris
    AVCT_KEY        INTEGER,                    -- noyau DEF_AVANCEMENT
    PROPRIO_KEY     INTEGER,                    -- noyau DEF_ORGANISME
    CAB_COMMENT     TEXT,
    DATE_CREA       TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    DATE_MODIF      TEXT,
    SRC_MODIF       TEXT,
    DATE_ABD        TEXT,
    SRC_ABD         TEXT,
    CHECK (NOE2_KEY IS NOT NULL OR ADR2_KEY IS NOT NULL)
);
-- tracé propre d'un câble hors des linéaires (raccordement), vide sinon
SELECT AddGeometryColumn('OPT_CABLE', 'GEOMETRY', 2154, 'LINESTRING', 'XY', 0);

-- Passage d'un câble sur un linéaire de son parcours (câble tiré), avec la ligne de l'infra qui le porte : câble
-- porté sur la portée (aérien) ou occupation de la conduite (souterrain, façade). Rang dans le parcours depuis NOE1.
CREATE TABLE OPT_PASSAGE (
    PAS_ID          INTEGER PRIMARY KEY AUTOINCREMENT,
    CAB_KEY         INTEGER NOT NULL REFERENCES OPT_CABLE (CAB_ID),
    LIN_KEY         INTEGER NOT NULL,           -- noyau PRJ_LINEAIRE
    PCB_KEY         INTEGER,                    -- infra INF_PORTEE_CABLE
    CDC_KEY         INTEGER,                    -- infra INF_CD_CABLE
    PAS_RANG        INTEGER,
    DATE_CREA       TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    DATE_MODIF      TEXT,
    SRC_MODIF       TEXT,
    DATE_ABD        TEXT,
    SRC_ABD         TEXT,
    UNIQUE (CAB_KEY, LIN_KEY),
    CHECK (PCB_KEY IS NULL OR CDC_KEY IS NULL)
);

-- Lovage : réserve de câble laissée sur un nœud (GraceTHD t_love).
CREATE TABLE OPT_LOVE (
    LOV_ID          INTEGER PRIMARY KEY AUTOINCREMENT,
    CAB_KEY         INTEGER NOT NULL REFERENCES OPT_CABLE (CAB_ID),
    NOE_KEY         INTEGER NOT NULL,           -- noyau PRJ_NOE
    LOV_LNG         REAL,                       -- m
    DATE_CREA       TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    DATE_MODIF      TEXT,
    SRC_MODIF       TEXT,
    DATE_ABD        TEXT,
    SRC_ABD         TEXT,
    UNIQUE (CAB_KEY, NOE_KEY)
);

-- Fibre d'un câble : rang dans le câble, tube et rang dans le tube, couleurs (code DEF_FO_COULEUR). Au-delà de 12
-- tubes, la couleur du tube revient avec (FIB_TUBE - 1) / 12 bagues noires (tube 13 : rouge, une bague noire).
CREATE TABLE OPT_FIBRE (
    FIB_ID          INTEGER PRIMARY KEY AUTOINCREMENT,
    CAB_KEY         INTEGER NOT NULL REFERENCES OPT_CABLE (CAB_ID),
    FIB_NUM         INTEGER NOT NULL,
    FIB_TUBE        INTEGER,
    FIB_NUM_TUBE    INTEGER,
    COUL_KEY        INTEGER REFERENCES DEF_FO_COULEUR (COUL_ID),        -- couleur de la fibre
    TUBE_COUL_KEY   INTEGER REFERENCES DEF_FO_COULEUR (COUL_ID),        -- couleur du tube
    FIB_TYPE        TEXT,                       -- norme UIT (G652D, G657…)
    FIB_COMMENT     TEXT,
    DATE_CREA       TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    DATE_MODIF      TEXT,
    SRC_MODIF       TEXT,
    UNIQUE (CAB_KEY, FIB_NUM)
);

-- Cassettes et positions ----------------------------------------------------------------------

-- Cassette d'un boîtier ou d'un tiroir ; la cassette 0 d'un boîtier regroupe les fibres en passage hors platines.
CREATE TABLE OPT_CASSETTE (
    CAS_ID          INTEGER PRIMARY KEY AUTOINCREMENT,
    EQU_KEY         INTEGER NOT NULL,           -- infra INF_EQUIPEMENT (boîtier ou tiroir)
    CAS_NUM         INTEGER NOT NULL,
    CTYP_KEY        INTEGER REFERENCES DEF_CASSETTE_TYPE (CTYP_ID),
    CAS_CAPA        INTEGER,                    -- nombre de pas
    CAS_COMMENT     TEXT,
    DATE_CREA       TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    DATE_MODIF      TEXT,
    SRC_MODIF       TEXT,
    DATE_ABD        TEXT,
    SRC_ABD         TEXT,
    UNIQUE (EQU_KEY, CAS_NUM)
);

-- Position d'une cassette : fibre entrante (FIB1, côté amont) et fibre sortante (FIB2) ; épissure et passage relient
-- deux fibres, une attente ou un connecteur n'en porte qu'une. Affectation : usage de la fibre repris de l'étude
-- (ABONNE, DEPART, PASSAGE, RESERVE, MORTE…).
CREATE TABLE OPT_POSITION (
    POS_ID          INTEGER PRIMARY KEY AUTOINCREMENT,
    CAS_KEY         INTEGER NOT NULL REFERENCES OPT_CASSETTE (CAS_ID),
    POS_NUM         INTEGER,
    FIB1_KEY        INTEGER REFERENCES OPT_FIBRE (FIB_ID),
    FIB2_KEY        INTEGER REFERENCES OPT_FIBRE (FIB_ID),
    PFON_KEY        INTEGER REFERENCES DEF_POS_FONCTION (PFON_ID),
    POS_CONNECTEUR  TEXT,                       -- type de connecteur (GraceTHD l_position_type : CSA…)
    POS_AFFECT      TEXT,
    POS_COMMENT     TEXT,
    DATE_CREA       TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    DATE_MODIF      TEXT,
    SRC_MODIF       TEXT,
    DATE_ABD        TEXT,
    SRC_ABD         TEXT,
    CHECK (FIB1_KEY IS NOT NULL OR FIB2_KEY IS NOT NULL)
);

-- Routes et mesures ---------------------------------------------------------------------------

-- Route optique : suite des fibres d'un bout à l'autre du réseau (du tiroir de départ au PBO), dans l'ordre.
CREATE TABLE OPT_ROUTE (
    RTE_ID          INTEGER PRIMARY KEY AUTOINCREMENT,
    RTE_CODE_EXT    TEXT NOT NULL UNIQUE,
    RTE_LIB         TEXT,
    RTE_COMMENT     TEXT,
    DATE_CREA       TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    DATE_MODIF      TEXT,
    SRC_MODIF       TEXT,
    DATE_ABD        TEXT,
    SRC_ABD         TEXT
);

CREATE TABLE OPT_ROUTE_FIBRE (
    ROF_ID          INTEGER PRIMARY KEY AUTOINCREMENT,
    RTE_KEY         INTEGER NOT NULL REFERENCES OPT_ROUTE (RTE_ID),
    ROF_RANG        INTEGER NOT NULL,
    FIB_KEY         INTEGER NOT NULL REFERENCES OPT_FIBRE (FIB_ID),
    UNIQUE (RTE_KEY, ROF_RANG)
);

-- Mesure d'une fibre, à une longueur d'onde et dans un sens (OE : de l'origine vers l'extrémité) : longueur, perte
-- totale, plus forte atténuation d'événement et plus forte pente des tronçons, ORL ; conformité aux seuils de la
-- mesure. Fichier de la trace (.sor) : PRJ_FICHIER rattaché à la mesure. Identifiants de la source conservés
-- (câble et fibre tels que nommés par l'appareil) quand la route ou la fibre n'est pas retrouvée.
CREATE TABLE OPT_MESURE (
    MES_ID          INTEGER PRIMARY KEY AUTOINCREMENT,
    MES_CODE_EXT    TEXT NOT NULL UNIQUE,
    MMET_KEY        INTEGER NOT NULL REFERENCES DEF_MES_METHODE (MMET_ID),
    RTE_KEY         INTEGER REFERENCES OPT_ROUTE (RTE_ID),
    FIB_KEY         INTEGER REFERENCES OPT_FIBRE (FIB_ID),
    EQU_KEY         INTEGER,                    -- infra INF_EQUIPEMENT à l'extrémité mesurée
    MES_CABLE       TEXT,
    MES_FIBRE       INTEGER,
    MES_ORIGINE     TEXT,
    MES_EXTREMITE   TEXT,
    MES_LAMBDA      INTEGER,                    -- nm
    MES_SENS        TEXT CHECK (MES_SENS IN ('OE', 'EO', 'BI')),
    MES_LNG         REAL,                       -- m
    MES_PERTE       REAL,                       -- dB
    MES_EVT_MAX     REAL,                       -- dB
    MES_PENTE_MAX   REAL,                       -- dB/km
    MES_ORL         REAL,                       -- dB
    MES_CONFORME    INTEGER CHECK (MES_CONFORME IN (0, 1)),
    MES_APPAREIL    TEXT,
    MES_DATE        TEXT,
    MES_COMMENT     TEXT,
    DATE_CREA       TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    DATE_MODIF      TEXT,
    SRC_MODIF       TEXT,
    DATE_ABD        TEXT,
    SRC_ABD         TEXT
);

CREATE INDEX IX_EQO_PARENT ON OPT_EQUIPEMENT (EQO_PARENT_KEY);
CREATE INDEX IX_CAB_NOE1 ON OPT_CABLE (NOE1_KEY);
CREATE INDEX IX_CAB_NOE2 ON OPT_CABLE (NOE2_KEY);
CREATE INDEX IX_CAB_ADR2 ON OPT_CABLE (ADR2_KEY);
CREATE INDEX IX_CAB_EQU1 ON OPT_CABLE (EQU1_KEY);
CREATE INDEX IX_CAB_EQU2 ON OPT_CABLE (EQU2_KEY);
CREATE INDEX IX_PAS_LIN ON OPT_PASSAGE (LIN_KEY);
CREATE INDEX IX_PAS_PCB ON OPT_PASSAGE (PCB_KEY);
CREATE INDEX IX_PAS_CDC ON OPT_PASSAGE (CDC_KEY);
CREATE INDEX IX_LOV_NOE ON OPT_LOVE (NOE_KEY);
CREATE INDEX IX_CAS_EQU ON OPT_CASSETTE (EQU_KEY);
CREATE INDEX IX_POS_CAS ON OPT_POSITION (CAS_KEY);
CREATE INDEX IX_POS_FIB1 ON OPT_POSITION (FIB1_KEY);
CREATE INDEX IX_POS_FIB2 ON OPT_POSITION (FIB2_KEY);
CREATE INDEX IX_ROF_FIB ON OPT_ROUTE_FIBRE (FIB_KEY);
CREATE INDEX IX_MES_RTE ON OPT_MESURE (RTE_KEY);
CREATE INDEX IX_MES_FIB ON OPT_MESURE (FIB_KEY);
CREATE INDEX IX_MES_EQU ON OPT_MESURE (EQU_KEY);
