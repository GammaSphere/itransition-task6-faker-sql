-- =============================================================================
-- Faker SQL: random number generation
-- =============================================================================
-- The generator is counter based (like Random123 / "stateless" PRNGs): a random
-- number is a hash of a 64-bit key and a stream number, so any value can be
-- computed directly, in any order, without a stored generator state.
--
--   seed + locale ──hash──> locale key ──hash(position)──> user key
--   user key ──hash(1)──> name key, ──hash(2)──> address key, ...
--   field key + stream ──hash──> 53 random bits ──> uniform double in [0, 1)
--
-- The mixing function is PostgreSQL's built-in 64-bit hash
-- hashint8extended(value, seed) (Bob Jenkins' lookup3 final mix, the function
-- behind hash partitioning, so it is stable across versions and platforms).
-- All functions are IMMUTABLE: the same arguments always give the same result.
-- =============================================================================

-- hash64(key, salt): derive a new independent 64-bit key from a key and a
-- small integer (stream id, counter, field number).
CREATE FUNCTION faker.hash64(p_key bigint, p_salt bigint)
RETURNS bigint
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT hashint8extended(p_salt, p_key)
$$;

-- locale_key(locale, seed): the root key of one (locale, seed) pair.
CREATE FUNCTION faker.locale_key(p_locale text, p_seed bigint)
RETURNS bigint
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT hashtextextended(p_locale, p_seed)
$$;

-- user_key(locale, seed, position): the key of the user at a 0-based position.
-- position = batch_index * batch_size + index_in_batch, so a user does not
-- depend on how the sequence is split into batches.
CREATE FUNCTION faker.user_key(p_locale text, p_seed bigint, p_position bigint)
RETURNS bigint
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT hashint8extended(p_position, hashtextextended(p_locale, p_seed))
$$;

-- random_uniform(key, stream): uniform double in [0, 1).
-- The top 53 bits of the hash fill the mantissa of a double exactly.
CREATE FUNCTION faker.random_uniform(p_key bigint, p_stream int)
RETURNS double precision
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT ((hashint8extended(p_stream, p_key) >> 11) & 9007199254740991)::double precision
           / 9007199254740992.0
$$;

-- random_int(key, stream, min, max): uniform integer in [min, max].
CREATE FUNCTION faker.random_int(p_key bigint, p_stream int, p_min int, p_max int)
RETURNS int
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT p_min + floor(faker.random_uniform(p_key, p_stream) * (p_max::bigint - p_min + 1))::int
$$;

-- random_bool(key, stream, probability): true with the given probability.
CREATE FUNCTION faker.random_bool(p_key bigint, p_stream int, p_probability double precision DEFAULT 0.5)
RETURNS boolean
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT faker.random_uniform(p_key, p_stream) < p_probability
$$;

-- random_normal(key, stream, mean, sd): normally distributed double.
-- Box–Muller transform of two independent uniforms u1, u2:
--     z = sqrt(-2 ln u1) * cos(2 pi u2)  ~  Normal(0, 1)
-- u1 is taken from (0, 1] (1 - uniform) so ln(u1) is always finite.
CREATE FUNCTION faker.random_normal(p_key bigint, p_stream int,
                                    p_mean double precision DEFAULT 0,
                                    p_sd double precision DEFAULT 1)
RETURNS double precision
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT p_mean + p_sd
           * sqrt(-2.0 * ln(1.0 - faker.random_uniform(hashint8extended(p_stream, p_key), 0)))
           * cos(2.0 * pi() * faker.random_uniform(hashint8extended(p_stream, p_key), 1))
$$;

-- random_lognormal(key, stream, mu, sigma): exp(Normal(mu, sigma)).
-- The median of the result is exp(mu); it is right-skewed and always > 0.
CREATE FUNCTION faker.random_lognormal(p_key bigint, p_stream int,
                                       p_mu double precision, p_sigma double precision)
RETURNS double precision
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT exp(faker.random_normal(p_key, p_stream, p_mu, p_sigma))
$$;

-- random_digits(key, stream, mask): replace mask characters with random ones.
--   #  digit 0-9        %  digit 1-9        ^  digit 2-9
--   ?  letter A-Z       !  letter a-h       anything else is kept as is
-- Example: random_digits(k, 1, '(^##) ^##-####') -> '(417) 352-0938'
-- Character i of the mask uses stream i of the derived key hash64(key, stream).
CREATE FUNCTION faker.random_digits(p_key bigint, p_stream int, p_mask text)
RETURNS text
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $$
DECLARE
    v_key    bigint := hashint8extended(p_stream, p_key);
    v_result text := '';
    v_char   text;
    v_i      int := 0;
BEGIN
    FOREACH v_char IN ARRAY string_to_array(p_mask, NULL) LOOP
        v_i := v_i + 1;
        v_result := v_result || CASE v_char
            WHEN '#' THEN faker.random_int(v_key, v_i, 0, 9)::text
            WHEN '%' THEN faker.random_int(v_key, v_i, 1, 9)::text
            WHEN '^' THEN faker.random_int(v_key, v_i, 2, 9)::text
            WHEN '?' THEN chr(65 + faker.random_int(v_key, v_i, 0, 25))
            WHEN '!' THEN chr(97 + faker.random_int(v_key, v_i, 0, 7))
            ELSE v_char
        END;
    END LOOP;
    RETURN v_result;
END;
$$;

-- random_point_on_sphere(key, stream): a point uniformly distributed on the
-- surface of a sphere, as (latitude, longitude) in degrees.
-- Area element: dA = cos(lat) dlat dlon, so the latitude must have the PDF
-- f(lat) = cos(lat) / 2 on [-90°, 90°]. Its CDF is F(lat) = (1 + sin(lat)) / 2,
-- and inverse transform sampling gives lat = asin(2u - 1). Longitude is
-- uniform on [-180°, 180°). (Uniform lat would crowd points at the poles.)
CREATE FUNCTION faker.random_point_on_sphere(p_key bigint, p_stream int DEFAULT 0)
RETURNS TABLE (latitude double precision, longitude double precision)
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT degrees(asin(2.0 * faker.random_uniform(hashint8extended(p_stream, p_key), 0) - 1.0)),
           360.0 * faker.random_uniform(hashint8extended(p_stream, p_key), 1) - 180.0
$$;
