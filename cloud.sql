--
-- PostgreSQL database dump
--

-- Dumped from database version 9.6.9
-- Dumped by pg_dump version 9.6.9

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


--
-- Name: dom_username; Type: DOMAIN; Schema: public; Owner: cloud
--

CREATE DOMAIN public.dom_username AS text;


ALTER DOMAIN public.dom_username OWNER TO cloud;

--
-- Name: expire_token(); Type: FUNCTION; Schema: public; Owner: cloud
--

CREATE FUNCTION public.expire_token() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  DELETE FROM tokens WHERE created < NOW() - INTERVAL '3 days';
RETURN NEW;
END;
$$;


ALTER FUNCTION public.expire_token() OWNER TO cloud;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: projects; Type: TABLE; Schema: public; Owner: cloud
--

CREATE TABLE public.projects (
    id integer NOT NULL,
    projectname text NOT NULL,
    ispublic boolean,
    ispublished boolean,
    notes text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    shared_at timestamp with time zone,
    username public.dom_username NOT NULL,
    first_published_at timestamp with time zone,
    remixedfrom integer
);


ALTER TABLE public.projects OWNER TO cloud;

--
-- Name: count_recent_projects; Type: VIEW; Schema: public; Owner: cloud
--

CREATE VIEW public.count_recent_projects AS
 SELECT count(*) AS count
   FROM public.projects
  WHERE (projects.updated_at > (('now'::text)::date - '1 day'::interval));


ALTER TABLE public.count_recent_projects OWNER TO cloud;

--
-- Name: exception_requests; Type: TABLE; Schema: public; Owner: cloud
--

CREATE TABLE public.exception_requests (
    id integer NOT NULL,
    exception_type_id integer NOT NULL,
    path text,
    method character varying(255),
    referer text,
    ip character varying(255),
    data jsonb,
    msg text NOT NULL,
    trace text,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


ALTER TABLE public.exception_requests OWNER TO cloud;

--
-- Name: exception_requests_id_seq; Type: SEQUENCE; Schema: public; Owner: cloud
--

CREATE SEQUENCE public.exception_requests_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.exception_requests_id_seq OWNER TO cloud;

--
-- Name: exception_requests_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: cloud
--

ALTER SEQUENCE public.exception_requests_id_seq OWNED BY public.exception_requests.id;


--
-- Name: exception_types; Type: TABLE; Schema: public; Owner: cloud
--

CREATE TABLE public.exception_types (
    id integer NOT NULL,
    label text NOT NULL,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    count integer DEFAULT 0 NOT NULL,
    status smallint DEFAULT 1 NOT NULL
);


ALTER TABLE public.exception_types OWNER TO cloud;

--
-- Name: exception_types_id_seq; Type: SEQUENCE; Schema: public; Owner: cloud
--

CREATE SEQUENCE public.exception_types_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.exception_types_id_seq OWNER TO cloud;

--
-- Name: exception_types_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: cloud
--

ALTER SEQUENCE public.exception_types_id_seq OWNED BY public.exception_types.id;


--
-- Name: lapis_migrations; Type: TABLE; Schema: public; Owner: cloud
--

CREATE TABLE public.lapis_migrations (
    name character varying(255) NOT NULL
);


ALTER TABLE public.lapis_migrations OWNER TO cloud;

--
-- Name: projects_id_seq; Type: SEQUENCE; Schema: public; Owner: cloud
--

CREATE SEQUENCE public.projects_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.projects_id_seq OWNER TO cloud;

--
-- Name: projects_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: cloud
--

ALTER SEQUENCE public.projects_id_seq OWNED BY public.projects.id;


--
-- Name: recent_projects_2_days; Type: VIEW; Schema: public; Owner: cloud
--

CREATE VIEW public.recent_projects_2_days AS
 SELECT count(*) AS count
   FROM public.projects
  WHERE (projects.updated_at > (('now'::text)::date - '2 days'::interval));


ALTER TABLE public.recent_projects_2_days OWNER TO cloud;

--
-- Name: tokens; Type: TABLE; Schema: public; Owner: cloud
--

CREATE TABLE public.tokens (
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    username public.dom_username NOT NULL,
    purpose text,
    value text NOT NULL
);


ALTER TABLE public.tokens OWNER TO cloud;

--
-- Name: users; Type: TABLE; Schema: public; Owner: cloud
--

CREATE TABLE public.users (
    id integer NOT NULL,
    created_at timestamp with time zone,
    username public.dom_username NOT NULL,
    email text,
    salt text,
    password text,
    about text,
    location text,
    isadmin boolean,
    verified boolean,
    updated_at timestamp with time zone
);


ALTER TABLE public.users OWNER TO cloud;

--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: cloud
--

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.users_id_seq OWNER TO cloud;

--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: cloud
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: exception_requests id; Type: DEFAULT; Schema: public; Owner: cloud
--

ALTER TABLE ONLY public.exception_requests ALTER COLUMN id SET DEFAULT nextval('public.exception_requests_id_seq'::regclass);


--
-- Name: exception_types id; Type: DEFAULT; Schema: public; Owner: cloud
--

ALTER TABLE ONLY public.exception_types ALTER COLUMN id SET DEFAULT nextval('public.exception_types_id_seq'::regclass);


--
-- Name: projects id; Type: DEFAULT; Schema: public; Owner: cloud
--

ALTER TABLE ONLY public.projects ALTER COLUMN id SET DEFAULT nextval('public.projects_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: cloud
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: exception_requests exception_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: cloud
--

ALTER TABLE ONLY public.exception_requests
    ADD CONSTRAINT exception_requests_pkey PRIMARY KEY (id);


--
-- Name: exception_types exception_types_pkey; Type: CONSTRAINT; Schema: public; Owner: cloud
--

ALTER TABLE ONLY public.exception_types
    ADD CONSTRAINT exception_types_pkey PRIMARY KEY (id);


--
-- Name: lapis_migrations lapis_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: cloud
--

ALTER TABLE ONLY public.lapis_migrations
    ADD CONSTRAINT lapis_migrations_pkey PRIMARY KEY (name);


--
-- Name: projects projects_pkey; Type: CONSTRAINT; Schema: public; Owner: cloud
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_pkey PRIMARY KEY (username, projectname);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: cloud
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (username);


--
-- Name: tokens value_pkey; Type: CONSTRAINT; Schema: public; Owner: cloud
--

ALTER TABLE ONLY public.tokens
    ADD CONSTRAINT value_pkey PRIMARY KEY (value);


--
-- Name: exception_requests_exception_type_id_idx; Type: INDEX; Schema: public; Owner: cloud
--

CREATE INDEX exception_requests_exception_type_id_idx ON public.exception_requests USING btree (exception_type_id);


--
-- Name: exception_types_label_idx; Type: INDEX; Schema: public; Owner: cloud
--

CREATE INDEX exception_types_label_idx ON public.exception_types USING btree (label);


--
-- Name: tokens expire_token_trigger; Type: TRIGGER; Schema: public; Owner: cloud
--

CREATE TRIGGER expire_token_trigger AFTER INSERT ON public.tokens FOR EACH STATEMENT EXECUTE PROCEDURE public.expire_token();


--
-- Name: projects projects_username_fkey; Type: FK CONSTRAINT; Schema: public; Owner: cloud
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_username_fkey FOREIGN KEY (username) REFERENCES public.users(username);


--
-- Name: tokens users_fkey; Type: FK CONSTRAINT; Schema: public; Owner: cloud
--

ALTER TABLE ONLY public.tokens
    ADD CONSTRAINT users_fkey FOREIGN KEY (username) REFERENCES public.users(username);


--
-- Name: FUNCTION expire_token(); Type: ACL; Schema: public; Owner: cloud
--

GRANT ALL ON FUNCTION public.expire_token() TO snapanalytics;


--
-- Name: TABLE projects; Type: ACL; Schema: public; Owner: cloud
--

GRANT SELECT ON TABLE public.projects TO snapanalytics;


--
-- Name: TABLE count_recent_projects; Type: ACL; Schema: public; Owner: cloud
--

GRANT SELECT ON TABLE public.count_recent_projects TO snapanalytics;


--
-- Name: TABLE recent_projects_2_days; Type: ACL; Schema: public; Owner: cloud
--

GRANT SELECT ON TABLE public.recent_projects_2_days TO snapanalytics;


--
-- Name: TABLE tokens; Type: ACL; Schema: public; Owner: cloud
--

GRANT SELECT ON TABLE public.tokens TO snapanalytics;


--
-- Name: TABLE users; Type: ACL; Schema: public; Owner: cloud
--

GRANT SELECT ON TABLE public.users TO snapanalytics;


--
-- PostgreSQL database dump complete
--

