-- =============================================================================
-- Faker SQL: schema and lookup tables
-- =============================================================================
-- Every lookup table is shared by all locales and has a `locale` column, so a
-- new locale is added by inserting rows; no table or function changes.
--
-- Weighted tables carry a `weight` (relative frequency, set by the data) and a
-- `cdf` (cumulative distribution function: running total of weights inside
-- one group divided by the group total, set by faker.refresh_weights()).
-- The B-tree index on (group..., cdf) turns a weighted random pick into one
-- index probe; see the faker.pick_* functions.
-- =============================================================================

DROP SCHEMA IF EXISTS faker CASCADE;
CREATE SCHEMA faker;

COMMENT ON SCHEMA faker IS 'Faker SQL: deterministic fake user data generator implemented as stored procedures';

-- -----------------------------------------------------------------------------
-- Locales
-- -----------------------------------------------------------------------------
CREATE TABLE faker.locales (
    code          text PRIMARY KEY,                -- 'en_US', 'de_DE'
    title         text NOT NULL,                   -- human readable name
    language      text NOT NULL,                   -- ISO 639-1
    country       text NOT NULL,                   -- ISO 3166-1 alpha-2
    units         text NOT NULL DEFAULT 'metric' CHECK (units IN ('metric', 'imperial')),
    decimal_mark  text NOT NULL DEFAULT '.',       -- '.' or ','
    sort_order    int  NOT NULL DEFAULT 0
);

-- -----------------------------------------------------------------------------
-- Given names and surnames of all locales
-- -----------------------------------------------------------------------------
CREATE TABLE faker.names (
    locale      text    NOT NULL REFERENCES faker.locales ON DELETE CASCADE,
    kind        text    NOT NULL CHECK (kind IN ('first', 'last')),
    gender      char(1) NOT NULL DEFAULT 'X' CHECK (gender IN ('M', 'F', 'X')),  -- X = any
    value       text    NOT NULL,
    weight      int     NOT NULL DEFAULT 1 CHECK (weight > 0),
    cdf         double precision,
    PRIMARY KEY (locale, kind, gender, value)
);
CREATE INDEX names_pick_idx ON faker.names (locale, kind, gender, cdf);

-- -----------------------------------------------------------------------------
-- Places: postal code + city + region (state / Bundesland)
-- -----------------------------------------------------------------------------
CREATE TABLE faker.places (
    locale       text NOT NULL REFERENCES faker.locales ON DELETE CASCADE,
    postal_code  text NOT NULL,
    city         text NOT NULL,
    region       text NOT NULL,
    region_code  text NOT NULL,
    weight       int  NOT NULL DEFAULT 1 CHECK (weight > 0),
    cdf          double precision,
    PRIMARY KEY (locale, postal_code, city)
);
CREATE INDEX places_pick_idx ON faker.places (locale, cdf);

-- -----------------------------------------------------------------------------
-- Words: every small or medium vocabulary of a locale, told apart by `kind`
--   title, salutation, name_suffix, particle, street, street_suffix,
--   street_direction, email_domain, eye_color, hair_color, blood_type, ...
-- `alt` is an alternative spelling, usually an abbreviation
-- ('Street' / 'St', 'Goethestraße' / 'Goethestr.').
-- -----------------------------------------------------------------------------
CREATE TABLE faker.words (
    locale      text    NOT NULL REFERENCES faker.locales ON DELETE CASCADE,
    kind        text    NOT NULL,
    gender      char(1) NOT NULL DEFAULT 'X' CHECK (gender IN ('M', 'F', 'X')),
    value       text    NOT NULL,
    alt         text,
    weight      int     NOT NULL DEFAULT 1 CHECK (weight > 0),
    cdf         double precision,
    PRIMARY KEY (locale, kind, gender, value)
);
CREATE INDEX words_pick_idx ON faker.words (locale, kind, gender, cdf);

-- -----------------------------------------------------------------------------
-- Formats: templates with {placeholders} and digit/letter masks
--   name, street_address, address, secondary, house_number, phone, email
-- -----------------------------------------------------------------------------
CREATE TABLE faker.formats (
    locale      text NOT NULL REFERENCES faker.locales ON DELETE CASCADE,
    kind        text NOT NULL,
    pattern     text NOT NULL,
    weight      int  NOT NULL DEFAULT 1 CHECK (weight > 0),
    cdf         double precision,
    PRIMARY KEY (locale, kind, pattern)
);
CREATE INDEX formats_pick_idx ON faker.formats (locale, kind, cdf);

-- -----------------------------------------------------------------------------
-- Body statistics: parameters of the height and BMI distributions
-- -----------------------------------------------------------------------------
CREATE TABLE faker.body_stats (
    locale          text    NOT NULL REFERENCES faker.locales ON DELETE CASCADE,
    gender          char(1) NOT NULL CHECK (gender IN ('M', 'F')),
    height_mean_cm  double precision NOT NULL,   -- height ~ Normal(mean, sd)
    height_sd_cm    double precision NOT NULL,
    bmi_median      double precision NOT NULL,   -- BMI ~ LogNormal(ln(median), sigma)
    bmi_sigma       double precision NOT NULL,
    PRIMARY KEY (locale, gender)
);

-- -----------------------------------------------------------------------------
-- Markov chain of order 2 for random text (one chain per locale)
-- A state is a pair of consecutive words (w1, w2). A transition from state
-- (w1, w2) emits next_word and moves to state (w2, next_word), whose id is
-- stored in next_state_id so the walk never has to search by text.
-- -----------------------------------------------------------------------------
CREATE TABLE faker.markov_states (
    state_id      int  PRIMARY KEY,
    locale        text NOT NULL REFERENCES faker.locales ON DELETE CASCADE,
    w1            text NOT NULL,
    w2            text NOT NULL,
    start_weight  int  NOT NULL DEFAULT 0,       -- > 0: the pair starts sentences
    start_cdf     double precision               -- CDF of start_weight per locale
);
CREATE INDEX markov_states_start_idx ON faker.markov_states (locale, start_cdf) WHERE start_weight > 0;

CREATE TABLE faker.markov_transitions (
    state_id       int  NOT NULL REFERENCES faker.markov_states ON DELETE CASCADE,
    next_word      text NOT NULL,
    next_state_id  int  NOT NULL,
    weight         int  NOT NULL CHECK (weight > 0),
    cdf            double precision,
    PRIMARY KEY (state_id, next_word)
);
CREATE INDEX markov_transitions_pick_idx ON faker.markov_transitions (state_id, cdf);

-- -----------------------------------------------------------------------------
-- faker.refresh_weights(): recompute every cdf column.
-- Call after inserting or changing lookup rows:  CALL faker.refresh_weights();
--   cdf(row) = (sum of the weights of its group up to and including the row)
--              / (sum of the weights of its group)
-- so the rows of a group split [0, 1) into intervals of length weight / total
-- and the last row has cdf = 1. Rows are ordered with the "C" collation, so
-- the result (and every generated user) is identical on any server.
-- -----------------------------------------------------------------------------
CREATE PROCEDURE faker.refresh_weights()
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE faker.names t SET cdf = c.cdf
    FROM (SELECT locale, kind, gender, value,
                 sum(weight) OVER (PARTITION BY locale, kind, gender ORDER BY value COLLATE "C"
                                   ROWS UNBOUNDED PRECEDING)::double precision
                 / sum(weight) OVER (PARTITION BY locale, kind, gender) AS cdf
          FROM faker.names) c
    WHERE (t.locale, t.kind, t.gender, t.value) = (c.locale, c.kind, c.gender, c.value)
      AND t.cdf IS DISTINCT FROM c.cdf;

    UPDATE faker.places t SET cdf = c.cdf
    FROM (SELECT locale, postal_code, city,
                 sum(weight) OVER (PARTITION BY locale ORDER BY postal_code COLLATE "C", city COLLATE "C"
                                   ROWS UNBOUNDED PRECEDING)::double precision
                 / sum(weight) OVER (PARTITION BY locale) AS cdf
          FROM faker.places) c
    WHERE (t.locale, t.postal_code, t.city) = (c.locale, c.postal_code, c.city)
      AND t.cdf IS DISTINCT FROM c.cdf;

    UPDATE faker.words t SET cdf = c.cdf
    FROM (SELECT locale, kind, gender, value,
                 sum(weight) OVER (PARTITION BY locale, kind, gender ORDER BY value COLLATE "C"
                                   ROWS UNBOUNDED PRECEDING)::double precision
                 / sum(weight) OVER (PARTITION BY locale, kind, gender) AS cdf
          FROM faker.words) c
    WHERE (t.locale, t.kind, t.gender, t.value) = (c.locale, c.kind, c.gender, c.value)
      AND t.cdf IS DISTINCT FROM c.cdf;

    UPDATE faker.formats t SET cdf = c.cdf
    FROM (SELECT locale, kind, pattern,
                 sum(weight) OVER (PARTITION BY locale, kind ORDER BY pattern COLLATE "C"
                                   ROWS UNBOUNDED PRECEDING)::double precision
                 / sum(weight) OVER (PARTITION BY locale, kind) AS cdf
          FROM faker.formats) c
    WHERE (t.locale, t.kind, t.pattern) = (c.locale, c.kind, c.pattern)
      AND t.cdf IS DISTINCT FROM c.cdf;

    UPDATE faker.markov_transitions t SET cdf = c.cdf
    FROM (SELECT state_id, next_word,
                 sum(weight) OVER (PARTITION BY state_id ORDER BY next_word COLLATE "C"
                                   ROWS UNBOUNDED PRECEDING)::double precision
                 / sum(weight) OVER (PARTITION BY state_id) AS cdf
          FROM faker.markov_transitions) c
    WHERE (t.state_id, t.next_word) = (c.state_id, c.next_word)
      AND t.cdf IS DISTINCT FROM c.cdf;

    UPDATE faker.markov_states s SET start_cdf = c.cdf
    FROM (SELECT state_id,
                 sum(start_weight) OVER (PARTITION BY locale ORDER BY state_id
                                         ROWS UNBOUNDED PRECEDING)::double precision
                 / sum(start_weight) OVER (PARTITION BY locale) AS cdf
          FROM faker.markov_states WHERE start_weight > 0) c
    WHERE s.state_id = c.state_id AND s.start_cdf IS DISTINCT FROM c.cdf;
END;
$$;

COMMENT ON PROCEDURE faker.refresh_weights() IS
    'Recomputes the cdf columns of all lookup tables. Call after loading or editing lookup data.';
