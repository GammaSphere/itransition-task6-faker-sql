# Faker SQL: stored procedure reference

Faker SQL is a fake-data generator written entirely as PostgreSQL stored procedures (schema `faker`). It generates people with a name, a postal address, a geolocation, physical attributes, a phone number, an e-mail address and a short bio in the language of the chosen locale (`en_US` and `de_DE` are included).

Every value is a pure function of **(locale, seed, position)**: the same arguments return the same people on any server, in any order, in batches of any size.

```sql
-- 10 American users, seed 42, first batch (batch index 0)
SELECT full_name, address, phone, email FROM faker.generate_users('en_US', 42);

-- the 4th batch of 10 German users, without the bio text
SELECT * FROM faker.generate_users('de_DE', 42, 3, 10, false);

-- one user at position 31 (0-based): the same row as in the batch above
SELECT * FROM faker.generate_user('de_DE', 42, 31);

-- the building blocks work on their own, with any 64-bit key
SELECT faker.random_normal(12345, 4, 170, 7);          -- 163.60...
SELECT * FROM faker.person_name('de_DE', 1234);       -- M | Hardy | | Stegmiller | Hardy Stegmiller
SELECT faker.random_digits(12345, 6, '(^##) ^##-####'); -- (829) 903-0682
```

## Installation

Requirements: PostgreSQL 14 or newer (tested on 17 locally and 18 on Neon, with identical output), no extensions.

```bash
pip install -r requirements.txt
DATABASE_URL=postgresql://user:password@host:5432/db  python db/setup.py
```

`db/setup.py` runs, in one transaction:

1. `db/sql/01_schema.sql` … `06_api.sql`: drops and recreates the schema `faker` with its tables and functions;
2. `db/seed/<locale>.sql`: the curated vocabularies and formats of each locale;
3. `COPY` of the large lookup tables from `db/data/*.csv.gz` (names, places, street names, Markov chain);
4. `CALL faker.refresh_weights()` and `ANALYZE`.

The CSV files are built from open data by `tools/build_data.py` (see [Data sources](#data-sources)).

## How it works

### Layers

The library is split into small functions, each with one job. Higher layers only call lower ones.

| Layer | File | Functions |
| --- | --- | --- |
| Random numbers | `02_random.sql` | `hash64`, `locale_key`, `user_key`, `random_uniform`, `random_int`, `random_bool`, `random_normal`, `random_lognormal`, `random_digits`, `random_point_on_sphere` |
| Weighted picks from lookup tables | `03_pick.sql` | `pick_name`, `pick_word`, `pick_format`, `pick_place` |
| String formatting | `04_format.sql` | `fill_template`, `to_ascii`, `slug`, `format_decimal`, `format_height`, `format_weight`, `format_dms`, `format_coordinates` |
| Field generators | `05_generators.sql` | `person_name`, `street_address`, `address`, `phone_number`, `email_address`, `geolocation`, `physical_attributes`, `markov_text` |
| Public API | `06_api.sql` | `generate_users`, `generate_user`, `list_locales`, `benchmark`, view `lookup_sizes` |
| Maintenance | `01_schema.sql` | procedure `refresh_weights` |

### Keys and streams: why the output is reproducible

There is no generator state. A random number is a hash of a 64-bit **key** and a small integer **stream** number, so any value can be computed directly (a *counter-based* generator, like Random123 or JAX's PRNG):

```text
locale_key = hashtextextended(locale, seed)                  -- 64-bit root of (locale, seed)
user_key   = hashint8extended(position, locale_key)          -- position = batch * batch_size + index
field key  = hash64(user_key, n)                             -- n = 1 name, 2 address, 3 geolocation,
                                                             --     4 physical, 5 phone, 6 e-mail, 7 text
uniform    = top 53 bits of hashint8extended(stream, field key) / 2^53     -- in [0, 1)
```

Inside a generator every random decision has its own stream number (gender = 0, first name = 1, surname = 2, …). Consequences:

- **Same arguments, same data.** Nothing depends on call order, on other rows or on the server.
- **Batches are views of one infinite sequence.** User #25 of a (locale, seed) is the same whether it is read in batches of 10 (batch 2, index 5) or 50 (batch 0, index 25). The app relies on this to page forward and back.
- **Fields are independent.** Changing the address formats does not change anybody's name, because the name generator has its own key.
- **Parallel by construction.** Different sessions can generate different ranges of positions without coordination.

The mixing function is PostgreSQL's built-in `hashint8extended(value, seed)`, Bob Jenkins' lookup3 mix with a 64-bit seed. It is the hash behind hash partitioning, so it is stable across versions and platforms, and it is implemented in C, which keeps random numbers cheap. `hashtextextended` hashes the locale code the same way.

### Data model and extensibility

All lookup tables are shared by every locale and have a `locale` column, so adding a locale means inserting rows; no table, index or function changes.

| Table | Contents | Group (one distribution per group) |
| --- | --- | --- |
| `locales` | code, title, language, country, units (`metric` / `imperial`), decimal mark | |
| `names` | given names (`kind = 'first'`, gender `M`/`F`) and surnames (`kind = 'last'`, gender `X`) | locale, kind, gender |
| `places` | postal code + city + region + region code, always consistent with each other | locale |
| `words` | small and medium vocabularies told apart by `kind`: `title`, `salutation`, `name_suffix`, `particle`, `street`, `street_suffix`, `street_direction`, `email_domain`, `eye_color`, `hair_color`, `blood_type`; `alt` holds an alternative spelling such as an abbreviation | locale, kind, gender |
| `formats` | templates and masks by `kind`: `name`, `street_address`, `address`, `secondary`, `house_number`, `phone`, `email` | locale, kind |
| `body_stats` | mean and standard deviation of height, median and log-sd of BMI | locale, gender |
| `markov_states`, `markov_transitions` | order-2 Markov chain of the locale's language | locale / state |

Every weighted table has a `weight` (relative frequency) and a `cdf` column that `refresh_weights()` fills with the cumulative probability of the row inside its group. The pick index on (group…, `cdf`) makes a weighted random pick a single B-tree probe; see [Weighted picks](#weighted-picks-inverse-transform-sampling).

Lookup sizes for the bundled locales (`SELECT * FROM faker.lookup_sizes` lists every list):

| Locale | Given names | Surnames | Places | Streets | Markov transitions |
| --- | ---: | ---: | ---: | ---: | ---: |
| en_US | 1 500 F + 1 500 M | 6 001 | 40 977 | 371 street words × 22 suffixes, 8 directions | 190 936 |
| de_DE | 1 003 F + 999 M | 30 429 | 15 050 | 3 224 street names | 209 893 |

With name templates, middle names, titles, double surnames and particles this gives tens of millions of distinct full names per locale, so 100 000 to 1 000 000 users do not visibly repeat.

## Algorithms

### Uniform numbers

`random_uniform(key, stream)` takes the top 53 bits of the 64-bit hash and divides by 2^53. A double has a 53-bit mantissa, so every value is exact, the result is in [0, 1) and 0 is possible while 1 is not. Integers in [min, max] are `min + floor(u * (max - min + 1))`.

### Normal distribution: Box–Muller transform

For two independent uniforms u1 ∈ (0, 1] and u2 ∈ [0, 1):

```text
z = sqrt(-2 ln u1) * cos(2π u2)   ~  Normal(0, 1)
x = mean + sd * z
```

Why it works: in polar coordinates, a pair of independent standard normals has a radius with R² ~ Exponential(1/2) and a uniform angle. `-2 ln u1` is exactly such an exponential variable (inverse CDF of the exponential) and `2π u2` is the uniform angle; projecting on the x axis gives one normal value. u1 is taken as `1 - uniform`, so it is never 0 and the logarithm is always finite. The function uses two sub-streams of its stream, so `random_normal(k, 4, …)` and `random_normal(k, 5, …)` are independent.

### Height and weight

- Height ~ `Normal(height_mean_cm, height_sd_cm)` of the locale and gender (`body_stats`; CDC NHANES for the US, Destatis for Germany).
- BMI ~ `LogNormal(ln(bmi_median), bmi_sigma)`: `exp` of a normal value. Real BMI is right-skewed and always positive, which a normal distribution is not.
- Weight = BMI × height². Weight therefore grows with height, as in real people, instead of being independent noise.
- Eye colour, hair colour and blood type are discrete weighted picks with the population frequencies of the locale.

### Uniform points on a sphere

Picking latitude and longitude as two uniform numbers is wrong: a 1° band at the equator has far more area than a 1° band at a pole, so points would crowd at the poles.

The area element of the unit sphere is dA = cos φ dφ dλ. Longitude λ can be uniform, but latitude φ must have the density

```text
f(φ) = cos φ / 2,   φ ∈ [-π/2, π/2]       (integrates to 1)
F(φ) = (1 + sin φ) / 2                     (its CDF)
```

Inverse transform sampling solves F(φ) = u for a uniform u:

```text
φ = asin(2u - 1)          latitude
λ = 360° · v - 180°       longitude, v uniform
```

Equivalently, sin φ is uniform on [-1, 1] (Archimedes' hat-box theorem). The test suite checks this with a chi-square test on sin φ, and the app's Distribution page plots the points on an equal-area map, where they look uniform.

### Weighted picks: inverse transform sampling

The rows of a group are sorted (by value, with the `"C"` collation so the order is the same on every server) and `cdf` is their running total of weight divided by the group total. Row k owns the interval [cdf(k-1), cdf(k)) of [0, 1), whose length is its probability weight(k) / total. For a uniform u the chosen row is the first one with `cdf > u`:

```sql
SELECT value FROM faker.names
WHERE locale = 'en_US' AND kind = 'last' AND gender = 'X' AND cdf > 0.5
ORDER BY cdf LIMIT 1;           -- one probe of names_pick_idx: 'Krieger'
```

Name weights are the square root of the real frequency (US Census and SSA counts): common names stay more frequent than rare ones, but the long tail still shows up.

### Templates and masks

Formats are weighted rows of `faker.formats`, so the variety of names, addresses and numbers is data, not code.

- `{placeholder}` parts are replaced by `fill_template` from a jsonb object; missing values become empty and spaces are tidied.
- Mask characters are replaced by `random_digits`: `#` digit 0-9, `%` digit 1-9, `^` digit 2-9, `?` letter A-Z, `!` letter a-h.

| Kind | Placeholders | en_US example | de_DE example |
| --- | --- | --- | --- |
| `name` | `{first} {middle} {mi} {last} {last2} {title} {salutation} {suffix} {particle}` | `{title} {first} {mi}. {last}` → Dr. Laura J. Simmons | `{salutation} {title} {first} {last}` → Frau Dr. Violetta Scheuermann |
| `street_address` | `{number} {street} {suffix} {direction}` | `{number} {direction} {street} {suffix}` → 4127 N Maple Ave | `{street} {number}` → Humboldtstraße 60d |
| `house_number` | mask | `%###` → 7393 | `%#!` → 95e |
| `secondary` | mask | `Apt. %?` → Apt. 4B | `%. OG` → 3. OG |
| `address` | `{street_address} {secondary} {postal_code} {city} {region} {region_code} {zip4} {box}`, `\n` for a new line | `{street_address}, {city}, {region_code} {postal_code}` | `{street_address}\n{postal_code} {city}` |
| `phone` | mask | `(^##) ^##-####` → (829) 903-0682 | `+49 (0)^## #######` |
| `email` | `{first} {last} {f} {l}` and masks | `{f}{last}` → jsmith | `{last}.{first}` → gross.juergen |

A generator looks up an optional part only when its template contains the placeholder, so a plain `{first} {last}` name costs three lookups, not ten.

### Random text: Markov chain

The bio is generated by an order-2 Markov chain over words, trained by `tools/build_data.py` on public-domain novels (Sherlock Holmes, Pride and Prejudice and Frankenstein for English; Effi Briest, Die Verwandlung, Werther and Buddenbrooks for German), about 230 000 words per language.

- A state is a pair of consecutive words (w1, w2). `markov_transitions` stores, for every state, each word w3 that followed it in the corpus with its count, plus the id of the next state (w2, w3), so the walk never searches by text.
- `markov_states.start_weight` counts how often the pair starts a sentence.
- Generation picks a start pair (weighted), then repeatedly picks the next word with probability count(w1 w2 w3) / count(w1 w2) (a weighted pick by `cdf`), until the first sentence end after `min_words`, `max_words`, or a pair that never continued in the corpus. A text cut at `max_words` is trimmed back to its last sentence end, or closed with a full stop.

Each step uses its own stream (`step` number), so the text is as reproducible as everything else.

## Public API

### `faker.generate_users`

```sql
faker.generate_users(
    p_locale     text,              -- 'en_US', 'de_DE', ... (see faker.list_locales())
    p_seed       bigint,            -- any 64-bit integer
    p_batch      int     DEFAULT 0, -- 0-based batch index
    p_batch_size int     DEFAULT 10,
    p_with_text  boolean DEFAULT true
) RETURNS SETOF faker.fake_user
```

Returns `p_batch_size` users at positions `p_batch * p_batch_size` … `+ p_batch_size - 1`. Raises an exception for an unknown locale, a negative batch, a batch size below 1 or a NULL seed.

| Column | Type | Description |
| --- | --- | --- |
| `pos` | bigint | 0-based position in the (locale, seed) sequence |
| `batch`, `batch_index` | int | the batch and the 0-based index inside it |
| `full_name` | text | formatted name, e.g. `Mr. Jason Doyle`, `Prof. Hans-Otto Leithner` |
| `gender`, `first_name`, `last_name` | text | name parts (gender `M` / `F`) |
| `address` | text | full postal address; may contain a line break |
| `latitude`, `longitude` | double precision | uniform on the sphere, degrees |
| `height_cm`, `weight_kg` | numeric | rounded to 0.1 |
| `height`, `weight` | text | in the locale's units: `5'11"`, `176 lb` / `1,82 m`, `79,8 kg` |
| `eye_color`, `hair_color`, `blood_type` | text | words of the locale |
| `phone`, `email` | text | |
| `about` | text | Markov chain bio, or NULL when `p_with_text` is false |

It is a PL/pgSQL function with one `RETURN QUERY` and `SET plan_cache_mode = force_generic_plan`, so the query is planned once per session instead of once per batch. The field generators are set-returning SQL functions that PostgreSQL inlines into that query as LATERAL subqueries: one generated user costs about 15 index probes and no per-row function-call overhead for the lookups.

### `faker.generate_user`

```sql
faker.generate_user(p_locale text, p_seed bigint, p_pos int, p_with_text boolean DEFAULT true)
RETURNS SETOF faker.fake_user
```

The single user at 0-based position `p_pos`; same values as `generate_users` for that position.

### `faker.list_locales`

```sql
faker.list_locales() RETURNS TABLE (code text, title text, language text, country text)
```

Locales in display order. The web app fills its locale list from it.

### `faker.benchmark`

```sql
faker.benchmark(p_locale text DEFAULT 'en_US', p_users int DEFAULT 100000,
                p_with_text boolean DEFAULT false, p_seed bigint DEFAULT 42)
RETURNS TABLE (locale text, users int, with_text boolean, seconds numeric, users_per_second numeric)
```

Generates `p_users` users in one session after a short warm-up and measures the time. Every column of every row is converted to text, so the planner cannot skip work. Results: [BENCHMARK.md](BENCHMARK.md).

### `faker.lookup_sizes` (view)

Row counts of every lookup list per locale: `SELECT * FROM faker.lookup_sizes`.

### `faker.refresh_weights` (procedure)

```sql
CALL faker.refresh_weights();
```

Recomputes the `cdf` columns of all lookup tables (and the Markov start and transition CDFs). Call it after inserting, deleting or reweighting lookup rows.

## Field generators

All generators take a locale and a 64-bit key, return one row, and can be used on their own. Use `faker.hash64(key, n)` to derive independent keys.

### `faker.person_name`

```sql
faker.person_name(p_locale text, p_key bigint)
RETURNS TABLE (gender char(1), first_name text, middle_name text, last_name text, full_name text)
```

Gender is 50/50. Picks a gendered given name and a surname, then a weighted `name` template, and fills only the parts the template uses: a second given name (`{middle}`, `{mi}` for the initial), a second surname for double names (`{last2}`), a gendered title or salutation, a suffix (`Jr.`, `PhD`), a nobility particle (`von`, `van der`). `middle_name` is NULL when the template has none.

```sql
SELECT full_name FROM faker.person_name('en_US', 99);   -- Maria Herrmann
```

### `faker.street_address` and `faker.address`

```sql
faker.street_address(p_locale text, p_key bigint)
RETURNS TABLE (street_address text, street text, house_number text)

faker.address(p_locale text, p_key bigint)
RETURNS TABLE (street_address text, secondary text, postal_code text, city text,
               region text, region_code text, full_address text)
```

`street_address` combines a house number mask, a street word, and for en_US a suffix (`Avenue` or `Ave`) and a direction (`North` or `N`). Words with an `alt` spelling use it some of the time (`Goethestraße` / `Goethestr.`). `address` adds a consistent (postal code, city, region) row from `faker.places` (real GeoNames data, so `Arlington, OR 97812` and `39638 Schwiesau` exist), an optional apartment or floor, and lays it out with a weighted `address` template: one line or two, state code or name, ZIP+4, P.O. box or Postfach.

```sql
SELECT full_address FROM faker.address('en_US', 5);     -- 82 Ferry Terrace, Arlington, OR 97812
SELECT street_address FROM faker.street_address('de_DE', 5);   -- Humboldtstraße 60d
```

### `faker.phone_number`

```sql
faker.phone_number(p_locale text, p_key bigint) RETURNS TABLE (phone text)
```

A weighted `phone` mask filled by `random_digits`. US numbers follow the North American Numbering Plan (area code and exchange start with 2-9), with or without `+1`, with dashes, dots, parentheses or an extension. German numbers use landline area codes or 015x/016x/017x mobile prefixes, national or `+49` / `0049` forms, spaces, slashes or dashes.

### `faker.email_address`

```sql
faker.email_address(p_locale text, p_key bigint, p_first_name text, p_last_name text)
RETURNS TABLE (email text)
```

Builds the local part from the person's own name with a weighted `email` template (`{first}.{last}`, `{f}{last}##`, …) after `slug()` transliteration, and adds a weighted domain of the locale (`gmail.com`, `gmx.de`, `web.de`, …).

```sql
SELECT email FROM faker.email_address('de_DE', 5, 'Jürgen', 'Groß');   -- gross.juergen@hotmail.de
```

### `faker.geolocation`

```sql
faker.geolocation(p_key bigint) RETURNS TABLE (latitude double precision, longitude double precision)
```

`random_point_on_sphere(key, 0)`: uniformly distributed on the sphere, see [Uniform points on a sphere](#uniform-points-on-a-sphere).

### `faker.physical_attributes`

```sql
faker.physical_attributes(p_locale text, p_key bigint, p_gender char)
RETURNS TABLE (height_cm double precision, weight_kg double precision, bmi double precision,
               eye_color text, hair_color text, blood_type text)
```

See [Height and weight](#height-and-weight).

```sql
SELECT * FROM faker.physical_attributes('en_US', 5, 'F');   -- 162.5 | 62.5 | 23.6 | Hazel | Brown | O+
```

### `faker.markov_text`

```sql
faker.markov_text(p_locale text, p_key bigint, p_min_words int DEFAULT 12, p_max_words int DEFAULT 40)
RETURNS text
```

Random text in the locale's language, see [Random text: Markov chain](#random-text-markov-chain).

```sql
SELECT faker.markov_text('de_DE', 3);
-- Ach, das ist ein herrlicher Anblick, der um acht Uhr in eigener Person einen gedeckten,
-- aber an gewissen Tagen den Herren Dalbeck Comp.
```

## Random primitives

| Function | Returns | Description |
| --- | --- | --- |
| `hash64(p_key bigint, p_salt bigint)` | bigint | new independent key from a key and a number |
| `locale_key(p_locale text, p_seed bigint)` | bigint | root key of a (locale, seed) |
| `user_key(p_locale text, p_seed bigint, p_position bigint)` | bigint | key of the user at a 0-based position |
| `random_uniform(p_key bigint, p_stream int)` | double precision | uniform in [0, 1) |
| `random_int(p_key bigint, p_stream int, p_min int, p_max int)` | int | uniform integer in [min, max] |
| `random_bool(p_key bigint, p_stream int, p_probability double precision DEFAULT 0.5)` | boolean | true with the given probability |
| `random_normal(p_key bigint, p_stream int, p_mean double precision DEFAULT 0, p_sd double precision DEFAULT 1)` | double precision | Box–Muller normal value |
| `random_lognormal(p_key bigint, p_stream int, p_mu double precision, p_sigma double precision)` | double precision | `exp(Normal(mu, sigma))`, median `exp(mu)` |
| `random_digits(p_key bigint, p_stream int, p_mask text)` | text | fills `# % ^ ? !` in a mask; other characters stay |
| `random_point_on_sphere(p_key bigint, p_stream int DEFAULT 0)` | table (latitude, longitude) | uniform point on the sphere, degrees |

```sql
SELECT faker.random_uniform(12345, 1);                 -- 0.4160604102492743
SELECT faker.random_int(12345, 2, 1, 6);               -- 3
SELECT faker.random_normal(12345, 4, 170, 7);          -- 163.60...
SELECT faker.random_digits(12345, 7, '%#!');           -- 95e
SELECT * FROM faker.random_point_on_sphere(12345);     -- -31.357825 | 33.487137
```

## Weighted picks

All pickers take a uniform number `p_u` in [0, 1) and return the row whose CDF interval contains it, or no row if the group is empty.

| Function | Returns |
| --- | --- |
| `pick_name(p_locale text, p_kind text, p_gender char, p_u double precision)` | table (value) |
| `pick_word(p_locale text, p_kind text, p_gender char, p_u double precision)` | table (value, alt) |
| `pick_format(p_locale text, p_kind text, p_u double precision)` | table (pattern) |
| `pick_place(p_locale text, p_u double precision)` | table (postal_code, city, region, region_code) |

```sql
SELECT * FROM faker.pick_name('en_US', 'last', 'X', 0.5);    -- Krieger
SELECT * FROM faker.pick_word('de_DE', 'street', 'X', 0.25); -- Flachsstraße | Flachsstr.
SELECT * FROM faker.pick_place('de_DE', 0.5);                -- 39638 | Schwiesau | Sachsen-Anhalt | ST
```

## Formatting helpers

| Function | Example |
| --- | --- |
| `fill_template(p_template text, p_values jsonb)` | `fill_template('{title} {first} {mi}. {last}', '{"first":"Laura","mi":"J","last":"Simmons"}')` → `Laura J. Simmons` |
| `to_ascii(p_text text)` | `Jürgen Groß-Éclair` → `Juergen Gross-Eclair` |
| `slug(p_text text)` | `O'Brien-Müller` → `obrienmueller` |
| `format_decimal(p_value double precision, p_digits int, p_decimal_mark text DEFAULT '.')` | `(3.14159, 2, ',')` → `3,14` |
| `format_height(p_locale text, p_cm double precision)` | en_US `182.4` → `6'0"`, de_DE → `1,82 m` |
| `format_height(p_cm double precision, p_units text, p_decimal_mark text DEFAULT '.')` | the same with explicit units |
| `format_weight(p_locale text, p_kg double precision)` | en_US `81.3` → `179 lb`, de_DE → `81,3 kg` |
| `format_weight(p_kg double precision, p_units text, p_decimal_mark text DEFAULT '.')` | the same with explicit units |
| `format_dms(p_degrees double precision)` | `48.137154` → `48°08′14″` |
| `format_coordinates(p_lat double precision, p_lon double precision, p_style text DEFAULT 'decimal')` | `'decimal'` → `48.137154, 11.576124`; `'dms'` → `48°08′14″N 11°34′34″E` |

## Adding a locale

Everything a locale needs is rows. For a new locale `xx_YY`:

1. `INSERT INTO faker.locales` (code, title, language, country, units, decimal mark).
2. `faker.names`: given names per gender (`first`, `M`/`F`) and surnames (`last`, `X`), with weights.
3. `faker.places`: postal code, city, region, region code (GeoNames has postal code dumps for most countries).
4. `faker.words`: at least `street`, `email_domain`, `eye_color`, `hair_color`, `blood_type`; titles and the other kinds only if the formats use them.
5. `faker.formats`: at least `name`, `street_address`, `house_number`, `address`, `phone`, `email`.
6. `faker.body_stats`: height and BMI parameters for `M` and `F`.
7. Optionally a Markov chain: add the corpus to `CORPORA` in `tools/build_data.py`.
8. `CALL faker.refresh_weights();`

A minimal example in SQL:

```sql
INSERT INTO faker.locales (code, title, language, country, units, decimal_mark, sort_order)
VALUES ('fr_FR', 'Français (France)', 'fr', 'FR', 'metric', ',', 3);

INSERT INTO faker.names (locale, kind, gender, value, weight) VALUES
    ('fr_FR', 'first', 'F', 'Camille', 10), ('fr_FR', 'first', 'M', 'Lucas', 10),
    ('fr_FR', 'last', 'X', 'Martin', 30), ('fr_FR', 'last', 'X', 'Bernard', 20);
INSERT INTO faker.formats (locale, kind, pattern, weight) VALUES
    ('fr_FR', 'name', '{first} {last}', 1),
    ('fr_FR', 'street_address', '{number} {street}', 1),
    ('fr_FR', 'house_number', '%#', 1),
    ('fr_FR', 'address', '{street_address}, {postal_code} {city}', 1),
    ('fr_FR', 'phone', '0% ## ## ## ##', 1),
    ('fr_FR', 'email', '{first}.{last}', 1);
-- ... words, places, body_stats ...
CALL faker.refresh_weights();
```

## Performance notes

- **One probe per pick.** The `cdf` column turns a weighted pick into `WHERE cdf > u ORDER BY cdf LIMIT 1` on a B-tree index, independent of table size.
- **Inlining.** Pickers and generators are `STABLE` set-returning SQL functions, which PostgreSQL inlines into the calling query, so no function-call overhead is paid per lookup. Sub-selects whose columns are used more than once carry `OFFSET 0`, which stops the planner from copying (and re-running) their expressions at every reference.
- **Plan once.** `generate_users` forces a generic plan: a 10-user batch takes about 3 ms instead of 5.5 ms, because the large inlined query is not re-planned on every call.
- **PL/pgSQL where it is faster.** `fill_template` and `random_digits` loop over a few items; as PL/pgSQL they are 2-3 times faster than the equivalent set-based SQL.
- **The bio is the expensive part.** The Markov chain needs about one index probe per word; `p_with_text => false` roughly doubles the speed.

Measured numbers are in [BENCHMARK.md](BENCHMARK.md).

## Data sources

| Data | Source | License |
| --- | --- | --- |
| US given names | SSA baby names 1945-2008, via hadley/data-baby-names | public domain |
| US surnames | US Census 2000 surnames, via fivethirtyeight/data | public domain |
| German given names, common surnames | Faker (de_DE, de_AT, de_CH, de_LU, de_LI providers) | MIT |
| German surname long tail | smashew/NameDatabases | MIT |
| Postal codes, cities, regions | GeoNames postal code dumps | CC BY 4.0 |
| Markov chain corpora | Project Gutenberg | public domain |
| World map (web app) | Natural Earth 1:110m land | public domain |
