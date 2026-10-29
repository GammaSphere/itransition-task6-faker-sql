-- =============================================================================
-- Faker SQL: weighted random picks from lookup tables
-- =============================================================================
-- Inverse transform sampling on a discrete distribution:
--   the rows of a group are ordered and `cdf` is their cumulative probability
--   (running total of weight / total weight, see faker.refresh_weights()).
--   Row k owns the interval [cdf(k-1), cdf(k)) of [0, 1), whose length is
--   weight(k) / total. For u ~ Uniform[0, 1) the picked row is the first one
--   with cdf > u, so it is chosen with probability weight / total.
--   The search is one B-tree probe on the *_pick_idx index (group..., cdf),
--   so a pick costs O(log n) whatever the size of the table.
--
-- The pickers are set-returning SQL functions (one row, or none if the group
-- is empty) so PostgreSQL inlines them into the calling query as LATERAL
-- subqueries instead of calling a function per row.
-- =============================================================================

-- pick_name(locale, kind, gender, u): a given name ('first', gender M/F) or a
-- surname ('last', gender X).
CREATE FUNCTION faker.pick_name(p_locale text, p_kind text, p_gender char, p_u double precision)
RETURNS TABLE (value text)
LANGUAGE sql STABLE PARALLEL SAFE AS $$
    SELECT n.value
    FROM faker.names n
    WHERE n.locale = p_locale AND n.kind = p_kind AND n.gender = p_gender
      AND n.cdf > p_u
    ORDER BY n.cdf
    LIMIT 1
$$;

-- pick_word(locale, kind, gender, u): a vocabulary word and its alternative
-- spelling. Gender-neutral vocabularies use gender 'X'.
CREATE FUNCTION faker.pick_word(p_locale text, p_kind text, p_gender char, p_u double precision)
RETURNS TABLE (value text, alt text)
LANGUAGE sql STABLE PARALLEL SAFE AS $$
    SELECT w.value, w.alt
    FROM faker.words w
    WHERE w.locale = p_locale AND w.kind = p_kind AND w.gender = p_gender
      AND w.cdf > p_u
    ORDER BY w.cdf
    LIMIT 1
$$;

-- pick_format(locale, kind, u): a template / mask of the given kind.
CREATE FUNCTION faker.pick_format(p_locale text, p_kind text, p_u double precision)
RETURNS TABLE (pattern text)
LANGUAGE sql STABLE PARALLEL SAFE AS $$
    SELECT f.pattern
    FROM faker.formats f
    WHERE f.locale = p_locale AND f.kind = p_kind
      AND f.cdf > p_u
    ORDER BY f.cdf
    LIMIT 1
$$;

-- pick_place(locale, u): a consistent (postal code, city, region) triple.
CREATE FUNCTION faker.pick_place(p_locale text, p_u double precision)
RETURNS TABLE (postal_code text, city text, region text, region_code text)
LANGUAGE sql STABLE PARALLEL SAFE AS $$
    SELECT p.postal_code, p.city, p.region, p.region_code
    FROM faker.places p
    WHERE p.locale = p_locale
      AND p.cdf > p_u
    ORDER BY p.cdf
    LIMIT 1
$$;
