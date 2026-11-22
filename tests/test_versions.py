"""Tests for the version feature registry and /version endpoint."""
import pytest

from app import (LATEST_VERSION, SUPPORTED_VERSIONS, VERSION_FILE,
                 create_app, features_for, parse_version, resolve_version)


def make_client(tmp_path, version):
    app = create_app(db_path=str(tmp_path / "v.db"), version=version)
    app.config["TESTING"] = True
    return app.test_client()


# ---------------- Pure version logic ----------------
def test_parse_version():
    assert parse_version("2.0.1") == (2, 0, 1)
    assert parse_version("1.1") < parse_version("1.1.2")
    assert parse_version("2.2.4") < parse_version("3.2.4")


def test_parse_version_invalid():
    with pytest.raises(ValueError):
        parse_version("v1.x")


def test_versions_are_in_order():
    parsed = [parse_version(v) for v in SUPPORTED_VERSIONS]
    assert parsed == sorted(parsed)
    assert LATEST_VERSION == "3.2.4"


@pytest.mark.parametrize("version, expected", [
    ("1.0", {"programs"}),
    ("1.1", {"programs", "calories", "clients"}),
    ("2.0.1", {"programs", "calories", "clients", "progress"}),
    ("2.2.4", {"programs", "calories", "clients", "progress", "bmi",
               "workouts"}),
    ("3.2.4", {"programs", "calories", "clients", "progress", "bmi",
               "workouts", "generator"}),
])
def test_features_for(version, expected):
    assert features_for(version) == expected


def test_features_grow_with_each_release():
    previous = set()
    for version in SUPPORTED_VERSIONS:
        current = features_for(version)
        assert previous < current
        previous = current


# ---------------- Version resolution ----------------
def test_resolve_version_from_env(monkeypatch):
    monkeypatch.setenv("APP_VERSION", "2.0.1")
    assert resolve_version() == "2.0.1"


def test_resolve_version_from_file(monkeypatch):
    monkeypatch.delenv("APP_VERSION", raising=False)
    assert resolve_version() == VERSION_FILE.read_text().strip()


def test_version_file_is_supported():
    assert VERSION_FILE.read_text().strip() in SUPPORTED_VERSIONS


# ---------------- Endpoints per version ----------------
@pytest.mark.parametrize("version", SUPPORTED_VERSIONS)
def test_version_endpoint(tmp_path, version):
    body = make_client(tmp_path, version).get("/version").get_json()
    assert body["version"] == version
    assert set(body["features"]) == features_for(version)
    assert body["hostname"]


@pytest.mark.parametrize("version", SUPPORTED_VERSIONS)
def test_health_in_every_version(tmp_path, version):
    res = make_client(tmp_path, version).get("/health")
    assert res.status_code == 200


def test_home_shows_version(tmp_path):
    body = make_client(tmp_path, "2.0.1").get("/").get_json()
    assert body["version"] == "2.0.1"
    assert "/clients/<name>/progress" in body["endpoints"]
    assert "/bmi" not in body["endpoints"]


def test_v1_0_has_programs_only(tmp_path):
    client = make_client(tmp_path, "1.0")
    assert client.get("/programs").status_code == 200
    assert client.get("/clients").status_code == 404
    assert client.post("/calories", json={"weight": 70,
                                          "program": "FL"}).status_code == 404


def test_v1_1_adds_clients(tmp_path):
    client = make_client(tmp_path, "1.1")
    res = client.post("/clients", json={"name": "Ravi", "weight": 70,
                                        "program": "FL"})
    assert res.status_code == 201
    assert client.get("/clients/Ravi/progress").status_code == 404


def test_v2_0_1_adds_progress(tmp_path):
    client = make_client(tmp_path, "2.0.1")
    client.post("/clients", json={"name": "Ravi", "weight": 70,
                                  "program": "FL"})
    res = client.post("/clients/Ravi/progress",
                      json={"week": "W1", "adherence": 80})
    assert res.status_code == 201
    assert client.post("/bmi", json={"weight": 70,
                                     "height": 175}).status_code == 404


def test_v2_2_4_adds_bmi_and_workouts(tmp_path):
    client = make_client(tmp_path, "2.2.4")
    assert client.post("/bmi", json={"weight": 70,
                                     "height": 175}).status_code == 200
    client.post("/clients", json={"name": "Ravi", "weight": 70,
                                  "program": "MG"})
    assert client.get("/clients/Ravi/workouts").status_code == 200
    assert client.post(
        "/clients/Ravi/generate-program").status_code == 404


def test_v3_2_4_adds_generator(tmp_path):
    client = make_client(tmp_path, "3.2.4")
    client.post("/clients", json={"name": "Ravi", "weight": 70,
                                  "program": "MG"})
    assert client.post(
        "/clients/Ravi/generate-program").status_code == 200
