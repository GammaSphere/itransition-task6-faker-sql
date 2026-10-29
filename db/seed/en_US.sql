-- =============================================================================
-- Locale en_US: English (United States)
-- Curated vocabularies and formats. Names, places, street words and the
-- Markov chain are loaded from db/data/*.csv.gz (see tools/build_data.py).
-- =============================================================================

INSERT INTO faker.locales (code, title, language, country, units, decimal_mark, sort_order)
VALUES ('en_US', 'English (United States)', 'en', 'US', 'imperial', '.', 1);

-- ---------------------------------------------------------------- name parts
INSERT INTO faker.words (locale, kind, gender, value, weight) VALUES
    ('en_US', 'title', 'M', 'Mr.', 70),
    ('en_US', 'title', 'M', 'Dr.', 18),
    ('en_US', 'title', 'M', 'Prof.', 4),
    ('en_US', 'title', 'M', 'Rev.', 3),
    ('en_US', 'title', 'M', 'Capt.', 2),
    ('en_US', 'title', 'M', 'Sgt.', 2),
    ('en_US', 'title', 'M', 'Hon.', 1),
    ('en_US', 'title', 'F', 'Ms.', 40),
    ('en_US', 'title', 'F', 'Mrs.', 33),
    ('en_US', 'title', 'F', 'Miss', 9),
    ('en_US', 'title', 'F', 'Dr.', 13),
    ('en_US', 'title', 'F', 'Prof.', 3),
    ('en_US', 'title', 'F', 'Rev.', 1),
    ('en_US', 'title', 'F', 'Hon.', 1),
    ('en_US', 'name_suffix', 'M', 'Jr.', 40),
    ('en_US', 'name_suffix', 'M', 'Sr.', 18),
    ('en_US', 'name_suffix', 'M', 'II', 10),
    ('en_US', 'name_suffix', 'M', 'III', 8),
    ('en_US', 'name_suffix', 'M', 'IV', 2),
    ('en_US', 'name_suffix', 'M', 'MD', 8),
    ('en_US', 'name_suffix', 'M', 'PhD', 8),
    ('en_US', 'name_suffix', 'M', 'DDS', 3),
    ('en_US', 'name_suffix', 'M', 'Esq.', 3),
    ('en_US', 'name_suffix', 'F', 'MD', 30),
    ('en_US', 'name_suffix', 'F', 'PhD', 30),
    ('en_US', 'name_suffix', 'F', 'RN', 20),
    ('en_US', 'name_suffix', 'F', 'DDS', 10),
    ('en_US', 'name_suffix', 'F', 'Esq.', 10);

INSERT INTO faker.formats (locale, kind, pattern, weight) VALUES
    ('en_US', 'name', '{first} {last}', 40),
    ('en_US', 'name', '{first} {mi}. {last}', 15),
    ('en_US', 'name', '{first} {middle} {last}', 8),
    ('en_US', 'name', '{title} {first} {last}', 10),
    ('en_US', 'name', '{title} {first} {mi}. {last}', 5),
    ('en_US', 'name', '{title} {last}', 2),
    ('en_US', 'name', '{first} {last} {suffix}', 5),
    ('en_US', 'name', '{first} {mi}. {last} {suffix}', 3),
    ('en_US', 'name', '{first} {last}-{last2}', 3),
    ('en_US', 'name', '{last}, {first}', 2),
    ('en_US', 'name', '{last}, {first} {mi}.', 2);

-- ---------------------------------------------------------------- addresses
-- Street base words come from db/data/words.csv.gz (kind 'street').
INSERT INTO faker.words (locale, kind, value, alt, weight) VALUES
    ('en_US', 'street_suffix', 'Street', 'St', 22),
    ('en_US', 'street_suffix', 'Avenue', 'Ave', 14),
    ('en_US', 'street_suffix', 'Road', 'Rd', 10),
    ('en_US', 'street_suffix', 'Drive', 'Dr', 10),
    ('en_US', 'street_suffix', 'Lane', 'Ln', 8),
    ('en_US', 'street_suffix', 'Way', NULL, 6),
    ('en_US', 'street_suffix', 'Court', 'Ct', 5),
    ('en_US', 'street_suffix', 'Boulevard', 'Blvd', 5),
    ('en_US', 'street_suffix', 'Place', 'Pl', 4),
    ('en_US', 'street_suffix', 'Circle', 'Cir', 3),
    ('en_US', 'street_suffix', 'Terrace', 'Ter', 2),
    ('en_US', 'street_suffix', 'Trail', 'Trl', 2),
    ('en_US', 'street_suffix', 'Parkway', 'Pkwy', 2),
    ('en_US', 'street_suffix', 'Highway', 'Hwy', 1),
    ('en_US', 'street_suffix', 'Square', 'Sq', 1),
    ('en_US', 'street_suffix', 'Loop', NULL, 1),
    ('en_US', 'street_suffix', 'Pike', NULL, 1),
    ('en_US', 'street_suffix', 'Run', NULL, 1),
    ('en_US', 'street_suffix', 'Path', NULL, 1),
    ('en_US', 'street_suffix', 'Crossing', 'Xing', 1),
    ('en_US', 'street_suffix', 'Hollow', 'Holw', 1),
    ('en_US', 'street_suffix', 'Ridge', 'Rdg', 1),
    ('en_US', 'street_direction', 'North', 'N', 10),
    ('en_US', 'street_direction', 'South', 'S', 10),
    ('en_US', 'street_direction', 'East', 'E', 10),
    ('en_US', 'street_direction', 'West', 'W', 10),
    ('en_US', 'street_direction', 'Northeast', 'NE', 3),
    ('en_US', 'street_direction', 'Northwest', 'NW', 3),
    ('en_US', 'street_direction', 'Southeast', 'SE', 3),
    ('en_US', 'street_direction', 'Southwest', 'SW', 3);

INSERT INTO faker.formats (locale, kind, pattern, weight) VALUES
    ('en_US', 'house_number', '%', 6),
    ('en_US', 'house_number', '%#', 14),
    ('en_US', 'house_number', '%##', 32),
    ('en_US', 'house_number', '%###', 36),
    ('en_US', 'house_number', '%####', 12),
    ('en_US', 'street_address', '{number} {street} {suffix}', 62),
    ('en_US', 'street_address', '{number} {direction} {street} {suffix}', 18),
    ('en_US', 'street_address', '{number} {street} {suffix} {direction}', 6),
    ('en_US', 'secondary', 'Apt. %#', 30),
    ('en_US', 'secondary', 'Apt. %?', 12),
    ('en_US', 'secondary', 'Apt %##', 8),
    ('en_US', 'secondary', 'Suite %##', 18),
    ('en_US', 'secondary', 'Unit %#', 12),
    ('en_US', 'secondary', 'Unit ?', 6),
    ('en_US', 'secondary', 'Fl %', 4),
    ('en_US', 'address', '{street_address}, {city}, {region_code} {postal_code}', 38),
    ('en_US', 'address', '{street_address}, {secondary}, {city}, {region_code} {postal_code}', 14),
    ('en_US', 'address', '{street_address} {secondary}, {city}, {region_code} {postal_code}-{zip4}', 6),
    ('en_US', 'address', E'{street_address}\n{city}, {region_code} {postal_code}', 14),
    ('en_US', 'address', E'{street_address}, {secondary}\n{city}, {region_code} {postal_code}', 6),
    ('en_US', 'address', '{street_address}, {city}, {region} {postal_code}', 10),
    ('en_US', 'address', '{street_address}, {city}, {region_code} {postal_code}, USA', 6),
    ('en_US', 'address', 'P.O. Box {box}, {city}, {region_code} {postal_code}', 4),
    ('en_US', 'address', 'PO Box {box}, {city}, {region_code} {postal_code}-{zip4}', 2);

-- ---------------------------------------------------------------- phone
-- North American Numbering Plan: area code and exchange start with 2-9 (^).
INSERT INTO faker.formats (locale, kind, pattern, weight) VALUES
    ('en_US', 'phone', '(^##) ^##-####', 30),
    ('en_US', 'phone', '^##-^##-####', 24),
    ('en_US', 'phone', '^##.^##.####', 9),
    ('en_US', 'phone', '+1 ^## ^## ####', 9),
    ('en_US', 'phone', '+1 (^##) ^##-####', 8),
    ('en_US', 'phone', '1-^##-^##-####', 7),
    ('en_US', 'phone', '(^##) ^##-#### x###', 4),
    ('en_US', 'phone', '^##-^##-#### ext. ####', 3),
    ('en_US', 'phone', '^##^######', 3),
    ('en_US', 'phone', '+1-^##-^##-####', 3);

-- ---------------------------------------------------------------- e-mail
INSERT INTO faker.formats (locale, kind, pattern, weight) VALUES
    ('en_US', 'email', '{first}.{last}', 24),
    ('en_US', 'email', '{first}{last}', 12),
    ('en_US', 'email', '{f}{last}', 14),
    ('en_US', 'email', '{first}_{last}', 6),
    ('en_US', 'email', '{first}.{last}##', 8),
    ('en_US', 'email', '{f}.{last}', 5),
    ('en_US', 'email', '{last}.{first}', 4),
    ('en_US', 'email', '{first}##', 6),
    ('en_US', 'email', '{first}{last}%###', 3),
    ('en_US', 'email', '{last}{f}', 4),
    ('en_US', 'email', '{first}.{l}', 3),
    ('en_US', 'email', '{f}{l}{last}##', 2),
    ('en_US', 'email', '{first}{last}##', 5);

INSERT INTO faker.words (locale, kind, value, weight) VALUES
    ('en_US', 'email_domain', 'gmail.com', 32),
    ('en_US', 'email_domain', 'yahoo.com', 12),
    ('en_US', 'email_domain', 'outlook.com', 9),
    ('en_US', 'email_domain', 'hotmail.com', 8),
    ('en_US', 'email_domain', 'icloud.com', 7),
    ('en_US', 'email_domain', 'aol.com', 4),
    ('en_US', 'email_domain', 'comcast.net', 3),
    ('en_US', 'email_domain', 'proton.me', 2),
    ('en_US', 'email_domain', 'msn.com', 2),
    ('en_US', 'email_domain', 'live.com', 2),
    ('en_US', 'email_domain', 'att.net', 2),
    ('en_US', 'email_domain', 'verizon.net', 2),
    ('en_US', 'email_domain', 'me.com', 1),
    ('en_US', 'email_domain', 'mail.com', 1),
    ('en_US', 'email_domain', 'example.com', 3),
    ('en_US', 'email_domain', 'example.org', 2);

-- ---------------------------------------------------------------- body
-- CDC NHANES adult means; BMI median and log-sd fitted to the US distribution.
INSERT INTO faker.body_stats (locale, gender, height_mean_cm, height_sd_cm, bmi_median, bmi_sigma) VALUES
    ('en_US', 'M', 175.4, 7.6, 28.0, 0.19),
    ('en_US', 'F', 161.7, 7.1, 27.6, 0.23);

INSERT INTO faker.words (locale, kind, value, weight) VALUES
    ('en_US', 'eye_color', 'Brown', 45),
    ('en_US', 'eye_color', 'Blue', 27),
    ('en_US', 'eye_color', 'Hazel', 13),
    ('en_US', 'eye_color', 'Green', 9),
    ('en_US', 'eye_color', 'Amber', 4),
    ('en_US', 'eye_color', 'Gray', 2),
    ('en_US', 'hair_color', 'Black', 18),
    ('en_US', 'hair_color', 'Dark brown', 28),
    ('en_US', 'hair_color', 'Brown', 18),
    ('en_US', 'hair_color', 'Light brown', 10),
    ('en_US', 'hair_color', 'Blond', 12),
    ('en_US', 'hair_color', 'Red', 3),
    ('en_US', 'hair_color', 'Auburn', 3),
    ('en_US', 'hair_color', 'Gray', 6),
    ('en_US', 'hair_color', 'White', 2),
    ('en_US', 'blood_type', 'O+', 374),
    ('en_US', 'blood_type', 'A+', 357),
    ('en_US', 'blood_type', 'B+', 85),
    ('en_US', 'blood_type', 'AB+', 34),
    ('en_US', 'blood_type', 'O-', 66),
    ('en_US', 'blood_type', 'A-', 63),
    ('en_US', 'blood_type', 'B-', 15),
    ('en_US', 'blood_type', 'AB-', 6);
