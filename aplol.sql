--
-- PostgreSQL database dump
--

SET statement_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET search_path = public, pg_catalog;
SET default_tablespace = '';
SET default_with_oids = false;

--
-- Name: aps_diff; Type: TABLE; Schema: public; Owner: aplol; Tablespace: 
--

CREATE TABLE aps_diff (
    id integer NOT NULL,
    name character varying NOT NULL,
    ethmac macaddr NOT NULL,
    wlc_name character varying DEFAULT 'undef'::character varying NOT NULL,
    db_wlc_name character varying DEFAULT 'undef'::character varying NOT NULL,
    apgroup_name character varying DEFAULT 'undef'::character varying NOT NULL,
    db_apgroup_name character varying DEFAULT 'undef'::character varying NOT NULL
);


ALTER TABLE public.aps_diff OWNER TO aplol;

--
-- Name: ap_diff_id_seq; Type: SEQUENCE; Schema: public; Owner: aplol
--

CREATE SEQUENCE ap_diff_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.ap_diff_id_seq OWNER TO aplol;

--
-- Name: ap_diff_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: aplol
--

ALTER SEQUENCE ap_diff_id_seq OWNED BY aps_diff.id;


--
-- Name: aps; Type: TABLE; Schema: public; Owner: aplol; Tablespace: 
--

CREATE TABLE aps (
    id integer NOT NULL,
    name character varying NOT NULL,
    ethmac macaddr NOT NULL,
    ip inet DEFAULT '0.0.0.0'::inet NOT NULL,
    model character varying DEFAULT 'undef'::character varying NOT NULL,
    location_id integer DEFAULT 0 NOT NULL,
    wlc_id integer DEFAULT 0 NOT NULL,
    associated boolean DEFAULT false NOT NULL,
    neighbor_name character varying DEFAULT 'undef'::character varying NOT NULL,
    neighbor_addr inet DEFAULT '0.0.0.0'::inet NOT NULL,
    neighbor_port character varying DEFAULT 'undef'::character varying NOT NULL,
    created timestamp with time zone DEFAULT ('now'::text)::timestamp with time zone NOT NULL,
    updated timestamp with time zone DEFAULT ('now'::text)::timestamp with time zone NOT NULL,
    active boolean DEFAULT true NOT NULL,
    uptime bigint DEFAULT 0 NOT NULL,
    alarm character varying DEFAULT 'undef'::character varying NOT NULL,
    wmac macaddr DEFAULT '00:00:00:00:00:00'::macaddr NOT NULL,
    apgroup_oid character varying DEFAULT 'undef'::character varying NOT NULL,
    apgroup_name character varying DEFAULT 'undef'::character varying NOT NULL,
    serial character varying DEFAULT 'undef'::character varying NOT NULL,
    client_total integer DEFAULT 0 NOT NULL,
    client_24 integer DEFAULT 0 NOT NULL,
    client_5 integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.aps OWNER TO aplol;

--
-- Name: COLUMN aps.active; Type: COMMENT; Schema: public; Owner: aplol
--

COMMENT ON COLUMN aps.active IS 'Set to false if AP not found';


--
-- Name: COLUMN aps.client_total; Type: COMMENT; Schema: public; Owner: aplol
--

COMMENT ON COLUMN aps.client_total IS 'Total number of clients connected to AP';


--
-- Name: COLUMN aps.client_24; Type: COMMENT; Schema: public; Owner: aplol
--

COMMENT ON COLUMN aps.client_24 IS 'Total number of 2.4GHz clients connected to AP';


--
-- Name: COLUMN aps.client_5; Type: COMMENT; Schema: public; Owner: aplol
--

COMMENT ON COLUMN aps.client_5 IS 'Total number of 5GHz clients connected to AP';


--
-- Name: aps_count; Type: TABLE; Schema: public; Owner: aplol; Tablespace: 
--

CREATE TABLE aps_count (
    id integer NOT NULL,
    date date DEFAULT now() NOT NULL,
    count integer DEFAULT 0 NOT NULL,
    type character varying DEFAULT 'default'::character varying NOT NULL,
    type_id integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.aps_count OWNER TO aplol;

--
-- Name: COLUMN aps_count.type_id; Type: COMMENT; Schema: public; Owner: aplol
--

COMMENT ON COLUMN aps_count.type_id IS 'ID of correlating type (i.e. ID for the VD name or ID for the WLC name)';


--
-- Name: aps_id_seq; Type: SEQUENCE; Schema: public; Owner: aplol
--

CREATE SEQUENCE aps_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.aps_id_seq OWNER TO aplol;

--
-- Name: aps_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: aplol
--

ALTER SEQUENCE aps_id_seq OWNED BY aps.id;


--
-- Name: count_id_seq; Type: SEQUENCE; Schema: public; Owner: aplol
--

CREATE SEQUENCE count_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.count_id_seq OWNER TO aplol;

--
-- Name: count_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: aplol
--

ALTER SEQUENCE count_id_seq OWNED BY aps_count.id;


--
-- Name: locations; Type: TABLE; Schema: public; Owner: aplol; Tablespace: 
--

CREATE TABLE locations (
    id integer NOT NULL,
    location character varying NOT NULL
);


ALTER TABLE public.locations OWNER TO aplol;

--
-- Name: locations_id_seq; Type: SEQUENCE; Schema: public; Owner: aplol
--

CREATE SEQUENCE locations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.locations_id_seq OWNER TO aplol;

--
-- Name: locations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: aplol
--

ALTER SEQUENCE locations_id_seq OWNED BY locations.id;


--
-- Name: log; Type: TABLE; Schema: public; Owner: aplol; Tablespace: 
--

CREATE TABLE log (
    id integer NOT NULL,
    ap_id integer DEFAULT 0 NOT NULL,
    date timestamp with time zone DEFAULT ('now'::text)::timestamp with time zone NOT NULL,
    username character varying DEFAULT 'undef'::character varying NOT NULL,
    caseid character varying DEFAULT 'undef'::character varying NOT NULL,
    message character varying DEFAULT 'undef'::character varying NOT NULL
);


ALTER TABLE public.log OWNER TO aplol;

--
-- Name: log_id_seq; Type: SEQUENCE; Schema: public; Owner: aplol
--

CREATE SEQUENCE log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.log_id_seq OWNER TO aplol;

--
-- Name: log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: aplol
--

ALTER SEQUENCE log_id_seq OWNED BY log.id;


--
-- Name: vd_mapping; Type: TABLE; Schema: public; Owner: aplol; Tablespace: 
--

CREATE TABLE vd_mapping (
    id integer NOT NULL,
    vd_id integer NOT NULL,
    location_id integer NOT NULL
);


ALTER TABLE public.vd_mapping OWNER TO aplol;

--
-- Name: vd_mapping_id_seq; Type: SEQUENCE; Schema: public; Owner: aplol
--

CREATE SEQUENCE vd_mapping_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.vd_mapping_id_seq OWNER TO aplol;

--
-- Name: vd_mapping_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: aplol
--

ALTER SEQUENCE vd_mapping_id_seq OWNED BY vd_mapping.id;


--
-- Name: virtual_domains; Type: TABLE; Schema: public; Owner: aplol; Tablespace: 
--

CREATE TABLE virtual_domains (
    id integer NOT NULL,
    name character varying NOT NULL,
    description character varying NOT NULL,
    description_long character varying,
    active boolean DEFAULT true NOT NULL
);


ALTER TABLE public.virtual_domains OWNER TO aplol;

--
-- Name: COLUMN virtual_domains.name; Type: COMMENT; Schema: public; Owner: aplol
--

COMMENT ON COLUMN virtual_domains.name IS 'VD name as defined in PI';


--
-- Name: virtual_domains_id_seq; Type: SEQUENCE; Schema: public; Owner: aplol
--

CREATE SEQUENCE virtual_domains_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.virtual_domains_id_seq OWNER TO aplol;

--
-- Name: virtual_domains_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: aplol
--

ALTER SEQUENCE virtual_domains_id_seq OWNED BY virtual_domains.id;


--
-- Name: wlc; Type: TABLE; Schema: public; Owner: aplol; Tablespace: 
--

CREATE TABLE wlc (
    id integer NOT NULL,
    name character varying NOT NULL,
    ipv4 inet
);


ALTER TABLE public.wlc OWNER TO aplol;

--
-- Name: wlc_id_seq; Type: SEQUENCE; Schema: public; Owner: aplol
--

CREATE SEQUENCE wlc_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.wlc_id_seq OWNER TO aplol;

--
-- Name: wlc_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: aplol
--

ALTER SEQUENCE wlc_id_seq OWNED BY wlc.id;


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: aplol
--

ALTER TABLE ONLY aps ALTER COLUMN id SET DEFAULT nextval('aps_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: aplol
--

ALTER TABLE ONLY aps_count ALTER COLUMN id SET DEFAULT nextval('count_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: aplol
--

ALTER TABLE ONLY aps_diff ALTER COLUMN id SET DEFAULT nextval('ap_diff_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: aplol
--

ALTER TABLE ONLY locations ALTER COLUMN id SET DEFAULT nextval('locations_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: aplol
--

ALTER TABLE ONLY log ALTER COLUMN id SET DEFAULT nextval('log_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: aplol
--

ALTER TABLE ONLY vd_mapping ALTER COLUMN id SET DEFAULT nextval('vd_mapping_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: aplol
--

ALTER TABLE ONLY virtual_domains ALTER COLUMN id SET DEFAULT nextval('virtual_domains_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: aplol
--

ALTER TABLE ONLY wlc ALTER COLUMN id SET DEFAULT nextval('wlc_id_seq'::regclass);


--
-- Name: ap_diff_ethmac_key; Type: CONSTRAINT; Schema: public; Owner: aplol; Tablespace: 
--

ALTER TABLE ONLY aps_diff
    ADD CONSTRAINT ap_diff_ethmac_key UNIQUE (ethmac);


--
-- Name: ap_diff_name_key; Type: CONSTRAINT; Schema: public; Owner: aplol; Tablespace: 
--

ALTER TABLE ONLY aps_diff
    ADD CONSTRAINT ap_diff_name_key UNIQUE (name);


--
-- Name: ap_diff_pkey; Type: CONSTRAINT; Schema: public; Owner: aplol; Tablespace: 
--

ALTER TABLE ONLY aps_diff
    ADD CONSTRAINT ap_diff_pkey PRIMARY KEY (id);


--
-- Name: aps_mac_key; Type: CONSTRAINT; Schema: public; Owner: aplol; Tablespace: 
--

ALTER TABLE ONLY aps
    ADD CONSTRAINT aps_mac_key UNIQUE (ethmac);


--
-- Name: aps_name_key; Type: CONSTRAINT; Schema: public; Owner: aplol; Tablespace: 
--

ALTER TABLE ONLY aps
    ADD CONSTRAINT aps_name_key UNIQUE (name);


--
-- Name: aps_pkey; Type: CONSTRAINT; Schema: public; Owner: aplol; Tablespace: 
--

ALTER TABLE ONLY aps
    ADD CONSTRAINT aps_pkey PRIMARY KEY (id);


--
-- Name: count_pkey; Type: CONSTRAINT; Schema: public; Owner: aplol; Tablespace: 
--

ALTER TABLE ONLY aps_count
    ADD CONSTRAINT count_pkey PRIMARY KEY (id);


--
-- Name: locations_location_key; Type: CONSTRAINT; Schema: public; Owner: aplol; Tablespace: 
--

ALTER TABLE ONLY locations
    ADD CONSTRAINT locations_location_key UNIQUE (location);


--
-- Name: locations_pkey; Type: CONSTRAINT; Schema: public; Owner: aplol; Tablespace: 
--

ALTER TABLE ONLY locations
    ADD CONSTRAINT locations_pkey PRIMARY KEY (id);


--
-- Name: log_pkey; Type: CONSTRAINT; Schema: public; Owner: aplol; Tablespace: 
--

ALTER TABLE ONLY log
    ADD CONSTRAINT log_pkey PRIMARY KEY (id);


--
-- Name: vd_mapping_pkey; Type: CONSTRAINT; Schema: public; Owner: aplol; Tablespace: 
--

ALTER TABLE ONLY vd_mapping
    ADD CONSTRAINT vd_mapping_pkey PRIMARY KEY (id);


--
-- Name: virtual_domains_name_key; Type: CONSTRAINT; Schema: public; Owner: aplol; Tablespace: 
--

ALTER TABLE ONLY virtual_domains
    ADD CONSTRAINT virtual_domains_name_key UNIQUE (name);


--
-- Name: virtual_domains_pkey; Type: CONSTRAINT; Schema: public; Owner: aplol; Tablespace: 
--

ALTER TABLE ONLY virtual_domains
    ADD CONSTRAINT virtual_domains_pkey PRIMARY KEY (id);


--
-- Name: wlc_pkey; Type: CONSTRAINT; Schema: public; Owner: aplol; Tablespace: 
--

ALTER TABLE ONLY wlc
    ADD CONSTRAINT wlc_pkey PRIMARY KEY (id);


--
-- Name: public; Type: ACL; Schema: -; Owner: postgres
--

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM postgres;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO PUBLIC;


--
-- PostgreSQL database dump complete
--

