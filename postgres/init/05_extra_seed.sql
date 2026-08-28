-- Deterministic mimic data for app.quotes and app.coverages.
-- Depends on 03_insurance_seed.sql having populated customers/agents/products/policies.
--
-- Re-apply to a running container (use the SOURCE_POSTGRES_* values from .env):
--   docker compose exec -T source_postgres psql -U insurance_app -d insurance \
--     -f /docker-entrypoint-initdb.d/05_extra_seed.sql
--
-- Approx row counts: quotes ~1400 (1000 converted 1:1 with policies + 400 lost),
-- coverages ~2500 (2-4 per policy; premium_amount sums to policies.annual_premium).

SELECT setseed(0.4242);

TRUNCATE app.coverages, app.quotes RESTART IDENTITY;

-- ===================== quotes: converted (one per policy) =====================
INSERT INTO app.quotes
WITH conv AS (
  SELECT
    p.policy_id,
    p.customer_id,
    p.agent_id,
    p.product_id,
    p.annual_premium,
    p.effective_date,
    random() AS r_prem,
    random() AS r_lead,
    random() AS r_dec
  FROM app.policies p
)
SELECT
  c.policy_id AS quote_id,
  'QTE-' || lpad(c.policy_id::text, 7, '0'),
  c.customer_id,
  c.agent_id,
  c.product_id,
  'ACCEPTED',
  round((c.annual_premium * (0.90 + c.r_prem * 0.20))::numeric, 2),
  (c.effective_date - (floor(c.r_lead * 28) + 3)::int)::timestamptz + INTERVAL '10 hours',
  (c.effective_date - (floor(c.r_dec * 3))::int),
  c.policy_id
FROM conv c;

-- ===================== quotes: not converted (1001..1400) =====================
INSERT INTO app.quotes
WITH base AS (
  SELECT
    1000 + gs AS quote_id,
    (1 + floor(random() * 800))::int AS customer_id,
    (1 + floor(random() * 30))::int  AS agent_id,
    (1 + floor(random() * 6))::int   AS product_id,
    DATE '2024-06-01' + (floor(random() * 800))::int AS created_date,
    random() AS r_status,
    random() AS r_prem,
    random() AS r_dec
  FROM generate_series(1, 400) gs
),
classified AS (
  SELECT b.*,
    CASE
      WHEN b.r_status < 0.45 THEN 'DECLINED'
      WHEN b.r_status < 0.75 THEN 'EXPIRED'
      WHEN b.r_status < 0.92 THEN 'SENT'
      ELSE 'DRAFT'
    END AS status
  FROM base b
)
SELECT
  c.quote_id,
  'QTE-' || lpad(c.quote_id::text, 7, '0'),
  c.customer_id,
  c.agent_id,
  c.product_id,
  c.status,
  round((pr.base_annual_premium * (0.70 + c.r_prem * 0.80))::numeric, 2),
  c.created_date::timestamptz + INTERVAL '10 hours',
  CASE
    WHEN c.status IN ('DECLINED', 'EXPIRED')
    THEN LEAST(c.created_date + (floor(c.r_dec * 30) + 5)::int, CURRENT_DATE)
    ELSE NULL
  END,
  NULL::bigint
FROM classified c
JOIN app.products pr ON pr.product_id = c.product_id;

-- ===================== coverages =====================
INSERT INTO app.coverages
WITH catalogue(code, name, lob, tier, lim_lo, lim_hi, deductible) AS (
  VALUES
    -- AUTO
    ('BODILY_INJURY',     'Bodily Injury Liability',   'AUTO', 'base',  100000, 500000,    0),
    ('PROPERTY_DAMAGE',   'Property Damage Liability',  'AUTO', 'base',   50000, 150000,    0),
    ('COMPREHENSIVE',     'Comprehensive',             'AUTO', 'extra',  15000,  60000,  500),
    ('COLLISION',         'Collision',                 'AUTO', 'extra',  15000,  60000, 1000),
    -- HOME
    ('DWELLING',          'Dwelling',                  'HOME', 'base',  200000, 800000, 1000),
    ('LIABILITY',         'Personal Liability',        'HOME', 'base',  100000, 500000,    0),
    ('PERSONAL_PROPERTY', 'Personal Property',         'HOME', 'extra',  50000, 250000,  500),
    ('MEDICAL_PAYMENTS',  'Medical Payments',          'HOME', 'extra',   1000,  10000,    0),
    -- LIFE / UMBRELLA
    ('DEATH_BENEFIT',     'Death Benefit',             'LIFE', 'base',  100000, 750000,    0),
    ('EXCESS_LIABILITY',  'Excess Liability',      'UMBRELLA', 'base', 1000000, 5000000,   0)
),
candidates AS (
  SELECT
    p.policy_id,
    p.annual_premium,
    cat.code,
    cat.name,
    cat.tier,
    cat.lim_lo,
    cat.lim_hi,
    cat.deductible,
    random() AS r_keep
  FROM app.policies p
  JOIN app.products pr ON pr.product_id = p.product_id
  JOIN catalogue cat ON cat.lob = pr.line_of_business
),
lines AS (
  -- every 'base' coverage, plus each 'extra' with 65% probability
  SELECT policy_id, annual_premium, code, name, lim_lo, lim_hi, deductible
  FROM candidates
  WHERE tier = 'base' OR r_keep < 0.65
),
numbered AS (
  SELECT
    l.*,
    row_number() OVER (PARTITION BY l.policy_id ORDER BY l.code) AS rn,
    count(*)     OVER (PARTITION BY l.policy_id)                 AS n_cov,
    round(l.annual_premium / count(*) OVER (PARTITION BY l.policy_id), 2) AS even_share
  FROM lines l
)
SELECT
  row_number() OVER (ORDER BY policy_id, code) AS coverage_id,
  policy_id,
  code,
  name,
  round((lim_lo + random() * (lim_hi - lim_lo))::numeric, -2) AS limit_amount,
  deductible,
  -- first coverage on the policy absorbs the rounding remainder, so the
  -- coverage premiums sum exactly to policies.annual_premium
  CASE WHEN rn = 1
       THEN annual_premium - even_share * (n_cov - 1)
       ELSE even_share
  END AS premium_amount
FROM numbered;

-- ===================== sanity summary =====================
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT 'quotes' t, count(*) c FROM app.quotes
    UNION ALL SELECT 'quotes converted', count(*) FROM app.quotes WHERE converted_policy_id IS NOT NULL
    UNION ALL SELECT 'coverages',        count(*) FROM app.coverages
    UNION ALL SELECT 'policies w/o coverage',
                     count(*) FROM app.policies p
                     WHERE NOT EXISTS (SELECT 1 FROM app.coverages c WHERE c.policy_id = p.policy_id)
  LOOP
    RAISE NOTICE '% = %', rpad(r.t, 22), r.c;
  END LOOP;
END $$;
