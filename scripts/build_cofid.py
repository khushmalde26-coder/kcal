"""Build Kcal/Resources/cofid.json from McCance and Widdowson's CoFID 2021.

Source: https://www.gov.uk/government/publications/composition-of-foods-integrated-dataset-cofid
Licence: Open Government Licence v3.0 (Public Health England, 2021).

Usage (from the repo root):
    python3 -m venv scripts/.venv && scripts/.venv/bin/pip install openpyxl
    curl -L -o scripts/data/cofid_2021.xlsx "<xlsx link from the page above>"
    scripts/.venv/bin/python scripts/build_cofid.py scripts/data/cofid_2021.xlsx

Output: a JSON array, values per 100 g (per 100 ml for alcoholic drinks), short keys:
    i id, n name, k kcal, p protein, c carbs, f fat,
    fi fibre, s sugars, sf saturated fat, sa salt, l 1 when liquid.
Missing values ("N" or blank) are omitted; trace ("Tr") counts as 0.
"""
import json
import sys
from pathlib import Path

import openpyxl

OUT = Path(__file__).resolve().parent.parent / "Kcal" / "Resources" / "cofid.json"
HEADER_ROWS = 3  # long names, codes, descriptions


def number(value):
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    text = str(value).strip()
    if text in ("", "N"):
        return None
    if text == "Tr":
        return 0.0
    try:
        return float(text.replace(",", ""))
    except ValueError:
        return None


def sheet(workbook, name):
    """Rows keyed by food code, with columns keyed by the CoFID code row (e.g. KCALS)."""
    rows = list(workbook[name].iter_rows(values_only=True))
    codes = rows[1]
    table = {}
    for row in rows[HEADER_ROWS:]:
        if not row or not row[0]:
            continue
        values = {codes[i]: row[i] for i in range(len(codes)) if codes[i]}
        values["code"], values["name"], values["group"] = row[0], row[1], row[3] or ""
        table[str(row[0]).strip()] = values
    return table


def rounded(value):
    if value is None:
        return None
    return round(value, 1) if value < 100 else round(value)


def main(path):
    workbook = openpyxl.load_workbook(path, read_only=True, data_only=True)
    proximates = sheet(workbook, "1.3 Proximates")
    inorganics = sheet(workbook, "1.4 Inorganics")

    foods = []
    for code, row in proximates.items():
        kcal = number(row.get("KCALS"))
        name = (row.get("name") or "").strip()
        if kcal is None or not name:
            continue
        fibre = number(row.get("AOACFIB"))
        if fibre is None:
            fibre = number(row.get("ENGFIB"))
        sodium = number(inorganics.get(code, {}).get("NA"))
        food = {
            "i": code,
            "n": name,
            "k": rounded(kcal),
            "p": rounded(number(row.get("PROT")) or 0),
            "c": rounded(number(row.get("CHO")) or 0),
            "f": rounded(number(row.get("FAT")) or 0),
            "fi": rounded(fibre),
            "s": rounded(number(row.get("TOTSUG"))),
            "sf": rounded(number(row.get("SATFOD"))),
            # Salt equivalent: sodium (mg) x 2.5 / 1000 g.
            "sa": None if sodium is None else round(sodium * 2.5 / 1000, 2),
        }
        # Group Q is alcoholic beverages, given per 100 ml.
        if str(row.get("group")).startswith("Q"):
            food["l"] = 1
        foods.append({k: v for k, v in food.items() if v is not None})

    foods.sort(key=lambda f: f["n"].lower())
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(foods, ensure_ascii=False, separators=(",", ":")))
    print(f"Wrote {len(foods)} foods to {OUT} ({OUT.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main(sys.argv[1])
