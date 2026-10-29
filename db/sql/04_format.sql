-- =============================================================================
-- Faker SQL: string formatting helpers
-- =============================================================================

-- fill_template(template, values): replace {name} placeholders with values
-- from a jsonb object. Missing or null values become ''. Runs of spaces are
-- collapsed and every line is trimmed, so optional parts leave no gaps.
-- Example: fill_template('{title} {first} {last}', '{"first":"Ann","last":"Lee"}')
--          -> 'Ann Lee'
CREATE FUNCTION faker.fill_template(p_template text, p_values jsonb)
RETURNS text
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $$
DECLARE
    v_result text := p_template;
    v_name   text;
    v_value  text;
BEGIN
    FOR v_name, v_value IN SELECT key, value FROM jsonb_each_text(p_values) LOOP
        v_result := replace(v_result, '{' || v_name || '}', coalesce(v_value, ''));
    END LOOP;
    v_result := regexp_replace(v_result, '\{\w+\}', '', 'g');        -- unknown placeholders
    v_result := regexp_replace(v_result, '[ \t]+', ' ', 'g');        -- collapse spaces
    v_result := regexp_replace(v_result, ' *\n *', E'\n', 'g');      -- trim lines
    RETURN btrim(regexp_replace(v_result, ' +([,.])', '\1', 'g'));   -- no space before , or .
END;
$$;

-- to_ascii(text): transliterate letters with diacritics for e-mail addresses
-- (ä -> ae, ß -> ss, é -> e, ...).
CREATE FUNCTION faker.to_ascii(p_text text)
RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT translate(
               replace(replace(replace(replace(replace(replace(replace(replace(p_text,
                   'ä', 'ae'), 'ö', 'oe'), 'ü', 'ue'), 'Ä', 'Ae'), 'Ö', 'Oe'), 'Ü', 'Ue'),
                   'ß', 'ss'), 'æ', 'ae'),
               'áàâãåāçćčéèêëēėęíìîïīłñńóòôõøōśšúùûūýÿźżžÁÀÂÃÅĀÇĆČÉÈÊËĒĖĘÍÌÎÏĪŁÑŃÓÒÔÕØŌŚŠÚÙÛŪÝŸŹŻŽ',
               'aaaaaaccceeeeeeeiiiiilnnoooooossuuuuyyzzzAAAAAACCCEEEEEEEIIIIILNNOOOOOOSSUUUUYYZZZ')
$$;

-- slug(text): lower-case ASCII letters and digits only ("O'Brien" -> "obrien").
CREATE FUNCTION faker.slug(p_text text)
RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT regexp_replace(lower(faker.to_ascii(p_text)), '[^a-z0-9]', '', 'g')
$$;

-- format_decimal(value, digits, decimal_mark): fixed-point number with the
-- locale's decimal mark ('.' or ',').
CREATE FUNCTION faker.format_decimal(p_value double precision, p_digits int, p_decimal_mark text DEFAULT '.')
RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT replace(round(p_value::numeric, p_digits)::text, '.', p_decimal_mark)
$$;

-- format_height(cm, units, decimal_mark): '5'11"' (imperial) or '1,82 m' (metric).
-- Inches are rounded first, so 71.6 in gives 6'0" and never 5'12".
CREATE FUNCTION faker.format_height(p_cm double precision, p_units text, p_decimal_mark text DEFAULT '.')
RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT CASE p_units
               WHEN 'imperial' THEN
                   (round(p_cm / 2.54)::int / 12)::text || '''' || (round(p_cm / 2.54)::int % 12)::text || '"'
               ELSE faker.format_decimal(p_cm / 100.0, 2, p_decimal_mark) || ' m'
           END
$$;

-- format_height(locale, cm): the same with the units of a locale.
CREATE FUNCTION faker.format_height(p_locale text, p_cm double precision)
RETURNS text
LANGUAGE sql STABLE PARALLEL SAFE AS $$
    SELECT faker.format_height(p_cm, l.units, l.decimal_mark) FROM faker.locales l WHERE l.code = p_locale
$$;

-- format_weight(kg, units, decimal_mark): '176 lb' (imperial) or '79,8 kg' (metric).
CREATE FUNCTION faker.format_weight(p_kg double precision, p_units text, p_decimal_mark text DEFAULT '.')
RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT CASE p_units
               WHEN 'imperial' THEN round(p_kg / 0.45359237)::text || ' lb'
               ELSE faker.format_decimal(p_kg, 1, p_decimal_mark) || ' kg'
           END
$$;

-- format_weight(locale, kg): the same with the units of a locale.
CREATE FUNCTION faker.format_weight(p_locale text, p_kg double precision)
RETURNS text
LANGUAGE sql STABLE PARALLEL SAFE AS $$
    SELECT faker.format_weight(p_kg, l.units, l.decimal_mark) FROM faker.locales l WHERE l.code = p_locale
$$;

-- format_dms(degrees): absolute angle as degrees, minutes and seconds: 52°31′12″
CREATE FUNCTION faker.format_dms(p_degrees double precision)
RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT (s / 3600)::text || '°' || lpad(((s % 3600) / 60)::text, 2, '0') || '′'
           || lpad((s % 60)::text, 2, '0') || '″'
    FROM (SELECT round(abs(p_degrees) * 3600)::int AS s) t
$$;

-- format_coordinates(lat, lon, style): 'decimal' -> '52.520008, -13.404954'
--                                      'dms'     -> '52°31′12″N 13°24′18″W'
CREATE FUNCTION faker.format_coordinates(p_lat double precision, p_lon double precision,
                                         p_style text DEFAULT 'decimal')
RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT CASE p_style
        WHEN 'dms' THEN
            faker.format_dms(p_lat) || CASE WHEN p_lat < 0 THEN 'S' ELSE 'N' END || ' ' ||
            faker.format_dms(p_lon) || CASE WHEN p_lon < 0 THEN 'W' ELSE 'E' END
        ELSE round(p_lat::numeric, 6)::text || ', ' || round(p_lon::numeric, 6)::text
    END
$$;
