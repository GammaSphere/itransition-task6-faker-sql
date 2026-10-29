-- =============================================================================
-- Locale de_DE: Deutsch (Deutschland)
-- Curated vocabularies and formats. Names, places, street names and the
-- Markov chain are loaded from db/data/*.csv.gz (see tools/build_data.py).
-- =============================================================================

INSERT INTO faker.locales (code, title, language, country, units, decimal_mark, sort_order)
VALUES ('de_DE', 'Deutsch (Deutschland)', 'de', 'DE', 'metric', ',', 2);

-- ---------------------------------------------------------------- name parts
INSERT INTO faker.words (locale, kind, gender, value, weight) VALUES
    ('de_DE', 'salutation', 'M', 'Herr', 1),
    ('de_DE', 'salutation', 'F', 'Frau', 1),
    ('de_DE', 'title', 'M', 'Dr.', 50),
    ('de_DE', 'title', 'M', 'Prof. Dr.', 8),
    ('de_DE', 'title', 'M', 'Prof.', 4),
    ('de_DE', 'title', 'M', 'Dr. med.', 10),
    ('de_DE', 'title', 'M', 'Dr. rer. nat.', 4),
    ('de_DE', 'title', 'M', 'Dr.-Ing.', 6),
    ('de_DE', 'title', 'M', 'Dipl.-Ing.', 12),
    ('de_DE', 'title', 'M', 'Dipl.-Kfm.', 4),
    ('de_DE', 'title', 'M', 'Mag.', 2),
    ('de_DE', 'title', 'F', 'Dr.', 50),
    ('de_DE', 'title', 'F', 'Prof. Dr.', 7),
    ('de_DE', 'title', 'F', 'Prof.', 3),
    ('de_DE', 'title', 'F', 'Dr. med.', 12),
    ('de_DE', 'title', 'F', 'Dr. rer. nat.', 4),
    ('de_DE', 'title', 'F', 'Dr.-Ing.', 3),
    ('de_DE', 'title', 'F', 'Dipl.-Ing.', 8),
    ('de_DE', 'title', 'F', 'Dipl.-Kffr.', 4),
    ('de_DE', 'title', 'F', 'Mag.', 2);

INSERT INTO faker.words (locale, kind, value, weight) VALUES
    ('de_DE', 'particle', 'von', 60),
    ('de_DE', 'particle', 'von der', 10),
    ('de_DE', 'particle', 'vom', 6),
    ('de_DE', 'particle', 'zu', 6),
    ('de_DE', 'particle', 'von und zu', 3),
    ('de_DE', 'particle', 'van', 8),
    ('de_DE', 'particle', 'van der', 4),
    ('de_DE', 'particle', 'de', 3);

INSERT INTO faker.formats (locale, kind, pattern, weight) VALUES
    ('de_DE', 'name', '{first} {last}', 42),
    ('de_DE', 'name', '{first} {middle} {last}', 10),
    ('de_DE', 'name', '{first}-{middle} {last}', 6),
    ('de_DE', 'name', '{salutation} {first} {last}', 8),
    ('de_DE', 'name', '{salutation} {title} {first} {last}', 5),
    ('de_DE', 'name', '{title} {first} {last}', 8),
    ('de_DE', 'name', '{first} {last}-{last2}', 6),
    ('de_DE', 'name', '{first} {particle} {last}', 3),
    ('de_DE', 'name', '{salutation} {title} {last}', 2),
    ('de_DE', 'name', '{last}, {first}', 4),
    ('de_DE', 'name', '{first} {mi}. {last}', 3);

-- ---------------------------------------------------------------- addresses
-- Street names (with 'str.' abbreviations as alt) come from db/data/words.csv.gz.
INSERT INTO faker.formats (locale, kind, pattern, weight) VALUES
    ('de_DE', 'house_number', '%', 28),
    ('de_DE', 'house_number', '%#', 46),
    ('de_DE', 'house_number', '%!', 8),
    ('de_DE', 'house_number', '%#!', 6),
    ('de_DE', 'house_number', '%##', 3),
    ('de_DE', 'house_number', '%-%', 2),
    ('de_DE', 'street_address', '{street} {number}', 1),
    ('de_DE', 'secondary', '%. OG', 30),
    ('de_DE', 'secondary', '%. Etage', 10),
    ('de_DE', 'secondary', 'Whg. %#', 18),
    ('de_DE', 'secondary', 'Wohnung %', 10),
    ('de_DE', 'secondary', 'Hinterhaus', 10),
    ('de_DE', 'secondary', 'Seitenflügel', 4),
    ('de_DE', 'secondary', 'Aufgang ?', 6),
    ('de_DE', 'secondary', 'Haus ?', 6),
    ('de_DE', 'secondary', 'EG', 6),
    ('de_DE', 'address', '{street_address}, {postal_code} {city}', 42),
    ('de_DE', 'address', E'{street_address}\n{postal_code} {city}', 28),
    ('de_DE', 'address', '{street_address}, {postal_code} {city}, {region}', 8),
    ('de_DE', 'address', '{street_address}, {secondary}, {postal_code} {city}', 8),
    ('de_DE', 'address', E'{street_address}, {secondary}\n{postal_code} {city}', 4),
    ('de_DE', 'address', '{street_address}, D-{postal_code} {city}', 3),
    ('de_DE', 'address', '{street_address}, {postal_code} {city}, Deutschland', 5),
    ('de_DE', 'address', 'Postfach {box}, {postal_code} {city}', 2);

-- ---------------------------------------------------------------- phone
-- Area codes 0 + 2-5 digits (never 0 after the trunk prefix), mobile 015x/016x/017x.
INSERT INTO faker.formats (locale, kind, pattern, weight) VALUES
    ('de_DE', 'phone', '0^# #######', 6),
    ('de_DE', 'phone', '0^## #######', 14),
    ('de_DE', 'phone', '0^### ######', 14),
    ('de_DE', 'phone', '0^###-#####', 6),
    ('de_DE', 'phone', '0^##/#######', 6),
    ('de_DE', 'phone', '0^### / ######', 4),
    ('de_DE', 'phone', '+49 ^## #######', 12),
    ('de_DE', 'phone', '+49 (0)^## #######', 7),
    ('de_DE', 'phone', '+49-^###-######', 4),
    ('de_DE', 'phone', '0049 ^## #######', 3),
    ('de_DE', 'phone', '015# ########', 9),
    ('de_DE', 'phone', '016# #######', 4),
    ('de_DE', 'phone', '017# #######', 9),
    ('de_DE', 'phone', '+49 15# ########', 6),
    ('de_DE', 'phone', '+49 17# #######', 6),
    ('de_DE', 'phone', '+49 (0)17# #######', 3);

-- ---------------------------------------------------------------- e-mail
INSERT INTO faker.formats (locale, kind, pattern, weight) VALUES
    ('de_DE', 'email', '{first}.{last}', 28),
    ('de_DE', 'email', '{first}{last}', 10),
    ('de_DE', 'email', '{f}.{last}', 10),
    ('de_DE', 'email', '{f}{last}', 8),
    ('de_DE', 'email', '{first}-{last}', 5),
    ('de_DE', 'email', '{first}_{last}', 4),
    ('de_DE', 'email', '{first}.{last}##', 8),
    ('de_DE', 'email', '{last}.{first}', 5),
    ('de_DE', 'email', '{first}##', 5),
    ('de_DE', 'email', '{last}##', 3),
    ('de_DE', 'email', '{first}.{l}', 3),
    ('de_DE', 'email', '{first}{last}19##', 3),
    ('de_DE', 'email', '{f}{l}##', 2);

INSERT INTO faker.words (locale, kind, value, weight) VALUES
    ('de_DE', 'email_domain', 'gmx.de', 20),
    ('de_DE', 'email_domain', 'web.de', 20),
    ('de_DE', 'email_domain', 'gmail.com', 16),
    ('de_DE', 'email_domain', 't-online.de', 12),
    ('de_DE', 'email_domain', 'gmx.net', 6),
    ('de_DE', 'email_domain', 'outlook.de', 5),
    ('de_DE', 'email_domain', 'yahoo.de', 4),
    ('de_DE', 'email_domain', 'freenet.de', 4),
    ('de_DE', 'email_domain', 'posteo.de', 3),
    ('de_DE', 'email_domain', 'hotmail.de', 3),
    ('de_DE', 'email_domain', 'icloud.com', 3),
    ('de_DE', 'email_domain', 'mail.de', 2),
    ('de_DE', 'email_domain', 'arcor.de', 2),
    ('de_DE', 'email_domain', 'online.de', 1),
    ('de_DE', 'email_domain', 'beispiel.de', 2);

-- ---------------------------------------------------------------- body
-- Destatis Mikrozensus adult means; BMI median and log-sd fitted to Germany.
INSERT INTO faker.body_stats (locale, gender, height_mean_cm, height_sd_cm, bmi_median, bmi_sigma) VALUES
    ('de_DE', 'M', 179.9, 7.2, 26.4, 0.16),
    ('de_DE', 'F', 166.0, 6.6, 24.6, 0.19);

INSERT INTO faker.words (locale, kind, value, weight) VALUES
    ('de_DE', 'eye_color', 'Blau', 34),
    ('de_DE', 'eye_color', 'Braun', 28),
    ('de_DE', 'eye_color', 'Grün', 13),
    ('de_DE', 'eye_color', 'Grau', 9),
    ('de_DE', 'eye_color', 'Graublau', 7),
    ('de_DE', 'eye_color', 'Haselnussbraun', 7),
    ('de_DE', 'eye_color', 'Bernstein', 2),
    ('de_DE', 'hair_color', 'Schwarz', 10),
    ('de_DE', 'hair_color', 'Dunkelbraun', 24),
    ('de_DE', 'hair_color', 'Braun', 18),
    ('de_DE', 'hair_color', 'Hellbraun', 12),
    ('de_DE', 'hair_color', 'Dunkelblond', 14),
    ('de_DE', 'hair_color', 'Blond', 10),
    ('de_DE', 'hair_color', 'Rot', 3),
    ('de_DE', 'hair_color', 'Grau', 7),
    ('de_DE', 'hair_color', 'Weiß', 2),
    ('de_DE', 'blood_type', 'A+', 37),
    ('de_DE', 'blood_type', '0+', 35),
    ('de_DE', 'blood_type', 'B+', 9),
    ('de_DE', 'blood_type', 'AB+', 4),
    ('de_DE', 'blood_type', 'A-', 6),
    ('de_DE', 'blood_type', '0-', 6),
    ('de_DE', 'blood_type', 'B-', 2),
    ('de_DE', 'blood_type', 'AB-', 1);
