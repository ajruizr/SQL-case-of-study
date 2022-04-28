-- Database: beers_db

-- DROP DATABASE IF EXISTS beers_db;

CREATE DATABASE beers_db
    WITH 
    OWNER = postgres
    ENCODING = 'UTF8'
    LC_COLLATE = 'Spanish_Mexico.1252'
    LC_CTYPE = 'Spanish_Mexico.1252'
    TABLESPACE = pg_default
    CONNECTION LIMIT = -1;

-- Extension: "uuid-ossp"

-- DROP EXTENSION "uuid-ossp";

CREATE EXTENSION IF NOT EXISTS "uuid-ossp"
    SCHEMA public
    VERSION "1.1";


-- Table: public.accounts

-- DROP TABLE IF EXISTS public.accounts;

CREATE TABLE IF NOT EXISTS public.accounts
(
    account_id integer NOT NULL DEFAULT nextval('accounts_account_id_seq'::regclass),
    capital numeric(12,2),
    name character varying(50) COLLATE pg_catalog."default" NOT NULL,
    CONSTRAINT accounts_pkey PRIMARY KEY (account_id)
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.accounts
    OWNER to postgres;


-- Table: public.beers

-- DROP TABLE IF EXISTS public.beers;

CREATE TABLE IF NOT EXISTS public.beers
(
    beer_id integer NOT NULL DEFAULT nextval('beers_beer_id_seq'::regclass),
    price numeric(4,2),
    name character varying(50) COLLATE pg_catalog."default",
    CONSTRAINT beers_pkey PRIMARY KEY (beer_id),
    CONSTRAINT name UNIQUE (name)
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.beers
    OWNER to postgres;


-- Table: public.notes

-- DROP TABLE IF EXISTS public.notes;

CREATE TABLE IF NOT EXISTS public.notes
(
    beer_id integer NOT NULL DEFAULT nextval('notes_beer_id_seq'::regclass),
    note character varying(2000) COLLATE pg_catalog."default",
    CONSTRAINT beer_id FOREIGN KEY (beer_id)
        REFERENCES public.beers (beer_id) MATCH SIMPLE
        ON UPDATE CASCADE
        ON DELETE RESTRICT
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.notes
    OWNER to postgres;


-- Table: public.sales

-- DROP TABLE IF EXISTS public.sales;

CREATE TABLE IF NOT EXISTS public.sales
(
    sale_id uuid NOT NULL DEFAULT uuid_generate_v4(),
    sale_date timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT sales_pkey PRIMARY KEY (sale_id)
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.sales
    OWNER to postgres;


-- Table: public.bills

-- DROP TABLE IF EXISTS public.bills;

CREATE TABLE IF NOT EXISTS public.bills
(
    sale_id uuid NOT NULL,
    beer_id integer NOT NULL,
    CONSTRAINT beer_id FOREIGN KEY (beer_id)
        REFERENCES public.beers (beer_id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION,
    CONSTRAINT sale_is FOREIGN KEY (sale_id)
        REFERENCES public.sales (sale_id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.bills
    OWNER to postgres;


-- Type: sale

-- DROP TYPE IF EXISTS public.sale;

CREATE TYPE public.sale AS
(
	sale_id uuid,
	account_id integer,
	out_status character varying(25),
	sale_date timestamp with time zone
);

ALTER TYPE public.sale
    OWNER TO postgres;

-- FUNCTION: public.fc_create_sale(integer[], integer, uuid, timestamp with time zone)

-- DROP FUNCTION IF EXISTS public.fc_create_sale(integer[], integer, uuid, timestamp with time zone);

CREATE OR REPLACE FUNCTION public.fc_create_sale(
	param_beer_ids integer[],
	param_account_id integer,
	param_sale_id uuid DEFAULT uuid_generate_v4(),
	param_sale_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP)
    RETURNS sale
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
	out_sale sale;
    var_beer_id integer;
    var_beer_price numeric;
	var_sale_price_amount numeric := 0;
BEGIN

    -- Checking account exists
	IF NOT EXISTS(SELECT * FROM accounts WHERE account_id=param_account_id) THEN
		out_sale.out_status := 'account_id_not_found';
		RETURN out_sale;
	END IF;

    -- Creates a sale
    INSERT INTO sales(sale_id,sale_date) VALUES(param_sale_id, param_sale_date);

    -- Stores all the beer sales in one
    FOREACH var_beer_id IN ARRAY param_beer_ids
    LOOP
        SELECT price INTO var_beer_price FROM beers WHERE beer_id=var_beer_id;
        IF var_beer_price IS NULL THEN
            out_sale.out_status := 'beer_not_found';
			RETURN out_sale;
        ELSE
            var_sale_price_amount := var_sale_price_amount + var_beer_price;
            INSERT INTO bills(sale_id,beer_id) VALUES(param_sale_id,var_beer_id);
        END IF;
    END LOOP;

    -- Updating account capital
    UPDATE accounts SET capital = capital + var_sale_price_amount WHERE account_id = param_account_id;
	
    out_sale.sale_id := param_sale_id;
    out_sale.sale_date := param_sale_date;
    out_sale.account_id := param_account_id;
	out_sale.out_status := 'succeed';
	RETURN out_sale;
END

$BODY$;

ALTER FUNCTION public.fc_create_sale(integer[], integer, uuid, timestamp with time zone)
    OWNER TO postgres;


-- FUNCTION: public.fc_delete_sale(integer, uuid)

-- DROP FUNCTION IF EXISTS public.fc_delete_sale(integer, uuid);

CREATE OR REPLACE FUNCTION public.fc_delete_sale(
	param_account_id integer,
	param_sale_id uuid)
    RETURNS sale
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
	out_sale sale;
    var_beer_id integer;
    var_beer_price numeric;
	var_sale_price_amount numeric := 0;
    var_beers_id integer[];
    var_sale_date timestamp with time zone;
BEGIN

    -- Checking account exists
	IF NOT EXISTS(SELECT * FROM accounts WHERE account_id=param_account_id) THEN
		out_sale.out_status := 'account_id_not_found';
		RETURN out_sale;
	END IF;

    -- Checking if sale exists
    IF NOT EXISTS(SELECT * FROM sales WHERE sale_id=param_sale_id) THEN
		out_sale.out_status := 'sale_id_not_found';
		RETURN out_sale;
	END IF;

    --retrieving sale date
    SELECT sale_date INTO var_sale_date FROM sales WHERE sale_id=param_sale_id;

    --Getting all beers ids from the sale and storing them in var_beer_id[]
    SELECT ARRAY (SELECT beer_id INTO var_beers_id FROM bills WHERE sale_id= param_sale_id);

    --Deleting all bills of the sale
    DELETE FROM bills WHERE sale_id= param_sale_id;

    -- Getting the total sum of sale

    FOREACH var_beer_id IN ARRAY var_beers_id
    LOOP
        SELECT price INTO var_beer_price FROM beers WHERE beer_id=var_beer_id;
        IF var_beer_price IS NULL THEN
            out_sale.out_status := 'beer_not_found';
			RETURN out_sale;
        ELSE
            var_sale_price_amount := var_sale_price_amount + var_beer_price;
        END IF;
    END LOOP;

    -- Updating account capital
    UPDATE accounts SET capital = capital - var_sale_price_amount WHERE account_id = param_account_id;
	
    -- Deletes a sale
    DELETE FROM sales WHERE sale_id=param_sale_id;

    out_sale.sale_id := param_sale_id;
    out_sale.sale_date := var_sale_date;
    out_sale.account_id := param_account_id;
	out_sale.out_status := 'delete was successful';
	RETURN out_sale;
END

$BODY$;

ALTER FUNCTION public.fc_delete_sale(integer, uuid)
    OWNER TO postgres;