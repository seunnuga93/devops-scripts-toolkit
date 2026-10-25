from datetime import date

from devops_toolkit import azure_cost_report as acr

# Shape of a real Cost Management query response (trimmed).
SAMPLE = {
    "properties": {
        "columns": [
            {"name": "Cost", "type": "Number"},
            {"name": "ResourceGroup", "type": "String"},
            {"name": "Currency", "type": "String"},
        ],
        "rows": [
            [12.5, "rg-web", "GBP"],
            [100.0, "rg-aks", "GBP"],
            [7.5, "rg-web", "GBP"],
            [3.0, "", "GBP"],
        ],
    }
}


def test_build_query_dates_and_grouping():
    q = acr.build_query(30, "ServiceName", today=date(2026, 3, 31))
    assert q["timePeriod"] == {"from": "2026-03-01", "to": "2026-03-31"}
    assert q["dataset"]["grouping"] == [{"type": "Dimension", "name": "ServiceName"}]


def test_parse_rows_sums_and_sorts():
    rows, currency = acr.parse_rows(SAMPLE, "ResourceGroup")
    assert rows == [("rg-aks", 100.0), ("rg-web", 20.0), ("(untagged)", 3.0)]
    assert currency == "GBP"


def test_format_report_totals_and_top_n():
    rows, currency = acr.parse_rows(SAMPLE, "ResourceGroup")
    report = acr.format_report(rows, currency, top=2)
    assert "rg-aks" in report and "rg-web" in report
    assert "(1 more)" in report
    assert report.splitlines()[-1].split() == ["TOTAL", "123.00", "GBP"]


def test_main_uses_api_response(monkeypatch, capsys):
    monkeypatch.setattr(acr, "query", lambda sub, body: SAMPLE)
    assert acr.main(["--subscription", "abc", "--csv"]) == 0
    out = capsys.readouterr().out.splitlines()
    assert out[0] == "ResourceGroup,cost,currency"
    assert out[1] == "rg-aks,100.00,GBP"
