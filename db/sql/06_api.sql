-- =============================================================================
-- Faker SQL: public API
-- =============================================================================

-- list_locales(): locales available for generation, in display order.
CREATE FUNCTION faker.list_locales()
RETURNS TABLE (code text, title text, language text, country text)
LANGUAGE sql STABLE PARALLEL SAFE AS $$
    SELECT l.code, l.title, l.language, l.country
    FROM faker.locales l
    ORDER BY l.sort_order, l.code
$$;

-- fake_user: one generated user, the row type of generate_users().
CREATE TYPE faker.fake_user AS (
    pos             bigint,     -- 0-based user number in the (locale, seed) sequence
    batch           int,
    batch_index     int,        -- 0-based index inside the batch
    full_name       text,
    gender          text,       -- M or F
    first_name      text,
    last_name       text,
    address         text,       -- may contain line breaks
    latitude       double precision,
    longitude       double precision,
    height_cm       numeric,
    weight_kg       numeric,
    height          text,       -- formatted for the locale (5'11" / 1,82 m)
    weight          text,       -- formatted for the locale (176 lb / 79,8 kg)
    eye_color       text,
    hair_color      text,
    blood_type      text,
    phone           text,
    email           text,
    about           text        -- Markov chain text, NULL when with_text = false
);

-- generate_users(locale, seed, batch, batch_size, with_text): one batch of
-- fake users. User number `pos` (0-based) = batch * batch_size + index, and
-- every value is a pure function of (locale, seed, pos): the same arguments
-- always return the same users, and user #25 is the same whether it is read
-- in batches of 10 or of 50.
CREATE FUNCTION faker.generate_users(
    p_locale     text,
    p_seed       bigint,
    p_batch      int     DEFAULT 0,
    p_batch_size int     DEFAULT 10,
    p_with_text  boolean DEFAULT true)
RETURNS SETOF faker.fake_user
LANGUAGE plpgsql STABLE PARALLEL SAFE
-- the query is the same for every call: plan it once per session, not per batch
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM faker.locales l WHERE l.code = p_locale) THEN
        RAISE EXCEPTION 'faker: unknown locale "%"', p_locale
            USING HINT = 'See SELECT * FROM faker.list_locales()';
    END IF;
    IF p_seed IS NULL OR p_batch IS NULL OR p_batch < 0 OR p_batch_size IS NULL OR p_batch_size < 1 THEN
        RAISE EXCEPTION 'faker: seed must be set, batch must be >= 0 and batch_size >= 1';
    END IF;

    RETURN QUERY
    SELECT u.pos, p_batch, u.i,
           n.full_name, n.gender::text, n.first_name, n.last_name,
           a.full_address,
           g.latitude, g.longitude,
           round(b.height_cm::numeric, 1), round(b.weight_kg::numeric, 1),
           faker.format_height(b.height_cm, l.units, l.decimal_mark),
           faker.format_weight(b.weight_kg, l.units, l.decimal_mark),
           b.eye_color, b.hair_color, b.blood_type,
           ph.phone, e.email,
           CASE WHEN p_with_text THEN faker.markov_text(p_locale, faker.hash64(u.k, 7)) END
    FROM (SELECT s.i, s.pos, faker.user_key(p_locale, p_seed, s.pos) AS k
          FROM (SELECT gs.i, p_batch::bigint * p_batch_size + gs.i AS pos
                FROM generate_series(0, p_batch_size - 1) AS gs(i)) s
          OFFSET 0) u
    CROSS JOIN faker.locales l
    CROSS JOIN LATERAL faker.person_name(p_locale, faker.hash64(u.k, 1)) n
    CROSS JOIN LATERAL faker.address(p_locale, faker.hash64(u.k, 2)) a
    CROSS JOIN LATERAL faker.geolocation(faker.hash64(u.k, 3)) g
    CROSS JOIN LATERAL faker.physical_attributes(p_locale, faker.hash64(u.k, 4), n.gender) b
    CROSS JOIN LATERAL faker.phone_number(p_locale, faker.hash64(u.k, 5)) ph
    CROSS JOIN LATERAL faker.email_address(p_locale, faker.hash64(u.k, 6), n.first_name, n.last_name) e
    WHERE l.code = p_locale
    ORDER BY u.i;
END;
$$;

-- generate_user(locale, seed, pos, with_text): the single user at position
-- `pos` (the same row generate_users returns for that position).
CREATE FUNCTION faker.generate_user(p_locale text, p_seed bigint, p_pos int, p_with_text boolean DEFAULT true)
RETURNS SETOF faker.fake_user
LANGUAGE sql STABLE PARALLEL SAFE AS $$
    SELECT * FROM faker.generate_users(p_locale, p_seed, p_pos, 1, p_with_text)
$$;

-- benchmark(locale, users, with_text, seed): generate `users` users inside
-- the database and measure the throughput of one session. A warm-up run
-- first loads the lookup tables into the buffer cache. Every column of every
-- row is turned into text, so the planner cannot skip any work.
CREATE FUNCTION faker.benchmark(
    p_locale    text    DEFAULT 'en_US',
    p_users     int     DEFAULT 100000,
    p_with_text boolean DEFAULT false,
    p_seed      bigint  DEFAULT 42)
RETURNS TABLE (locale text, users int, with_text boolean, seconds numeric, users_per_second numeric)
LANGUAGE plpgsql VOLATILE AS $$
DECLARE
    v_start   timestamptz;
    v_seconds double precision;
    v_chars   bigint;
BEGIN
    SELECT sum(length(u::text)) INTO v_chars
    FROM faker.generate_users(p_locale, p_seed + 1, 0, least(p_users, 2000), p_with_text) u;

    v_start := clock_timestamp();
    SELECT sum(length(u::text)) INTO v_chars
    FROM faker.generate_users(p_locale, p_seed, 0, p_users, p_with_text) u;
    v_seconds := extract(epoch FROM clock_timestamp() - v_start);

    locale := p_locale;
    users := p_users;
    with_text := p_with_text;
    seconds := round(v_seconds::numeric, 3);
    users_per_second := round((p_users / greatest(v_seconds, 1e-6))::numeric);
    RETURN NEXT;
END;
$$;

-- lookup_sizes: how many rows each locale has in every lookup list.
CREATE VIEW faker.lookup_sizes AS
    SELECT locale, 'names' AS "table", kind || CASE WHEN gender <> 'X' THEN ' (' || gender || ')' ELSE '' END AS list,
           count(*) AS entries
    FROM faker.names GROUP BY locale, kind, gender
    UNION ALL
    SELECT locale, 'places', 'postal code + city + region', count(*) FROM faker.places GROUP BY locale
    UNION ALL
    SELECT locale, 'words', kind || CASE WHEN gender <> 'X' THEN ' (' || gender || ')' ELSE '' END, count(*)
    FROM faker.words GROUP BY locale, kind, gender
    UNION ALL
    SELECT locale, 'formats', kind, count(*) FROM faker.formats GROUP BY locale, kind
    UNION ALL
    SELECT locale, 'markov_states', 'word pairs', count(*) FROM faker.markov_states GROUP BY locale
    UNION ALL
    SELECT s.locale, 'markov_transitions', 'word pair -> next word', count(*)
    FROM faker.markov_transitions t JOIN faker.markov_states s USING (state_id) GROUP BY s.locale;
