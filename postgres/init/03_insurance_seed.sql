-- Deterministic mimic data for the app.* insurance schema.
--
-- setseed() fixes the PRNG so every rebuild produces byte-identical data.
-- Re-apply to a running container (use the SOURCE_POSTGRES_* values from .env):
--   docker compose exec -T source_postgres psql -U insurance_app -d insurance \
--     -f /docker-entrypoint-initdb.d/03_insurance_seed.sql
--
-- Approx row counts: customers 800, agents 30, products 6, policies 1000,
-- premium_payments ~2500, claims 400, claim_payments ~540.

SELECT setseed(0.4242);

TRUNCATE app.claim_payments, app.claims, app.premium_payments,
         app.policies, app.products, app.agents, app.customers RESTART IDENTITY CASCADE;

-- ===================== customers (800) =====================
INSERT INTO app.customers
WITH n(fnames, lnames, cities, states, streets) AS (
  VALUES (
    ARRAY['James','Mary','John','Patricia','Robert','Jennifer','Michael','Linda','William','Elizabeth',
          'David','Barbara','Richard','Susan','Joseph','Jessica','Thomas','Sarah','Charles','Karen',
          'Christopher','Nancy','Daniel','Lisa','Matthew','Betty','Anthony','Margaret','Mark','Sandra',
          'Donald','Ashley','Steven','Kimberly','Paul','Emily','Andrew','Donna','Joshua','Michelle'],
    ARRAY['Smith','Johnson','Williams','Brown','Jones','Garcia','Miller','Davis','Rodriguez','Martinez',
          'Hernandez','Lopez','Gonzalez','Wilson','Anderson','Thomas','Taylor','Moore','Jackson','Martin',
          'Lee','Perez','Thompson','White','Harris','Sanchez','Clark','Ramirez','Lewis','Robinson'],
    ARRAY['Springfield','Franklin','Clinton','Georgetown','Salem','Madison','Arlington','Ashland','Dover','Oxford',
          'Riverside','Bristol','Fairview','Kingston','Newport','Manchester','Milford','Auburn','Dayton','Hudson'],
    ARRAY['CA','TX','NY','FL','IL','PA','OH','GA','NC','MI','NJ','VA','WA','AZ','MA','TN','IN','MO','MD','WI'],
    ARRAY['Main St','Oak Ave','Maple Dr','Cedar Ln','Pine St','Elm St','Washington Ave','Lake Rd','Hill St','Park Ave']
  )
)
SELECT
  gs,
  n.fnames[1 + floor(random() * array_length(n.fnames, 1))::int],
  n.lnames[1 + floor(random() * array_length(n.lnames, 1))::int],
  'cust' || gs || '@example.com',
  '+1-' || (200 + floor(random() * 700))::int || '-'
        || lpad(floor(random() * 1000)::int::text, 3, '0') || '-'
        || lpad(floor(random() * 10000)::int::text, 4, '0'),
  DATE '2004-12-31' - (floor(random() * 20800) + 200)::int,
  CASE WHEN random() < 0.49 THEN 'F' WHEN random() < 0.98 THEN 'M' ELSE 'X' END,
  (100 + floor(random() * 8900))::int || ' '
        || n.streets[1 + floor(random() * array_length(n.streets, 1))::int],
  n.cities[1 + floor(random() * array_length(n.cities, 1))::int],
  n.states[1 + floor(random() * array_length(n.states, 1))::int],
  lpad(floor(random() * 100000)::int::text, 5, '0'),
  TIMESTAMPTZ '2021-01-01 00:00:00+00'
        + (floor(random() * 1600) || ' days')::interval
        + (floor(random() * 86400) || ' seconds')::interval
FROM generate_series(1, 800) gs, n;

-- ===================== agents (30) =====================
INSERT INTO app.agents
WITH n(fnames, lnames, regions) AS (
  VALUES (
    ARRAY['Alex','Jordan','Taylor','Morgan','Casey','Jamie','Riley','Avery','Quinn','Cameron',
          'Drew','Skyler','Reese','Parker','Hayden','Rowan','Emerson','Finley','Sawyer','Marlowe'],
    ARRAY['Bennett','Coleman','Fleming','Griffin','Hayes','Iverson','Jennings','Kramer','Lambert','Mercer',
          'Nolan','Osborne','Pierce','Quill','Reyes','Sutton','Tucker','Underwood','Vaughn','Walsh'],
    ARRAY['NORTHEAST','SOUTHEAST','MIDWEST','WEST','SOUTHWEST']
  )
)
SELECT
  gs,
  n.fnames[1 + floor(random() * array_length(n.fnames, 1))::int],
  n.lnames[1 + floor(random() * array_length(n.lnames, 1))::int],
  'agent' || gs || '@acme-insurance.example',
  DATE '2014-01-01' + (floor(random() * 3800))::int,
  n.regions[1 + floor(random() * array_length(n.regions, 1))::int],
  round((0.040 + random() * 0.110)::numeric, 3),
  random() < 0.85
FROM generate_series(1, 30) gs, n;

-- ===================== products (6) =====================
INSERT INTO app.products (product_id, product_code, product_name, line_of_business, base_annual_premium) VALUES
  (1, 'AUTO-STD',   'Standard Auto',     'AUTO',     1150.00),
  (2, 'AUTO-PREM',  'Premium Auto',      'AUTO',     1875.00),
  (3, 'HOME-OWN',   'Homeowners',        'HOME',     1425.00),
  (4, 'HOME-CONDO', 'Condo Owners',      'HOME',      880.00),
  (5, 'LIFE-TERM',  '20-Year Term Life', 'LIFE',      540.00),
  (6, 'UMB-1M',     'Umbrella $1M',      'UMBRELLA',  395.00);

-- ===================== policies (1000) =====================
INSERT INTO app.policies
WITH base AS (
  SELECT
    gs AS policy_id,
    (1 + floor(random() * 800))::int AS customer_id,
    (1 + floor(random() * 30))::int  AS agent_id,
    (1 + floor(random() * 6))::int   AS product_id,
    DATE '2024-01-01' + (floor(random() * 850))::int AS effective_date,
    random() AS r_status,
    random() AS r_prem,
    (ARRAY['ANNUAL','SEMIANNUAL','QUARTERLY','MONTHLY'])[1 + floor(random() * 4)::int] AS payment_frequency
  FROM generate_series(1, 1000) gs
)
SELECT
  b.policy_id,
  'POL-' || lpad(b.policy_id::text, 7, '0'),
  b.customer_id,
  b.agent_id,
  b.product_id,
  CASE
    WHEN b.r_status < 0.06 THEN 'CANCELLED'
    WHEN b.r_status < 0.18 THEN 'LAPSED'
    WHEN (b.effective_date + INTERVAL '1 year')::date < CURRENT_DATE THEN 'EXPIRED'
    ELSE 'ACTIVE'
  END,
  b.effective_date,
  (b.effective_date + INTERVAL '1 year')::date,
  round((p.base_annual_premium * (0.75 + b.r_prem * 0.70))::numeric, 2),
  b.payment_frequency,
  (b.effective_date - (floor(random() * 20))::int)::timestamptz + INTERVAL '9 hours'
FROM base b
JOIN app.products p ON p.product_id = b.product_id;

-- ===================== premium_payments (first <=4 installments per policy) ==
INSERT INTO app.premium_payments
WITH sched AS (
  SELECT
    p.policy_id,
    p.effective_date,
    p.annual_premium,
    CASE p.payment_frequency
      WHEN 'ANNUAL' THEN 1 WHEN 'SEMIANNUAL' THEN 2
      WHEN 'QUARTERLY' THEN 4 ELSE 12 END AS installments,
    CASE p.payment_frequency
      WHEN 'ANNUAL' THEN 12 WHEN 'SEMIANNUAL' THEN 6
      WHEN 'QUARTERLY' THEN 3 ELSE 1 END AS month_step
  FROM app.policies p
),
rows AS (
  SELECT
    s.policy_id,
    i AS installment_number,
    (s.effective_date + ((i - 1) * s.month_step || ' months')::interval)::date AS due_date,
    round((s.annual_premium / s.installments)::numeric, 2) AS amount,
    random() AS r_pay,
    random() AS r_days,
    random() AS r_method
  FROM sched s
  CROSS JOIN LATERAL generate_series(1, LEAST(s.installments, 4)) AS i
),
classified AS (
  SELECT r.*,
    CASE
      WHEN r.due_date > CURRENT_DATE THEN 'PENDING'
      WHEN r.r_pay < 0.90 THEN 'PAID'
      WHEN r.r_pay < 0.97 THEN 'LATE'
      WHEN r.r_pay < 0.985 THEN 'FAILED'
      ELSE 'PENDING'
    END AS status
  FROM rows r
)
SELECT
  row_number() OVER (ORDER BY policy_id, installment_number),
  policy_id,
  installment_number,
  due_date,
  CASE status
    WHEN 'PAID' THEN LEAST(due_date + (floor(r_days * 8))::int, CURRENT_DATE)
    WHEN 'LATE' THEN LEAST(due_date + (floor(r_days * 25) + 8)::int, CURRENT_DATE)
    ELSE NULL
  END,
  amount,
  CASE WHEN status IN ('PAID','LATE')
       THEN (ARRAY['CARD','ACH','CHECK','CASH'])[1 + floor(r_method * 4)::int]
       ELSE NULL END,
  status
FROM classified;

-- ===================== claims (400) =====================
INSERT INTO app.claims
WITH base AS (
  SELECT
    gs AS claim_id,
    (1 + floor(random() * 1000))::int AS policy_id,
    random() AS r_type, random() AS r_status, random() AS r_when,
    random() AS r_lag,  random() AS r_est,    random() AS r_ratio, random() AS r_close
  FROM generate_series(1, 400) gs
),
joined AS (
  SELECT b.*,
    p.effective_date,
    LEAST((p.effective_date + INTERVAL '1 year')::date, CURRENT_DATE) AS window_end,
    pr.line_of_business
  FROM base b
  JOIN app.policies p  ON p.policy_id  = b.policy_id
  JOIN app.products pr ON pr.product_id = p.product_id
),
computed AS (
  SELECT j.*,
    (j.effective_date
      + (floor(j.r_when * GREATEST(1, (j.window_end - j.effective_date))))::int) AS incident_date
  FROM joined j
),
c2 AS (
  SELECT c.*,
    LEAST(c.incident_date + (floor(c.r_lag * 12))::int, CURRENT_DATE) AS reported_date,
    CASE
      WHEN c.r_status < 0.55 THEN 'CLOSED'
      WHEN c.r_status < 0.68 THEN 'DENIED'
      WHEN c.r_status < 0.80 THEN 'APPROVED'
      WHEN c.r_status < 0.90 THEN 'IN_REVIEW'
      ELSE 'OPEN'
    END AS status,
    round((300 + c.r_est * c.r_est * 45000)::numeric, 2) AS estimated_amount
  FROM computed c
)
SELECT
  c2.claim_id,
  'CLM-' || lpad(c2.claim_id::text, 7, '0'),
  c2.policy_id,
  CASE c2.line_of_business
    WHEN 'AUTO' THEN (ARRAY['COLLISION','THEFT','WINDSHIELD','VANDALISM','LIABILITY'])[1 + floor(c2.r_type * 5)::int]
    WHEN 'HOME' THEN (ARRAY['FIRE','WATER_DAMAGE','HAIL','THEFT','LIABILITY'])[1 + floor(c2.r_type * 5)::int]
    WHEN 'LIFE' THEN 'DEATH_BENEFIT'
    ELSE 'LIABILITY'
  END,
  c2.status,
  c2.incident_date,
  c2.reported_date,
  CASE WHEN c2.status IN ('CLOSED','DENIED')
       THEN LEAST(c2.reported_date + (floor(c2.r_close * 70) + 5)::int, CURRENT_DATE)
       ELSE NULL END,
  c2.estimated_amount,
  CASE
    WHEN c2.status = 'CLOSED'   THEN round((c2.estimated_amount * (0.55 + c2.r_ratio * 0.45))::numeric, 2)
    WHEN c2.status = 'APPROVED' THEN round((c2.estimated_amount * (0.20 + c2.r_ratio * 0.45))::numeric, 2)
    ELSE 0
  END,
  CASE c2.status
    WHEN 'CLOSED'    THEN 'Claim settled and paid.'
    WHEN 'DENIED'    THEN 'Claim denied after investigation.'
    WHEN 'APPROVED'  THEN 'Claim approved; payment in progress.'
    WHEN 'IN_REVIEW' THEN 'Adjuster reviewing documentation.'
    ELSE 'Claim reported; awaiting assignment.'
  END
FROM c2;

-- ===================== claim_payments =====================
INSERT INTO app.claim_payments
WITH paid AS (
  SELECT c.claim_id, c.paid_amount,
         COALESCE(c.closed_date, c.reported_date + 30) AS base_date,
         cu.first_name || ' ' || cu.last_name AS payee
  FROM app.claims c
  JOIN app.policies  p  ON p.policy_id   = c.policy_id
  JOIN app.customers cu ON cu.customer_id = p.customer_id
  WHERE c.paid_amount > 0
),
lines AS (
  SELECT claim_id, base_date AS payment_date, paid_amount AS amount,
         'INDEMNITY' AS payment_type, payee AS payee_name, 0 AS ord
  FROM paid
  UNION ALL
  SELECT claim_id,
         base_date - (floor(random() * 20))::int,
         round((150 + random() * 2400)::numeric, 2),
         'EXPENSE',
         (ARRAY['ClaimsPro Adjusters LLC','Metro Legal Group','Rapid Restoration Inc','Apex Salvage Co'])[1 + floor(random() * 4)::int],
         1
  FROM paid
  WHERE random() < 0.35
)
SELECT
  row_number() OVER (ORDER BY claim_id, ord),
  claim_id, payment_date, amount, payment_type, payee_name
FROM lines;

-- ===================== sanity summary =====================
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT 'customers' t, count(*) c FROM app.customers
    UNION ALL SELECT 'agents',           count(*) FROM app.agents
    UNION ALL SELECT 'products',          count(*) FROM app.products
    UNION ALL SELECT 'policies',          count(*) FROM app.policies
    UNION ALL SELECT 'premium_payments',  count(*) FROM app.premium_payments
    UNION ALL SELECT 'claims',            count(*) FROM app.claims
    UNION ALL SELECT 'claim_payments',    count(*) FROM app.claim_payments
  LOOP
    RAISE NOTICE '% = %', rpad(r.t, 18), r.c;
  END LOOP;
END $$;
