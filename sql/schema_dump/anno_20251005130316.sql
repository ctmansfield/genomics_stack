--
-- PostgreSQL database dump
--

\restrict Yzb8iptz6XHWm41aWRbyj9lwJMP0xFBb33iixWKMgB2Qdtx7V41Ha0Br7IBMV4t

-- Dumped from database version 16.10 (Debian 16.10-1.pgdg13+1)
-- Dumped by pg_dump version 16.10 (Ubuntu 16.10-0ubuntu0.24.04.1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: anno; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA anno;


--
-- Name: first_rsid(text); Type: FUNCTION; Schema: anno; Owner: -
--

CREATE FUNCTION anno.first_rsid(existing_variation text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$DECLARE
  t text := COALESCE(existing_variation,'');
  a text[];
BEGIN
  IF t = '' THEN RETURN NULL; END IF;
  a := regexp_match(t, '(rs[0-9]+)');
  IF a IS NULL OR array_length(a,1) IS NULL THEN RETURN NULL; END IF;
  RETURN a[1];
END;$$;


--
-- Name: vep_impact_rank(text); Type: FUNCTION; Schema: anno; Owner: -
--

CREATE FUNCTION anno.vep_impact_rank(impact text) RETURNS integer
    LANGUAGE sql IMMUTABLE
    AS $_$  SELECT CASE UPPER(COALESCE($1,''))
           WHEN 'HIGH' THEN 4
           WHEN 'MODERATE' THEN 3
           WHEN 'LOW' THEN 2
           WHEN 'MODIFIER' THEN 1
           ELSE 0
         END$_$;


--
-- PostgreSQL database dump complete
--

\unrestrict Yzb8iptz6XHWm41aWRbyj9lwJMP0xFBb33iixWKMgB2Qdtx7V41Ha0Br7IBMV4t

