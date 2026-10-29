-- =============================================================================
-- Faker SQL: field generators
-- =============================================================================
-- Each generator takes a locale and its own 64-bit key and returns one row.
-- Inside a generator every random decision uses its own stream number, so
-- adding a decision never shifts the others. Optional parts (a middle name,
-- a title, an apartment number) are only looked up when the chosen template
-- contains their placeholder.
-- =============================================================================

-- person_name(locale, key): gender, name parts and the formatted full name.
-- Name templates (formats.kind = 'name') may use:
--   {first} {middle} {mi} (middle initial) {last} {last2} (second surname)
--   {title} {salutation} {suffix} {particle}
-- e.g. '{title} {first} {mi}. {last}' -> 'Dr. Laura J. Simmons'
--      '{salutation} {first}-{middle} {last}' -> 'Herr Hans-Peter Krüger'
CREATE FUNCTION faker.person_name(p_locale text, p_key bigint)
RETURNS TABLE (gender char(1), first_name text, middle_name text, last_name text, full_name text)
LANGUAGE sql STABLE PARALLEL SAFE AS $$
    SELECT g.gender, f.value, x.middle, l.value,
           faker.fill_template(fmt.pattern, jsonb_build_object(
               'first', f.value,
               'middle', x.middle,
               'mi', left(x.middle, 1),
               'last', l.value,
               'last2', x.last2,
               'title', x.title,
               'salutation', x.salutation,
               'suffix', x.suffix,
               'particle', x.particle))
    FROM (SELECT (CASE WHEN faker.random_bool(p_key, 0) THEN 'M' ELSE 'F' END)::char(1) AS gender OFFSET 0) g
    CROSS JOIN LATERAL faker.pick_name(p_locale, 'first', g.gender, faker.random_uniform(p_key, 1)) f
    CROSS JOIN LATERAL faker.pick_name(p_locale, 'last', 'X', faker.random_uniform(p_key, 2)) l
    CROSS JOIN LATERAL faker.pick_format(p_locale, 'name', faker.random_uniform(p_key, 3)) fmt
    CROSS JOIN LATERAL (SELECT
        CASE WHEN fmt.pattern ~ '\{(middle|mi)\}' THEN
            (SELECT p.value FROM faker.pick_name(p_locale, 'first', g.gender, faker.random_uniform(p_key, 4)) p) END AS middle,
        CASE WHEN strpos(fmt.pattern, '{last2}') > 0 THEN
            (SELECT p.value FROM faker.pick_name(p_locale, 'last', 'X', faker.random_uniform(p_key, 5)) p) END AS last2,
        CASE WHEN strpos(fmt.pattern, '{title}') > 0 THEN
            (SELECT w.value FROM faker.pick_word(p_locale, 'title', g.gender, faker.random_uniform(p_key, 6)) w) END AS title,
        CASE WHEN strpos(fmt.pattern, '{salutation}') > 0 THEN
            (SELECT w.value FROM faker.pick_word(p_locale, 'salutation', g.gender, faker.random_uniform(p_key, 7)) w) END AS salutation,
        CASE WHEN strpos(fmt.pattern, '{suffix}') > 0 THEN
            (SELECT w.value FROM faker.pick_word(p_locale, 'name_suffix', g.gender, faker.random_uniform(p_key, 8)) w) END AS suffix,
        CASE WHEN strpos(fmt.pattern, '{particle}') > 0 THEN
            (SELECT w.value FROM faker.pick_word(p_locale, 'particle', 'X', faker.random_uniform(p_key, 9)) w) END AS particle
        OFFSET 0  -- keeps the subquery: each part is looked up once, not once per reference
    ) x
$$;

-- street_address(locale, key): house number + street, e.g. '4127 N Maple Ave'
-- or 'Goethestr. 12a'. Street address templates (formats.kind =
-- 'street_address') may use {number} {street} {suffix} {direction}.
-- Words with an `alt` spelling (St / Straße -> Str.) use it sometimes.
CREATE FUNCTION faker.street_address(p_locale text, p_key bigint)
RETURNS TABLE (street_address text, street text, house_number text)
LANGUAGE sql STABLE PARALLEL SAFE AS $$
    SELECT faker.fill_template(sf.pattern, jsonb_build_object(
               'number', hn.number,
               'street', st.street,
               'suffix', x.suffix,
               'direction', x.direction)),
           st.street, hn.number
    FROM faker.pick_format(p_locale, 'street_address', faker.random_uniform(p_key, 1)) sf
    CROSS JOIN LATERAL (
        SELECT faker.random_digits(p_key, 2, h.pattern) AS number
        FROM faker.pick_format(p_locale, 'house_number', faker.random_uniform(p_key, 3)) h
        OFFSET 0) hn
    CROSS JOIN LATERAL (
        SELECT CASE WHEN w.alt IS NOT NULL AND faker.random_bool(p_key, 5, 0.3) THEN w.alt ELSE w.value END AS street
        FROM faker.pick_word(p_locale, 'street', 'X', faker.random_uniform(p_key, 4)) w
        OFFSET 0) st
    CROSS JOIN LATERAL (SELECT
        CASE WHEN strpos(sf.pattern, '{suffix}') > 0 THEN
            (SELECT CASE WHEN w.alt IS NOT NULL AND faker.random_bool(p_key, 7, 0.5) THEN w.alt ELSE w.value END
             FROM faker.pick_word(p_locale, 'street_suffix', 'X', faker.random_uniform(p_key, 6)) w) END AS suffix,
        CASE WHEN strpos(sf.pattern, '{direction}') > 0 THEN
            (SELECT CASE WHEN w.alt IS NOT NULL AND faker.random_bool(p_key, 9, 0.85) THEN w.alt ELSE w.value END
             FROM faker.pick_word(p_locale, 'street_direction', 'X', faker.random_uniform(p_key, 8)) w) END AS direction
        OFFSET 0
    ) x
$$;

-- address(locale, key): a complete postal address. The city, region and
-- postal code always belong together (one faker.places row).
-- Address templates (formats.kind = 'address') may use
--   {street_address} {secondary} {postal_code} {city} {region} {region_code}
--   {zip4} (4 random digits) {box} (P.O. box number); '\n' starts a new line.
CREATE FUNCTION faker.address(p_locale text, p_key bigint)
RETURNS TABLE (street_address text, secondary text, postal_code text, city text,
               region text, region_code text, full_address text)
LANGUAGE sql STABLE PARALLEL SAFE AS $$
    SELECT s.street_address, x.secondary, pl.postal_code, pl.city, pl.region, pl.region_code,
           faker.fill_template(af.pattern, jsonb_build_object(
               'street_address', s.street_address,
               'secondary', x.secondary,
               'postal_code', pl.postal_code,
               'city', pl.city,
               'region', pl.region,
               'region_code', pl.region_code,
               'zip4', x.zip4,
               'box', x.box))
    FROM faker.pick_place(p_locale, faker.random_uniform(p_key, 1)) pl
    CROSS JOIN LATERAL faker.pick_format(p_locale, 'address', faker.random_uniform(p_key, 2)) af
    CROSS JOIN LATERAL faker.street_address(p_locale, faker.hash64(p_key, 3)) s
    CROSS JOIN LATERAL (SELECT
        CASE WHEN strpos(af.pattern, '{secondary}') > 0 THEN
            (SELECT faker.random_digits(p_key, 12, sf.pattern)
             FROM faker.pick_format(p_locale, 'secondary', faker.random_uniform(p_key, 4)) sf) END AS secondary,
        CASE WHEN strpos(af.pattern, '{zip4}') > 0 THEN faker.random_digits(p_key, 10, '####') END AS zip4,
        CASE WHEN strpos(af.pattern, '{box}') > 0 THEN faker.random_digits(p_key, 11, '%###') END AS box
        OFFSET 0
    ) x
$$;

-- phone_number(locale, key): a phone number from a weighted mask
-- (formats.kind = 'phone'), e.g. '(^##) ^##-####' -> '(417) 352-0938'.
CREATE FUNCTION faker.phone_number(p_locale text, p_key bigint)
RETURNS TABLE (phone text)
LANGUAGE sql STABLE PARALLEL SAFE AS $$
    SELECT faker.random_digits(p_key, 1, f.pattern)
    FROM faker.pick_format(p_locale, 'phone', faker.random_uniform(p_key, 0)) f
$$;

-- email_address(locale, key, first_name, last_name): an e-mail address built
-- from the person's name. Local-part templates (formats.kind = 'email') may
-- use {first} {last} {f} {l} (initials) and digit masks: '{f}{last}##'.
-- Names are transliterated to ASCII ('Jürgen' -> 'juergen').
CREATE FUNCTION faker.email_address(p_locale text, p_key bigint, p_first_name text, p_last_name text)
RETURNS TABLE (email text)
LANGUAGE sql STABLE PARALLEL SAFE AS $$
    SELECT faker.random_digits(p_key, 3, faker.fill_template(f.pattern, jsonb_build_object(
               'first', s.first, 'last', s.last, 'f', left(s.first, 1), 'l', left(s.last, 1))))
           || '@' || d.value
    FROM (SELECT faker.slug(p_first_name) AS first, faker.slug(p_last_name) AS last OFFSET 0) s
    CROSS JOIN LATERAL faker.pick_format(p_locale, 'email', faker.random_uniform(p_key, 1)) f
    CROSS JOIN LATERAL faker.pick_word(p_locale, 'email_domain', 'X', faker.random_uniform(p_key, 2)) d
$$;

-- geolocation(key): latitude/longitude uniformly distributed on the sphere.
CREATE FUNCTION faker.geolocation(p_key bigint)
RETURNS TABLE (latitude double precision, longitude double precision)
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT p.latitude, p.longitude FROM faker.random_point_on_sphere(p_key, 0) p
$$;

-- physical_attributes(locale, key, gender):
--   height ~ Normal(mean, sd) of the locale and gender (faker.body_stats)
--   BMI    ~ LogNormal(ln(median), sigma), weight = BMI * height²
--            (so weight is correlated with height, as in real people)
--   eye colour, hair colour, blood type: weighted picks with the locale's
--   population frequencies and words.
CREATE FUNCTION faker.physical_attributes(p_locale text, p_key bigint, p_gender char)
RETURNS TABLE (height_cm double precision, weight_kg double precision, bmi double precision,
               eye_color text, hair_color text, blood_type text)
LANGUAGE sql STABLE PARALLEL SAFE AS $$
    SELECT r.height, r.bmi * (r.height / 100.0) ^ 2, r.bmi, e.value, h.value, b.value
    FROM faker.body_stats s
    CROSS JOIN LATERAL (SELECT faker.random_normal(p_key, 1, s.height_mean_cm, s.height_sd_cm) AS height,
                               faker.random_lognormal(p_key, 2, ln(s.bmi_median), s.bmi_sigma) AS bmi
                        OFFSET 0) r
    LEFT JOIN LATERAL faker.pick_word(p_locale, 'eye_color', 'X', faker.random_uniform(p_key, 3)) e ON true
    LEFT JOIN LATERAL faker.pick_word(p_locale, 'hair_color', 'X', faker.random_uniform(p_key, 4)) h ON true
    LEFT JOIN LATERAL faker.pick_word(p_locale, 'blood_type', 'X', faker.random_uniform(p_key, 5)) b ON true
    WHERE s.locale = p_locale AND s.gender = p_gender
$$;

-- markov_text(locale, key, min_words, max_words): random text in the locale's
-- language from an order-2 Markov chain trained on public-domain novels.
--   1. pick a sentence start (w1, w2), weighted by how often it starts a sentence
--   2. repeat: pick the next word w3 with probability count(w1 w2 w3) / count(w1 w2),
--      move to state (w2, w3)
--   3. stop at the first sentence end after min_words, at max_words or at a
--      pair that never continues in the corpus
--      (then cut back to the last sentence end, or close the sentence with '.')
CREATE FUNCTION faker.markov_text(p_locale text, p_key bigint,
                                  p_min_words int DEFAULT 12, p_max_words int DEFAULT 40)
RETURNS text
LANGUAGE plpgsql STABLE PARALLEL SAFE AS $$
DECLARE
    v_state    int;
    v_word     text;
    v_words    text[];
    v_last_end int := 0;  -- number of words up to the last sentence end
    v_step     int := 0;
BEGIN
    SELECT s.state_id, ARRAY[s.w1, s.w2]
      INTO v_state, v_words
    FROM faker.markov_states s
    WHERE s.locale = p_locale AND s.start_weight > 0
      AND s.start_cdf > faker.random_uniform(p_key, 0)
    ORDER BY s.start_cdf
    LIMIT 1;
    IF NOT FOUND THEN
        RETURN NULL;
    END IF;
    IF v_words[2] ~ '[.!?]$' THEN
        v_last_end := 2;
    END IF;

    WHILE cardinality(v_words) < p_max_words AND v_last_end < p_min_words LOOP
        v_step := v_step + 1;
        SELECT t.next_word, t.next_state_id
          INTO v_word, v_state
        FROM faker.markov_transitions t
        WHERE t.state_id = v_state
          AND t.cdf > faker.random_uniform(p_key, v_step)
        ORDER BY t.cdf
        LIMIT 1;
        EXIT WHEN NOT FOUND;
        v_words := v_words || v_word;
        IF v_word ~ '[.!?]$' THEN
            v_last_end := cardinality(v_words);
        END IF;
    END LOOP;

    IF v_last_end < cardinality(v_words) THEN
        IF v_last_end >= p_min_words / 2 THEN
            v_words := v_words[1:v_last_end];
        ELSE
            v_words[cardinality(v_words)] := rtrim(v_words[cardinality(v_words)], ',;:') || '.';
        END IF;
    END IF;
    RETURN array_to_string(v_words, ' ');
END;
$$;
