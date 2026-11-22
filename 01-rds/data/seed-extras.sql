-- ==============================================================================
-- FILE: seed-extras.sql
-- ==============================================================================
-- Runs after the Pagila load, as the master user, in the pagila database.
--
-- 1) Creates the agent's read-only login role (IAM auth, no password).
-- 2) Plants a handful of known problems so a viewer can grade the audit:
--    the README lists every one of them.
--
-- psql variable: agent_user (passed with -v agent_user=...)
-- ==============================================================================

\set ON_ERROR_STOP on

CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- ------------------------------------------------------------------------------
-- READ-ONLY AGENT ROLE
-- ------------------------------------------------------------------------------
-- rds_iam switches the role to token authentication: a password login is
-- refused even if one were set. pg_read_all_data covers every table without
-- per-table grants; pg_monitor exposes pg_stat_statements and the size and
-- index statistics the audit reads. The read-only default is a second fence
-- behind the grants.
-- ------------------------------------------------------------------------------

SELECT format('CREATE ROLE %I LOGIN', :'agent_user')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'agent_user')
\gexec

GRANT rds_iam TO :"agent_user";
GRANT pg_read_all_data TO :"agent_user";
GRANT pg_monitor TO :"agent_user";
GRANT CONNECT ON DATABASE pagila TO :"agent_user";
ALTER ROLE :"agent_user" SET default_transaction_read_only = on;

-- ------------------------------------------------------------------------------
-- PLANTED INDEX PROBLEMS
-- ------------------------------------------------------------------------------
-- A straight duplicate of idx_last_name, and an index nothing ever queries.
-- (Pagila already ships duplicate customer_id indexes on every payment
-- partition, which the agent should also catch.)
-- ------------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_customer_last_name_dup
  ON customer (last_name);
CREATE INDEX IF NOT EXISTS idx_rental_return_date
  ON rental (return_date);

-- ------------------------------------------------------------------------------
-- PLANTED ANOMALOUS ROWS
-- ------------------------------------------------------------------------------

-- A negative payment and a payment far above any rental price.
INSERT INTO payment (customer_id, staff_id, rental_id, amount, payment_date)
VALUES (130, 1, 1520, -45.00, '2022-03-15 14:02:00+00'),
       (459, 2, 1,    999.99, '2022-04-02 03:11:00+00');

-- Three rentals returned before they were rented.
UPDATE rental
   SET return_date = rental_date - interval '3 days'
 WHERE rental_id IN (1001, 2002, 3003);

-- A duplicate customer: same name, email and address as customer 1.
INSERT INTO customer (store_id, first_name, last_name, email, address_id,
                      active)
SELECT store_id, first_name, last_name, email, address_id, active
  FROM customer
 WHERE customer_id = 1;

ANALYZE;
