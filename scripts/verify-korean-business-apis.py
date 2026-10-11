#!/usr/bin/env python3
"""Read-only live API checks. Never print credentials, request URLs or raw errors."""

import argparse
import io
import json
import os
import re
import sys
import zipfile
from datetime import datetime
from decimal import Decimal
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import urlopen
from xml.etree import ElementTree
from zoneinfo import ZoneInfo


class CheckFailure(Exception):
    """Only fixed, credential-free diagnostic codes may be used here."""


def require(condition, code):
    if not condition:
        raise CheckFailure(code)


def load_keys(path):
    names = ("KOSIS_API_KEY", "DART_API_KEY")
    values = {name: os.environ.get(name, "").strip() for name in names}
    if path.is_file():
        for line in path.read_text(encoding="utf-8").splitlines():
            name, separator, value = line.removeprefix("export ").partition("=")
            name = name.strip()
            if separator and name in names and not values[name]:
                values[name] = value.strip().strip("\"'")
    require(all(values.values()), "missing_api_key")
    return values


def fetch(endpoint, parameters):
    with urlopen(endpoint + "?" + urlencode(parameters), timeout=15) as response:
        require(response.status == 200, "http_status")
        content = response.read(20_000_001)
    require(len(content) <= 20_000_000, "response_too_large")
    return content


def kosis(keys, endpoint, parameters):
    result = json.loads(fetch("https://kosis.kr/openapi/" + endpoint, {
        "apiKey": keys["KOSIS_API_KEY"], "format": "json", "jsonVD": "Y",
        **parameters,
    }))
    require(isinstance(result, list) and bool(result), "kosis_no_rows_or_api_error")
    return result


def dart(keys, endpoint, parameters):
    result = json.loads(fetch("https://opendart.fss.or.kr/api/" + endpoint, {
        "crtfc_key": keys["DART_API_KEY"], **parameters,
    }))
    require(isinstance(result, dict), "dart_invalid_response")
    status = result.get("status", "")
    if status != "000":
        code = status if re.fullmatch(r"\d{3}", str(status)) else "invalid"
        raise CheckFailure("dart_status_" + str(code))
    require(bool(result.get("list")), "dart_no_rows")
    return result["list"]


def check_search(keys):
    rows = kosis(keys, "statisticsSearch.do", {
        "method": "getList", "searchNm": "성 및 연령별 1인가구",
        "orgId": "101", "startCount": "1", "resultCount": "10",
    })
    require(any(row.get("TBL_ID") == "DT_1PL1502" for row in rows), "table_not_found")
    return f"rows={len(rows)}, target=DT_1PL1502"


def check_metadata(keys):
    for obj_id, item_id in (("A", "11"), ("B", "000"), ("13999001", "T00")):
        rows = kosis(keys, "statisticsData.do", {
            "method": "getMeta", "type": "ITM", "orgId": "101",
            "tblId": "DT_1PL1502", "objId": obj_id, "itmId": item_id,
        })
        require(any(row.get("ITM_ID") == item_id for row in rows), "metadata_code_mismatch")
    return "region/age/item=3 verified selections"


def check_series(keys, table_id, selections, item_id, unit, labels):
    rows = kosis(keys, "Param/statisticsParameterData.do", {
        "method": "getList", "orgId": "101", "tblId": table_id,
        "itmId": item_id, "prdSe": "Y", "newEstPrdCnt": "1", **selections,
    })
    require(len(rows) == 1, "unexpected_cell_count")
    row = rows[0]
    require(row.get("TBL_ID") == table_id and row.get("ITM_ID") == item_id, "series_id_mismatch")
    for parameter, value in selections.items():
        require(row.get("C" + parameter[-1]) == value, "dimension_code_mismatch")
    for field, label in labels.items():
        require(row.get(field) == label, "dimension_label_mismatch")
    require(row.get("UNIT_NM") == unit, "unit_mismatch")
    require(re.fullmatch(r"\d{4}", row.get("PRD_DE", "")), "year_missing")
    require(row.get("PRD_SE") == "A", "annual_response_code_changed")
    require(bool(row.get("LST_CHN_DE")), "update_date_missing")
    amount = Decimal(row["DT"])
    require(amount.is_finite() and amount >= 0 and amount == amount.to_integral_value(), "invalid_count")
    return f"table={table_id}, period={row['PRD_DE']}, value={amount} {unit}, response_frequency=A"


def check_company(keys):
    content = fetch("https://opendart.fss.or.kr/api/corpCode.xml", {
        "crtfc_key": keys["DART_API_KEY"],
    })
    with zipfile.ZipFile(io.BytesIO(content)) as archive:
        info = archive.getinfo("CORPCODE.xml")
        require(info.file_size <= 100_000_000, "company_index_too_large")
        root = ElementTree.fromstring(archive.read(info))
    matches = [row for row in root.findall("list") if row.findtext("corp_name") == "풀무원"]
    require(len(matches) == 1, "company_name_ambiguous")
    require(matches[0].findtext("corp_code") == "00155355", "company_code_mismatch")
    return "company=풀무원, corp_code=00155355, ZIP/XML verified"


def check_disclosures(keys):
    rows = dart(keys, "list.json", {
        "corp_code": "00155355", "bgn_de": "20250101",
        "end_de": datetime.now(ZoneInfo("Asia/Seoul")).strftime("%Y%m%d"),
        "pblntf_ty": "A", "last_reprt_at": "Y", "page_count": "3",
    })
    require(all(re.fullmatch(r"\d{14}", row.get("rcept_no", "")) for row in rows), "receipt_missing")
    require(all(row.get("corp_code") == "00155355" for row in rows), "disclosure_company_mismatch")
    return f"rows={len(rows)}, valid_receipt_numbers={len(rows)}"


def check_financials(keys, year, report):
    rows = dart(keys, "fnlttSinglAcntAll.json", {
        "corp_code": "00155355", "bsns_year": year,
        "reprt_code": report, "fs_div": "CFS",
    })
    require(all(row.get("currency") == "KRW" for row in rows), "currency_changed")
    require(all(row.get("bsns_year") == year and row.get("reprt_code") == report for row in rows), "financial_period_mismatch")
    require(all(row.get("corp_code") == "00155355" for row in rows), "financial_company_mismatch")
    require(all(re.fullmatch(r"\d{14}", row.get("rcept_no", "")) for row in rows), "financial_receipt_missing")
    require(all(row.get("sj_div") in {"BS", "IS", "CIS", "CF", "SCE"} for row in rows), "statement_type_changed")
    require(all(row.get("thstrm_nm") for row in rows), "financial_period_label_missing")
    amounts = [row["thstrm_amount"] for row in rows if row.get("thstrm_amount", "").strip()]
    require(bool(amounts), "financial_amounts_missing")
    for amount in amounts:
        require(Decimal(amount.replace(",", "")).is_finite(), "invalid_financial_amount")
    cumulative = 0
    for row in rows:
        amount = row.get("thstrm_add_amount", "").strip()
        if amount:
            require(Decimal(amount.replace(",", "")).is_finite(), "invalid_cumulative_amount")
            if row["sj_div"] in {"IS", "CIS"}:
                cumulative += 1
    if report != "11011":
        require(cumulative > 0, "income_statement_cumulative_fields_missing")
    return f"year={year}, report={report}, CFS, rows={len(rows)}, currency=KRW, income_cumulative_rows={cumulative}"


def run_check(name, callback):
    try:
        print(f"PASS {name}: {callback()}", flush=True)
        return True
    except CheckFailure as error:
        diagnostic = str(error)
    except HTTPError as error:
        diagnostic = f"http_{error.code}"
    except (URLError, TimeoutError):
        diagnostic = "network_or_timeout"
    except Exception as error:
        diagnostic = type(error).__name__
    print(f"FAIL {name}: {diagnostic}", flush=True)
    return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--env-file", type=Path, default=Path(__file__).resolve().parents[1] / ".env")
    arguments = parser.parse_args()
    try:
        keys = load_keys(arguments.env_file)
    except Exception as error:
        print("FAIL configuration: " + (str(error) if isinstance(error, CheckFailure) else type(error).__name__))
        return 1
    checks = [
        ("KOSIS_SEARCH", lambda: check_search(keys)),
        ("KOSIS_METADATA", lambda: check_metadata(keys)),
        ("KOSIS_HOUSEHOLDS", lambda: check_series(keys, "DT_1PL1502", {"objL1": "11", "objL2": "000"}, "T00", "가구", {"C1_NM": "서울특별시", "C2_NM": "합계"})),
        ("KOSIS_BUSINESSES", lambda: check_series(keys, "DT_1K52D01", {"objL1": "11", "objL2": "P", "objL3": "0"}, "T1", "개", {"C1_NM": "서울", "C2_NM": "교육 서비스업(85)", "C3_NM": "계"})),
        ("KOSIS_SMALL_BUSINESSES", lambda: check_series(keys, "DT_1K52D03", {"objL1": "11", "objL2": "P", "objL3": "1"}, "T1", "개", {"C1_NM": "서울", "C2_NM": "교육 서비스업(85)", "C3_NM": "1 - 4명"})),
        ("DART_COMPANY_INDEX", lambda: check_company(keys)),
        ("DART_DISCLOSURES", lambda: check_disclosures(keys)),
        ("DART_ANNUAL_FINANCIALS", lambda: check_financials(keys, "2025", "11011")),
        ("DART_HALF_YEAR_FINANCIALS", lambda: check_financials(keys, "2026", "11012")),
    ]
    results = [run_check(name, callback) for name, callback in checks]
    print(f"RESULT {sum(results)}/{len(results)} checks passed")
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
