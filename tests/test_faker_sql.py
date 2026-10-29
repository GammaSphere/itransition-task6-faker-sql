"""Tests of the SQL faker against a database built by db/setup.py.

    DATABASE_URL=postgresql://faker:faker@localhost:5544/faker  pytest -q
"""
from __future__ import annotations

import math
import os
import re
import statistics

import psycopg
import pytest

URL = os.environ.get("DATABASE_URL", "postgresql://faker:faker@127.0.0.1:5544/faker")
LOCALES = ["en_US", "de_DE"]


@pytest.fixture(scope="module")
def db():
    with psycopg.connect(URL, autocommit=True) as conn:
        yield conn


def users(db, locale, seed, batch=0, size=10, text=True):
    cur = db.execute("SELECT * FROM faker.generate_users(%s, %s, %s, %s, %s)", (locale, seed, batch, size, text))
    cols = [d.name for d in cur.description]
    return [dict(zip(cols, row)) for row in cur.fetchall()]


def strip_position(rows):
    return [{k: v for k, v in r.items() if k not in ("batch", "batch_index")} for r in rows]


# --------------------------------------------------------------- reproducibility

@pytest.mark.parametrize("locale", LOCALES)
def test_same_arguments_give_same_users(db, locale):
    assert users(db, locale, 123, 4) == users(db, locale, 123, 4)


@pytest.mark.parametrize("locale", LOCALES)
def test_user_depends_on_position_not_on_batch_size(db, locale):
    by_ten = users(db, locale, 99, 2, 10) + users(db, locale, 99, 3, 10)
    by_twenty = users(db, locale, 99, 1, 20)
    assert strip_position(by_ten) == strip_position(by_twenty)
    assert [u["pos"] for u in by_twenty] == list(range(20, 40))


def test_single_user_matches_batch(db):
    batch = users(db, "en_US", 5, 3, 10)
    cur = db.execute("SELECT * FROM faker.generate_user('en_US', 5, 34)")
    single = dict(zip([d.name for d in cur.description], cur.fetchone()))
    assert strip_position([single]) == strip_position([batch[4]])


def test_seed_locale_and_batch_change_the_data(db):
    base = {u["full_name"] for u in users(db, "en_US", 1)}
    assert base.isdisjoint({u["full_name"] for u in users(db, "en_US", 2)})
    assert base.isdisjoint({u["full_name"] for u in users(db, "en_US", 1, 1)})
    assert base.isdisjoint({u["full_name"] for u in users(db, "de_DE", 1)})


def test_known_values_are_stable(db):
    """Golden values: the same data on every server (local Docker, Neon, ...)."""
    first = users(db, "en_US", 42, 0, 1, False)[0]
    assert first["full_name"] == "Diane Bui"
    assert first["email"] == "diane.b@yahoo.com"
    assert first["phone"] == "+1 905 477 6129"


def test_bad_arguments_are_rejected(db):
    with pytest.raises(psycopg.errors.RaiseException, match="unknown locale"):
        users(db, "xx_XX", 1)
    with pytest.raises(psycopg.errors.RaiseException):
        users(db, "en_US", 1, -1)


# --------------------------------------------------------------- content

@pytest.mark.parametrize("locale", LOCALES)
def test_every_field_is_filled(db, locale):
    for u in users(db, locale, 7, 0, 200):
        for key, value in u.items():
            assert value is not None and value != "", (key, u)


@pytest.mark.parametrize("locale", LOCALES)
def test_email_and_phone_look_valid(db, locale):
    for u in users(db, locale, 8, 0, 300, False):
        assert re.fullmatch(r"[a-z0-9._-]+@[a-z0-9.-]+\.[a-z]+", u["email"]), u["email"]
        digits = re.sub(r"\D", "", u["phone"])
        assert 9 <= len(digits) <= 16, u["phone"]


def test_us_phone_numbers_follow_nanp(db):
    for u in users(db, "en_US", 9, 0, 300, False):
        digits = re.sub(r"\D", "", u["phone"].split(" x")[0].split(" ext.")[0])
        digits = digits[1:] if len(digits) == 11 else digits
        assert len(digits) == 10 and digits[0] in "23456789" and digits[3] in "23456789", u["phone"]


@pytest.mark.parametrize("locale, zip_re", [("en_US", r"\b\d{5}(-\d{4})?\b"), ("de_DE", r"\b\d{5}\b")])
def test_address_has_postal_code(db, locale, zip_re):
    for u in users(db, locale, 10, 0, 300, False):
        assert re.search(zip_re, u["address"]), u["address"]


def test_names_and_formats_vary(db):
    rows = users(db, "en_US", 11, 0, 2000, False)
    assert len({u["full_name"] for u in rows}) > 1950
    assert any(u["full_name"].startswith(("Mr.", "Ms.", "Mrs.", "Dr.")) for u in rows)
    assert any(re.search(r" [A-Z]\. ", u["full_name"]) for u in rows)        # middle initial
    assert any("," in u["full_name"] for u in rows)                          # "Last, First"
    assert any("\n" in u["address"] for u in rows)                           # multi-line address
    assert any("Box" in u["address"] for u in rows)
    de = users(db, "de_DE", 11, 0, 2000, False)
    assert any(u["full_name"].startswith(("Herr", "Frau")) for u in de)
    assert any("str." in u["address"] or "Str." in u["address"] for u in de)
    assert any(c in u["full_name"] for u in de for c in "äöüß")


@pytest.mark.parametrize("locale", LOCALES)
def test_text_is_in_sentences(db, locale):
    for u in users(db, locale, 12, 0, 100):
        assert u["about"][0].isupper() and u["about"][-1] in ".!?", u["about"]
        assert 3 <= len(u["about"].split()) <= 40


# --------------------------------------------------------------- distributions

def test_uniform_values_cover_unit_interval(db):
    row = db.execute("SELECT min(u), max(u), avg(u), stddev_pop(u) FROM "
                     "(SELECT faker.random_uniform(i, 3) AS u FROM generate_series(1, 100000) i) t").fetchone()
    lo, hi, mean, sd = row
    assert lo >= 0 and hi < 1
    assert abs(mean - 0.5) < 0.005 and abs(sd - math.sqrt(1 / 12)) < 0.005


def test_normal_values(db):
    mean, sd, within1, within2 = db.execute(
        "SELECT avg(z), stddev_pop(z), avg((abs(z) < 1)::int), avg((abs(z) < 2)::int) FROM "
        "(SELECT faker.random_normal(i, 1) AS z FROM generate_series(1, 100000) i) t").fetchone()
    assert abs(mean) < 0.02 and abs(sd - 1) < 0.02
    assert abs(float(within1) - 0.6827) < 0.01 and abs(float(within2) - 0.9545) < 0.005


def test_points_are_uniform_on_the_sphere(db):
    """For a uniform point on a sphere sin(latitude) is uniform on [-1, 1]:
    the band |lat| < 30 deg holds half of the area (uniform latitudes in
    degrees would put only a third there)."""
    rows = db.execute("SELECT latitude, longitude FROM generate_series(1, 40000) i, "
                      "faker.random_point_on_sphere(i::bigint, 0)").fetchall()
    lats = [r[0] for r in rows]
    lons = [r[1] for r in rows]
    assert all(-90 <= a <= 90 for a in lats) and all(-180 <= o < 180 for o in lons)
    band = sum(abs(a) < 30 for a in lats) / len(lats)
    assert abs(band - 0.5) < 0.01
    # chi-square of sin(lat) in 20 equal bins (19 dof, 99.9% quantile 43.8)
    bins = [0] * 20
    for a in lats:
        bins[min(19, int((math.sin(math.radians(a)) + 1) / 2 * 20))] += 1
    expected = len(lats) / 20
    assert sum((b - expected) ** 2 / expected for b in bins) < 43.8
    assert abs(statistics.mean(lons)) < 3


@pytest.mark.parametrize("locale", LOCALES)
def test_height_follows_body_stats(db, locale):
    stats = {g: (m, s) for g, m, s in db.execute(
        "SELECT gender, height_mean_cm, height_sd_cm FROM faker.body_stats WHERE locale = %s", (locale,))}
    rows = users(db, locale, 13, 0, 6000, False)
    for gender, (mean, sd) in stats.items():
        h = [float(u["height_cm"]) for u in rows if u["gender"] == gender]
        assert abs(statistics.mean(h) - mean) < 0.5
        assert abs(statistics.pstdev(h) - sd) < 0.4


def test_eye_colors_follow_weights(db):
    weights = dict(db.execute("SELECT value, weight FROM faker.words WHERE locale = 'en_US' AND kind = 'eye_color'"))
    total = sum(weights.values())
    rows = users(db, "en_US", 14, 0, 6000, False)
    for color, weight in weights.items():
        share = sum(u["eye_color"] == color for u in rows) / len(rows)
        assert abs(share - weight / total) < 0.02, color


# --------------------------------------------------------------- helpers

def test_fill_template(db):
    got = db.execute("""SELECT faker.fill_template('{title} {first} {last} , {x}', '{"first": "Ann", "last": "Lee", "title": null}')""").fetchone()[0]
    assert got == "Ann Lee,"


def test_random_digits_masks(db):
    got = db.execute("SELECT faker.random_digits(i, 1, '#%^?!-x') FROM generate_series(1, 2000) i").fetchall()
    for (s,) in got:
        assert re.fullmatch(r"[0-9][1-9][2-9][A-Z][a-h]-x", s), s


def test_formatting(db):
    row = db.execute("SELECT faker.format_height('en_US', 180.3), faker.format_height('de_DE', 180.3), "
                     "faker.format_weight('en_US', 80), faker.format_weight('de_DE', 79.84), "
                     "faker.format_coordinates(52.52, -13.405, 'dms'), faker.slug('Jürgen O''Brien')").fetchone()
    assert row == ("5'11\"", "1,80 m", "176 lb", "79,8 kg", "52°31′12″N 13°24′18″W", "juergenobrien")
