"""Build the large lookup tables of the SQL faker from open data sources.

Reads the raw downloads in data/raw/ and writes gzip CSV files to db/data/,
which db/setup.py loads with COPY. The small curated vocabularies (titles,
formats, eye colours, ...) live in db/seed/<locale>.sql instead.

Sources (all free to use; see README "Data sources"):
  * US given names   - SSA baby names 1880-2008 (hadley/data-baby-names)
  * US surnames      - US Census 2000 surnames (fivethirtyeight/data)
  * German names     - Faker de_* person providers + NameDatabases (smashew)
  * Places           - GeoNames postal code dumps US.zip / DE.zip (CC BY 4.0)
  * Markov corpora   - Project Gutenberg novels (public domain)

Run:  python tools/build_data.py
"""
from __future__ import annotations

import collections
import csv
import gzip
import importlib
import io
import math
import re
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "data" / "raw"
OUT = ROOT / "db" / "data"


def write_csv(name: str, header: list[str], rows) -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    count = 0
    # mtime=0 keeps the archives byte-identical between runs.
    with open(OUT / f"{name}.csv.gz", "wb") as raw:
        with gzip.GzipFile(fileobj=raw, mode="wb", mtime=0) as gz:
            with io.TextIOWrapper(gz, encoding="utf-8", newline="") as fh:
                w = csv.writer(fh)
                w.writerow(header)
                for row in rows:
                    w.writerow(row)
                    count += 1
    print(f"  {name}.csv.gz: {count} rows")
    return count


def compress(freq: float, scale: float = 1000.0) -> int:
    """Square-root compression of a frequency: common names stay more likely
    than rare ones, but the long tail is not drowned out."""
    return max(1, round(math.sqrt(freq) * scale))


# --------------------------------------------------------------------------
# Names
# --------------------------------------------------------------------------

IRISH_O = {
    "OBRIEN", "OCONNOR", "ONEILL", "ODONNELL", "OCONNELL", "ONEAL", "OHARA",
    "OROURKE", "OLEARY", "OKEEFE", "OSULLIVAN", "OMALLEY", "OSHEA", "OGRADY",
    "OTOOLE", "OKANE", "OREILLY", "OBRYANT", "ODONOGHUE", "OHAIR", "OMEARA",
    "OCALLAGHAN", "ODOHERTY", "OHALLORAN", "OKELLY", "OBANNON", "OGORMAN",
    "OHERN", "OKEEFFE", "ODANIEL", "OLOUGHLIN", "OSHAUGHNESSY", "OQUINN",
}


def census_case(upper: str) -> str:
    """SMITH -> Smith, MCDONALD -> McDonald, OBRIEN -> O'Brien."""
    if upper in IRISH_O:
        return "O'" + upper[1:].capitalize()
    name = upper.capitalize()
    if name.startswith("Mc") and len(name) > 3:
        name = "Mc" + name[2:].capitalize()
    return name


def us_names():
    rows = []
    # Given names: popularity summed over the birth years of today's adults.
    shares: dict[str, collections.Counter[str]] = {"M": collections.Counter(), "F": collections.Counter()}
    with open(RAW / "hadley_baby_names.csv", encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            year = int(r["year"])
            if 1945 <= year <= 2008:
                # percent is a fraction of births; keep it in parts per million
                shares["M" if r["sex"] == "boy" else "F"][r["name"]] += round(float(r["percent"]) * 1e6)
    for gender, counter in shares.items():
        for name, ppm in counter.most_common(1500):
            share = ppm / 1e6
            rows.append(("en_US", "first", gender, name, compress(share / 64, 3000)))
    # Surnames: top 6000 of the 2000 census, weighted by population count.
    with open(RAW / "fte_surnames.csv", encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            if int(r["rank"]) > 6000:
                break
            rows.append(("en_US", "last", "X", census_case(r["name"]), compress(int(r["count"]), 0.1)))
    return rows


def faker_list(locale: str, attr: str):
    provider = importlib.import_module(f"faker.providers.person.{locale}").Provider
    value = getattr(provider, attr, ()) or ()
    return list(value.keys() if isinstance(value, dict) else value)


def de_names():
    rows = []
    for gender, attr in (("M", "first_names_male"), ("F", "first_names_female")):
        seen = set()
        for name in faker_list("de_DE", attr):
            name = name.strip()
            if name and name not in seen:
                seen.add(name)
                rows.append(("de_DE", "first", gender, name, 4))
    # Common surnames (Faker de_DE/AT/CH/LU/LI) get a higher weight than the
    # long tail of 29k German surnames.
    common = []
    for loc in ("de_DE", "de_AT", "de_CH", "de_LU", "de_LI"):
        common += faker_list(loc, "last_names")
    weights = {}
    for name in common:
        weights[name.strip()] = 12
    with open(RAW / "smashew_de_surnames_utf8.txt", encoding="utf-8") as fh:
        for line in fh:
            name = line.strip()
            if name and name not in weights and re.fullmatch(r"[A-ZÄÖÜ][a-zäöüß]+(?:-[A-ZÄÖÜ][a-zäöüß]+)?", name):
                weights[name] = 1
    for name, weight in weights.items():
        if name:
            rows.append(("de_DE", "last", "X", name, weight))
    return rows


# --------------------------------------------------------------------------
# Places (postal code + city + region) from GeoNames
# --------------------------------------------------------------------------

US_STATES = {
    "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "DC", "FL", "GA", "HI", "ID", "IL", "IN",
    "IA", "KS", "KY", "LA", "ME", "MD", "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH",
    "NJ", "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC", "SD", "TN", "TX", "UT",
    "VT", "VA", "WA", "WV", "WI", "WY",
}

DE_STATES = {
    "Baden-Württemberg": "BW", "Bayern": "BY", "Berlin": "BE", "Brandenburg": "BB",
    "Bremen": "HB", "Hamburg": "HH", "Hessen": "HE", "Mecklenburg-Vorpommern": "MV",
    "Niedersachsen": "NI", "Nordrhein-Westfalen": "NW", "Rheinland-Pfalz": "RP",
    "Saarland": "SL", "Sachsen": "SN", "Sachsen-Anhalt": "ST", "Schleswig-Holstein": "SH",
    "Thüringen": "TH",
}

DE_COMPANY = re.compile(r"GmbH|mbH|\bAG\b|\bKG\b|e\.V\.|\bBank\b|Postfach|\d|Versand|Verlag|Vertrieb|Sparkasse|Gesellschaft|Service", re.I)


def places():
    rows = []
    seen = set()
    for code, locale in (("US", "en_US"), ("DE", "de_DE")):
        z = zipfile.ZipFile(RAW / f"geonames_{code}.zip")
        for line in z.read(f"{code}.txt").decode("utf-8").splitlines():
            f = line.split("\t")
            postal, city, region, region_code, accuracy = f[1], f[2].strip(), f[3].strip(), f[4], f[11]
            if code == "US":
                if region_code not in US_STATES:
                    continue
            else:
                if region not in DE_STATES or not accuracy or DE_COMPANY.search(city):
                    continue
                region_code = DE_STATES[region]
                # "Berlin Mitte" style district suffixes are fine, but strip
                # parenthesised qualifiers: "Frankfurt (Oder)" stays, "X (Y)" stays.
            key = (locale, postal, city)
            if key in seen:
                continue
            seen.add(key)
            rows.append((locale, postal, city, region, region_code, 1))
    return rows


# --------------------------------------------------------------------------
# Street names
# --------------------------------------------------------------------------

US_STREET_WORDS = """
Main Oak Pine Maple Cedar Elm Washington Lake Hill Park Walnut Spring Church Willow
Jefferson Lincoln Madison Jackson Adams Franklin Highland Sunset Ridge Meadow Valley
Forest River Mill School Railroad Center Market Union Chestnut Spruce Birch Hickory
Dogwood Magnolia Laurel Sycamore Poplar Aspen Juniper Cypress Holly Ivy Rose Lilac
Orchard Prospect Pleasant Grove Fairview Lakeview Riverside Hillside Woodland Greenwood
Broad High Front Water Bridge Mountain Canyon Creek Brook Pond Bay Harbor Ocean Beach
Shore Cliff Rock Stone Granite Summit Crest Vista Heritage Liberty Independence Freedom
Victory Pioneer Frontier Colonial Village Country Farm Ranch Prairie Meadowbrook
Cherry Peach Apple Plum Pecan Mulberry Hawthorn Redwood Sequoia Alder Beech Buckeye
Kennedy Roosevelt Wilson Monroe Grant Hamilton Clinton Harrison Taylor Polk Tyler
Pierce Hayes Garfield Cleveland McKinley Truman Eisenhower Reagan Carter Hoover
Jordan Austin Houston Dallas Denver Phoenix Boston Columbia Georgia Virginia Carolina
Dakota Montana Arizona Nevada Oregon Vermont Delaware Maryland Kentucky Tennessee
Ohio Indiana Illinois Michigan Wisconsin Minnesota Iowa Kansas Nebraska Texas Florida
College University Academy Hospital Airport Depot Station Commerce Industrial Factory
Cottage Garden Meadowlark Robin Cardinal Bluebird Eagle Hawk Falcon Sparrow Dove
Fox Deer Elk Bear Wolf Buffalo Beaver Otter Quail Pheasant Turkey Heron Swan
Autumn Winter Summer Morning Evening Sunrise Sunny Shady Quiet Hidden Golden Silver
Copper Iron Coal Gold Diamond Crystal Emerald Ruby Sapphire Pearl Coral Amber
North South East West Central Old New King Queen Prince Duke Lord Bishop Abbey
Canal Ferry Dock Port Wharf Lighthouse Anchor Sail Mariner Clipper Schooner
Cedarwood Oakwood Elmwood Pinewood Maplewood Briarwood Edgewood Kingswood Brentwood
Ashford Bradford Stratford Oxford Cambridge Windsor Kensington Chelsea Hampton
Fairway Green Links Clubhouse Country Club Polo Saddle Stirrup Bridle Horseshoe
""".split()

US_ORDINALS = [
    f"{n}{'th' if 10 <= n % 100 <= 20 else {1: 'st', 2: 'nd', 3: 'rd'}.get(n % 10, 'th')}"
    for n in range(1, 101)
]

DE_STREET_BASES = """
Haupt Schul Garten Bahnhof Dorf Kirch Berg Wald Wiesen Feld Mühlen Linden Birken
Eichen Buchen Ahorn Kastanien Tannen Fichten Erlen Eschen Ulmen Pappel Weiden Rosen
Tulpen Nelken Lilien Flieder Holunder Veilchen Narzissen Dahlien Astern Sonnen Mond
Stern Markt Rathaus Post Brunnen Quell Bach See Teich Weiher Burg Schloss Kloster
Turm Tor Mauer Graben Wall Hafen Fähr Brücken Mühl Hof Gut Anger Heide Moor Marsch
Au Tal Höhen Hügel Kamp Winkel Sand Stein Kies Lehm Ton Ziegel Kalk Salz Eisen
Kupfer Silber Gold Goethe Schiller Lessing Herder Heine Kant Hegel Luther Melanchthon
Bach Händel Mozart Beethoven Schubert Brahms Wagner Haydn Schumann Mendelssohn Dürer
Cranach Holbein Gutenberg Kepler Humboldt Liebig Röntgen Planck Einstein Koch Virchow
Siemens Bosch Benz Daimler Diesel Zeppelin Otto Lilienthal Bismarck Stein Hardenberg
Ebert Stresemann Adenauer Heuss Brandt Erhard Bebel Lassalle Uhland Mörike Hölderlin
Fontane Storm Raabe Keller Hebbel Kleist Grimm Hauff Eichendorff Novalis Busch
Gerhart-Hauptmann Thomas-Mann Hermann-Hesse Kolping Kneipp Stifter Hebel Jahn Arndt
Blumen Obst Apfel Birnen Kirsch Pflaumen Wein Hopfen Korn Hafer Gersten Roggen Weizen
Raps Flachs Hanf Lerchen Finken Amsel Drossel Schwalben Tauben Falken Adler Habicht
Eulen Raben Kranich Storchen Reiher Hirsch Reh Fuchs Dachs Hasen Biber Otter Wolfs
Bären Luchs Lärchen Kiefern Buchsbaum Hasel Wacholder Efeu Ginster Rhododendron
Industrie Gewerbe Handwerker Schützen Turner Sänger Jäger Fischer Bauern Müller
Schmiede Bäcker Gerber Weber Färber Zimmer Tischler Glaser Töpfer Brauerei Ziegelei
Friedhof Kapellen Pfarr Kantor Küster Schäfer Hirten Ring Ost West Nord Süd Ober
Unter Mittel Neu Alt Groß Klein Lang Kurz Breit Hoch Tief Sommer Winter Frühlings
Herbst Morgen Abend Friedens Freiheits Einheits Europa Kaiser König Fürsten Grafen
Herzog Prinzen Bürger Rats Stadt Land Bergmanns Hütten Zechen Schacht Stollen
""".split()

DE_SUFFIXES = [("straße", 40), ("weg", 24), ("allee", 4), ("gasse", 5), ("platz", 4),
               ("ring", 5), ("damm", 2), ("pfad", 2), ("steig", 2), ("ufer", 1), ("chaussee", 1)]

DE_CITY_ADJ = """
Berliner Hamburger Münchner Kölner Frankfurter Stuttgarter Düsseldorfer Leipziger
Dresdner Hannoversche Nürnberger Bremer Bonner Mainzer Kasseler Erfurter Magdeburger
Potsdamer Rostocker Kieler Lübecker Augsburger Würzburger Regensburger Ulmer Trierer
Aachener Bielefelder Mannheimer Karlsruher Freiburger Heidelberger Darmstädter
Wiesbadener Koblenzer Saarbrücker Hallesche Chemnitzer Zwickauer Jenaer Weimarer
Göttinger Braunschweiger Oldenburger Osnabrücker Münsteraner Dortmunder Essener
""".split()

DE_PREPOSITIONAL = """
Am Markt|Am Bahnhof|Am Anger|Am Hang|Am Rain|Am Mühlbach|Am Sportplatz|Am Friedhof
Am Waldrand|Am Kirchberg|Am Lindenhof|Am Schlossberg|Am Eichenhain|Am Steinbruch
An der Kirche|An der Mühle|An der Linde|An der Post|An der Schule|An den Teichen
Auf dem Berg|Auf der Höhe|Auf der Heide|Auf dem Kamp|Im Winkel|Im Grund|Im Wiesengrund
Im Vogelsang|Im Kirschgarten|Im Rosengarten|In den Gärten|In der Au|Zur Mühle
Zum Sportplatz|Zur Linde|Zum Steinbruch|Zur Kapelle|Unter den Linden|Hinter der Kirche
Hinterm Dorf|Vor dem Tor|Alter Markt|Neuer Weg|Kurze Straße|Lange Straße|Breite Straße
Hohe Straße|Alte Dorfstraße|Neue Straße|Obere Hauptstraße|Untere Mühlgasse
""".replace("\n", "|").split("|")


def street_words():
    rows = []
    for word in dict.fromkeys(US_STREET_WORDS + US_ORDINALS):
        rows.append(("en_US", "street", "X", word, "", 1))
    seen = set()

    def add(value, alt, weight):
        if value not in seen:
            seen.add(value)
            rows.append(("de_DE", "street", "X", value, alt, weight))

    for base in dict.fromkeys(DE_STREET_BASES):
        for suffix, weight in DE_SUFFIXES:
            if "-" in base:  # Thomas-Mann -> Thomas-Mann-Straße
                value = f"{base}-{suffix.capitalize()}"
            else:
                value = base + suffix
            alt = value[:-6] + ("Str." if value.endswith("Straße") else "str.") if suffix == "straße" else ""
            add(value, alt, weight)
    for adj in DE_CITY_ADJ:
        add(f"{adj} Straße", f"{adj} Str.", 30)
        add(f"{adj} Allee", "", 4)
        add(f"{adj} Ring", "", 4)
        add(f"{adj} Platz", "", 3)
    for name in DE_PREPOSITIONAL:
        name = name.strip()
        if name:
            alt = name[:-6] + "Str." if name.endswith("Straße") else ""
            add(name, alt, 20)
    return rows


# --------------------------------------------------------------------------
# Markov chain corpora
# --------------------------------------------------------------------------

CORPORA = {
    "en_US": [1661, 1342, 84],          # Sherlock Holmes, Pride and Prejudice, Frankenstein
    "de_DE": [5323, 22367, 2407, 34811],  # Effi Briest, Die Verwandlung, Werther, Buddenbrooks
}
MAX_TOKENS = 230_000

ABBREVIATIONS = {
    "Mr.", "Mrs.", "Ms.", "Dr.", "St.", "Jr.", "Sr.", "Prof.", "Rev.", "Col.", "Capt.", "Gen.",
    "Lt.", "No.", "Co.", "vs.", "etc.", "i.e.", "e.g.",
    "Hr.", "Fr.", "Nr.", "bzw.", "usw.", "ca.", "z.", "B.", "u.", "v.", "d.", "h.", "s.", "o.",
    "Frl.", "Geh.", "Kom.", "Kommerzienrat.",
}
QUOTES = "\"'“”„‟«»‹›‘’‚_*[](){}"


def gutenberg_body(text: str) -> str:
    start = re.search(r"\*\*\* ?START OF (THE|THIS) PROJECT GUTENBERG.*?\*\*\*", text)
    end = re.search(r"\*\*\* ?END OF (THE|THIS) PROJECT GUTENBERG", text)
    return text[start.end() if start else 0:end.start() if end else len(text)]


def tokenize_paragraph(paragraph: str):
    paragraph = re.sub(r"\s*(--|—|–)\s*", " ", paragraph)
    tokens = []
    for raw in paragraph.split():
        tok = raw.strip(QUOTES)
        # inner apostrophes (don't, it's) survive, other quote marks go
        tok = re.sub(r"[\"“”„«»_*]", "", tok)
        if not tok or not re.search(r"\w", tok):
            continue
        if tok in ABBREVIATIONS or re.fullmatch(r"[A-ZÄÖÜ]\.", tok):
            tok = tok.rstrip(".")
        tokens.append(tok)
    return tokens


def is_heading(paragraph: str) -> bool:
    letters = [c for c in paragraph if c.isalpha()]
    if not letters:
        return True
    upper = sum(c.isupper() for c in letters) / len(letters)
    return upper > 0.6 or re.match(r"^(CHAPTER|Chapter|Kapitel|KAPITEL|Letter|BRIEF|[IVXLC]+\.)\b", paragraph) is not None


def ends_sentence(tok: str) -> bool:
    return tok[-1] in ".!?"


def markov():
    state_rows = []
    transition_rows = []
    next_id = 1
    for locale, ids in CORPORA.items():
        paragraphs = []
        total = 0
        for gid in ids:
            body = gutenberg_body((RAW / f"gutenberg_{gid}.txt").read_text(encoding="utf-8-sig"))
            for para in re.split(r"\n\s*\n", body):
                para = " ".join(para.split())
                if len(para.split()) < 12 or is_heading(para):
                    continue
                toks = tokenize_paragraph(para)
                if len(toks) < 8:
                    continue
                paragraphs.append(toks)
                total += len(toks)
                if total >= MAX_TOKENS:
                    break
            if total >= MAX_TOKENS:
                break
        transitions = collections.defaultdict(collections.Counter)
        starts = collections.Counter()
        for toks in paragraphs:
            for i in range(len(toks) - 2):
                transitions[(toks[i], toks[i + 1])][toks[i + 2]] += 1
            for i in range(len(toks) - 1):
                at_start = i == 0 or ends_sentence(toks[i - 1])
                if at_start and toks[i][0].isupper() and not ends_sentence(toks[i]):
                    starts[(toks[i], toks[i + 1])] += 1
        states = set(transitions) | set(starts)
        for counter in list(transitions.items()):
            (w1, w2), nexts = counter
            for w3 in nexts:
                states.add((w2, w3))
        ids_by_state = {}
        for state in sorted(states):
            ids_by_state[state] = next_id
            next_id += 1
        for state, sid in ids_by_state.items():
            state_rows.append((sid, locale, state[0], state[1], starts.get(state, 0)))
        for (w1, w2), nexts in transitions.items():
            sid = ids_by_state[(w1, w2)]
            for w3, cnt in nexts.items():
                transition_rows.append((sid, w3, ids_by_state[(w2, w3)], cnt))
        print(f"  {locale}: {total} tokens, {len(ids_by_state)} states, {sum(len(n) for n in transitions.values())} transitions, {len(starts)} sentence starts")
    return state_rows, transition_rows


def main():
    print("names")
    write_csv("names", ["locale", "kind", "gender", "value", "weight"], us_names() + de_names())
    print("places")
    write_csv("places", ["locale", "postal_code", "city", "region", "region_code", "weight"], places())
    print("streets")
    write_csv("words", ["locale", "kind", "gender", "value", "alt", "weight"], street_words())
    print("markov")
    states, transitions = markov()
    write_csv("markov_states", ["state_id", "locale", "w1", "w2", "start_weight"], states)
    write_csv("markov_transitions", ["state_id", "next_word", "next_state_id", "weight"], transitions)


if __name__ == "__main__":
    main()
