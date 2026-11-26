"""Profit mode: expected income = predicted yield x price, for several crops side by side.

Uses the trained yield model already in the project. Price comes from (1) the farmer, or
(2) live Agmarknet price when a DATA_GOV_API_KEY is set. Costs are optional; without costs
the result is only an INCOME estimate, never called profit.
"""
from app.i18n import M, _ as tr3, norm, t
from app.services import prices, registry, soil_service, yield_service

ACRE_PER_HA = 2.471
LONG_CROPS = {"Sugarcane", "Banana", "Turmeric", "Ginger", "Tapioca", "Papaya", "Mango", "Grapes"}
DATA_LAST_YEAR = 2015

M["profit_estimate"] = tr3(
    "This is an estimate of INCOME (yield x price). Your costs are not included, so it is not profit. Type your cost per {unit} to see net profit.",
    "\u092F\u0939 \u0906\u092F \u0915\u093E \u0905\u0928\u0941\u092E\u093E\u0928 \u0939\u0948 (\u0909\u092A\u091C x \u092D\u093E\u0935)\u0964 \u0906\u092A\u0915\u0940 \u0932\u093E\u0917\u0924 \u0936\u093E\u092E\u093F\u0932 \u0928\u0939\u0940\u0902 \u0939\u0948, \u0907\u0938\u0932\u093F\u090F \u092F\u0939 \u092E\u0941\u0928\u093E\u092B\u093C\u093E \u0928\u0939\u0940\u0902 \u0939\u0948\u0964 \u0936\u0941\u0926\u094D\u0927 \u092E\u0941\u0928\u093E\u092B\u093C\u093E \u0926\u0947\u0916\u0928\u0947 \u0915\u0947 \u0932\u093F\u090F \u092A\u094D\u0930\u0924\u093F {unit} \u0905\u092A\u0928\u0940 \u0932\u093E\u0917\u0924 \u0932\u093F\u0916\u0947\u0902\u0964",
    "\u0C07\u0C26\u0C3F \u0C06\u0C26\u0C3E\u0C2F \u0C05\u0C02\u0C1A\u0C28\u0C3E (\u0C26\u0C3F\u0C17\u0C41\u0C2C\u0C21\u0C3F x \u0C27\u0C30). \u0C2E\u0C40 \u0C16\u0C30\u0C4D\u0C1A\u0C41\u0C32\u0C41 \u0C15\u0C32\u0C2A\u0C32\u0C47\u0C26\u0C41, \u0C15\u0C3E\u0C2C\u0C1F\u0C4D\u0C1F\u0C3F \u0C07\u0C26\u0C3F \u0C32\u0C3E\u0C2D\u0C02 \u0C15\u0C3E\u0C26\u0C41. \u0C28\u0C3F\u0C15\u0C30 \u0C32\u0C3E\u0C2D\u0C02 \u0C1A\u0C42\u0C21\u0C21\u0C3E\u0C28\u0C3F\u0C15\u0C3F {unit}\u0C15\u0C41 \u0C2E\u0C40 \u0C16\u0C30\u0C4D\u0C1A\u0C41 \u0C28\u0C2E\u0C4B\u0C26\u0C41 \u0C1A\u0C47\u0C2F\u0C02\u0C21\u0C3F.")
M["profit_net"] = tr3(
    "Net profit = expected income minus the cost you typed. Prices change every day, so check your local mandi before you decide.",
    "\u0936\u0941\u0926\u094D\u0927 \u092E\u0941\u0928\u093E\u092B\u093C\u093E = \u0905\u092A\u0947\u0915\u094D\u0937\u093F\u0924 \u0906\u092F - \u0906\u092A\u0915\u0940 \u0932\u093F\u0916\u0940 \u0932\u093E\u0917\u0924\u0964 \u092D\u093E\u0935 \u0930\u094B\u091C\u093C \u092C\u0926\u0932\u0924\u0947 \u0939\u0948\u0902, \u0907\u0938\u0932\u093F\u090F \u0928\u093F\u0930\u094D\u0923\u092F \u0938\u0947 \u092A\u0939\u0932\u0947 \u0905\u092A\u0928\u0940 \u0938\u094D\u0925\u093E\u0928\u0940\u092F \u092E\u0902\u0921\u0940 \u092E\u0947\u0902 \u091C\u093E\u0901\u091A\u0947\u0902\u0964",
    "\u0C28\u0C3F\u0C15\u0C30 \u0C32\u0C3E\u0C2D\u0C02 = \u0C05\u0C02\u0C1A\u0C28\u0C3E \u0C06\u0C26\u0C3E\u0C2F\u0C02 - \u0C2E\u0C40\u0C30\u0C41 \u0C28\u0C2E\u0C4B\u0C26\u0C41 \u0C1A\u0C47\u0C38\u0C3F\u0C28 \u0C16\u0C30\u0C4D\u0C1A\u0C41. \u0C27\u0C30\u0C32\u0C41 \u0C30\u0C4B\u0C1C\u0C42 \u0C2E\u0C3E\u0C30\u0C24\u0C3E\u0C2F\u0C3F, \u0C15\u0C3E\u0C2C\u0C1F\u0C4D\u0C1F\u0C3F \u0C28\u0C3F\u0C30\u0C4D\u0C23\u0C2F\u0C3F\u0C02\u0C1A\u0C47 \u0C2E\u0C41\u0C02\u0C26\u0C41 \u0C2E\u0C40 \u0C38\u0C4D\u0C25\u0C3E\u0C28\u0C3F\u0C15 \u0C2E\u0C02\u0C21\u0C3F\u0C32\u0C4B \u0C1A\u0C42\u0C21\u0C02\u0C21\u0C3F.")
M["profit_costmix"] = tr3(
    "Costs were typed for only some crops, so the list is ranked by income, not by net profit.",
    "\u0932\u093E\u0917\u0924 \u0915\u0947\u0935\u0932 \u0915\u0941\u091B \u092B\u0938\u0932\u094B\u0902 \u0915\u0947 \u0932\u093F\u090F \u0932\u093F\u0916\u0940 \u0917\u0908 \u0939\u0948, \u0907\u0938\u0932\u093F\u090F \u0938\u0942\u091A\u0940 \u0906\u092F \u0915\u0947 \u0905\u0928\u0941\u0938\u093E\u0930 \u0939\u0948, \u0936\u0941\u0926\u094D\u0927 \u092E\u0941\u0928\u093E\u092B\u093C\u0947 \u0915\u0947 \u0905\u0928\u0941\u0938\u093E\u0930 \u0928\u0939\u0940\u0902\u0964",
    "\u0C15\u0C4A\u0C28\u0C4D\u0C28\u0C3F \u0C2A\u0C02\u0C1F\u0C32\u0C15\u0C41 \u0C2E\u0C3E\u0C24\u0C4D\u0C30\u0C2E\u0C47 \u0C16\u0C30\u0C4D\u0C1A\u0C41 \u0C28\u0C2E\u0C4B\u0C26\u0C41 \u0C1A\u0C47\u0C36\u0C3E\u0C30\u0C41, \u0C15\u0C3E\u0C2C\u0C1F\u0C4D\u0C1F\u0C3F \u0C1C\u0C3E\u0C2C\u0C3F\u0C24\u0C3E \u0C06\u0C26\u0C3E\u0C2F\u0C02 \u0C2A\u0C4D\u0C30\u0C15\u0C3E\u0C30\u0C02 \u0C09\u0C02\u0C26\u0C3F, \u0C28\u0C3F\u0C15\u0C30 \u0C32\u0C3E\u0C2D\u0C02 \u0C2A\u0C4D\u0C30\u0C15\u0C3E\u0C30\u0C02 \u0C15\u0C3E\u0C26\u0C41.")
M["profit_long"] = tr3(
    "{crop} takes much longer than one season, so it cannot be compared directly with seasonal crops.",
    "{crop} \u090F\u0915 \u0938\u0940\u091C\u093C\u0928 \u0938\u0947 \u092C\u0939\u0941\u0924 \u0932\u0902\u092C\u0940 \u0905\u0935\u0927\u093F \u0915\u0940 \u092B\u0938\u0932 \u0939\u0948, \u0907\u0938\u0932\u093F\u090F \u0907\u0938\u0915\u0940 \u0938\u0940\u0927\u0940 \u0924\u0941\u0932\u0928\u093E \u092E\u094C\u0938\u092E\u0940 \u092B\u0938\u0932\u094B\u0902 \u0938\u0947 \u0928\u0939\u0940\u0902 \u0939\u094B \u0938\u0915\u0924\u0940\u0964",
    "{crop} \u0C12\u0C15 \u0C38\u0C40\u0C1C\u0C28\u0C4D \u0C15\u0C02\u0C1F\u0C47 \u0C1A\u0C3E\u0C32\u0C3E \u0C0E\u0C15\u0C4D\u0C15\u0C41\u0C35 \u0C15\u0C3E\u0C32\u0C02 \u0C2A\u0C02\u0C1F, \u0C15\u0C3E\u0C2C\u0C1F\u0C4D\u0C1F\u0C3F \u0C38\u0C40\u0C1C\u0C28\u0C4D \u0C2A\u0C02\u0C1F\u0C32\u0C24\u0C4B \u0C28\u0C47\u0C30\u0C41\u0C17\u0C3E \u0C2A\u0C4B\u0C32\u0C4D\u0C1A\u0C32\u0C47\u0C2E\u0C41.")
M["profit_noprice"] = tr3(
    "No price found for {crop}. Type today's mandi price (Rs per quintal) to include it in the ranking.",
    "{crop} \u0915\u093E \u092D\u093E\u0935 \u0928\u0939\u0940\u0902 \u092E\u093F\u0932\u093E\u0964 \u0907\u0938\u0947 \u0938\u0942\u091A\u0940 \u092E\u0947\u0902 \u091C\u094B\u0921\u093C\u0928\u0947 \u0915\u0947 \u0932\u093F\u090F \u0906\u091C \u0915\u093E \u092E\u0902\u0921\u0940 \u092D\u093E\u0935 (\u20B9 \u092A\u094D\u0930\u0924\u093F \u0915\u094D\u0935\u093F\u0902\u091F\u0932) \u0932\u093F\u0916\u0947\u0902\u0964",
    "{crop} \u0C27\u0C30 \u0C26\u0C4A\u0C30\u0C15\u0C32\u0C47\u0C26\u0C41. \u0C30\u0C4D\u0C2F\u0C3E\u0C02\u0C15\u0C3F\u0C02\u0C17\u0C4D\u200C\u0C32\u0C4B \u0C1A\u0C47\u0C30\u0C4D\u0C1A\u0C21\u0C3E\u0C28\u0C3F\u0C15\u0C3F \u0C08 \u0C30\u0C4B\u0C1C\u0C41 \u0C2E\u0C02\u0C21\u0C3F \u0C27\u0C30 (\u0C15\u0C4D\u0C35\u0C3F\u0C02\u0C1F\u0C3E\u0C32\u0C41\u0C15\u0C41 \u20B9) \u0C28\u0C2E\u0C4B\u0C26\u0C41 \u0C1A\u0C47\u0C2F\u0C02\u0C21\u0C3F.")
M["profit_cotton"] = tr3(
    "Cotton is not included: government records give cotton in bales, which the yield model cannot use.",
    "\u0915\u092A\u093E\u0938 \u0936\u093E\u092E\u093F\u0932 \u0928\u0939\u0940\u0902 \u0939\u0948: \u0938\u0930\u0915\u093E\u0930\u0940 \u0930\u093F\u0915\u0949\u0930\u094D\u0921 \u092E\u0947\u0902 \u0915\u092A\u093E\u0938 \u0917\u093E\u0901\u0920\u094B\u0902 \u092E\u0947\u0902 \u0939\u0948, \u091C\u093F\u0938\u0947 \u0909\u092A\u091C \u092E\u0949\u0921\u0932 \u0907\u0938\u094D\u0924\u0947\u092E\u093E\u0932 \u0928\u0939\u0940\u0902 \u0915\u0930 \u0938\u0915\u0924\u093E\u0964",
    "\u0C2A\u0C24\u0C4D\u0C24\u0C3F \u0C1A\u0C47\u0C30\u0C4D\u0C1A\u0C32\u0C47\u0C26\u0C41: \u0C2A\u0C4D\u0C30\u0C2D\u0C41\u0C24\u0C4D\u0C35 \u0C30\u0C3F\u0C15\u0C3E\u0C30\u0C4D\u0C21\u0C41\u0C32\u0C4D\u0C32\u0C4B \u0C2A\u0C24\u0C4D\u0C24\u0C3F \u0C2C\u0C47\u0C33\u0C4D\u0C32\u0C32\u0C4B \u0C09\u0C02\u0C26\u0C3F, \u0C26\u0C40\u0C28\u0C4D\u0C28\u0C3F \u0C26\u0C3F\u0C17\u0C41\u0C2C\u0C21\u0C3F \u0C2E\u0C4B\u0C21\u0C32\u0C4D \u0C35\u0C3E\u0C21\u0C32\u0C47\u0C26\u0C41.")
M["profit_olddata"] = tr3(
    "Yields come from government records up to {year}. Newer varieties and better farming can give more, so real yields may be higher.",
    "\u0909\u092A\u091C {year} \u0924\u0915 \u0915\u0947 \u0938\u0930\u0915\u093E\u0930\u0940 \u0930\u093F\u0915\u0949\u0930\u094D\u0921 \u0938\u0947 \u0939\u0948\u0964 \u0928\u0908 \u0915\u093F\u0938\u094D\u092E\u0947\u0902 \u0914\u0930 \u092C\u0947\u0939\u0924\u0930 \u0916\u0947\u0924\u0940 \u0938\u0947 \u091C\u093C\u094D\u092F\u093E\u0926\u093E \u0909\u092A\u091C \u092E\u093F\u0932 \u0938\u0915\u0924\u0940 \u0939\u0948, \u0907\u0938\u0932\u093F\u090F \u0905\u0938\u0932\u0940 \u0909\u092A\u091C \u0905\u0927\u093F\u0915 \u0939\u094B \u0938\u0915\u0924\u0940 \u0939\u0948\u0964",
    "\u0C26\u0C3F\u0C17\u0C41\u0C2C\u0C21\u0C41\u0C32\u0C41 {year} \u0C35\u0C30\u0C15\u0C41 \u0C09\u0C28\u0C4D\u0C28 \u0C2A\u0C4D\u0C30\u0C2D\u0C41\u0C24\u0C4D\u0C35 \u0C30\u0C3F\u0C15\u0C3E\u0C30\u0C4D\u0C21\u0C41\u0C32 \u0C28\u0C41\u0C02\u0C21\u0C3F. \u0C15\u0C4A\u0C24\u0C4D\u0C24 \u0C30\u0C15\u0C3E\u0C32\u0C41, \u0C2E\u0C46\u0C30\u0C41\u0C17\u0C48\u0C28 \u0C38\u0C3E\u0C17\u0C41\u0C24\u0C4B \u0C0E\u0C15\u0C4D\u0C15\u0C41\u0C35 \u0C30\u0C3E\u0C35\u0C1A\u0C4D\u0C1A\u0C41, \u0C15\u0C3E\u0C2C\u0C1F\u0C4D\u0C1F\u0C3F \u0C28\u0C3F\u0C1C\u0C2E\u0C48\u0C28 \u0C26\u0C3F\u0C17\u0C41\u0C2C\u0C21\u0C3F \u0C0E\u0C15\u0C4D\u0C15\u0C41\u0C35 \u0C09\u0C02\u0C21\u0C35\u0C1A\u0C4D\u0C1A\u0C41.")
M["unit_acre"] = tr3("acre", "\u090F\u0915\u0921\u093C", "\u0C0E\u0C15\u0C30\u0C3E")
M["unit_hectare"] = tr3("hectare", "\u0939\u0947\u0915\u094D\u091F\u0947\u092F\u0930", "\u0C39\u0C46\u0C15\u0C4D\u0C1F\u0C3E\u0C30\u0C41")
M["sum_profit"] = tr3("Profit comparison: best income {crop}", "\u092E\u0941\u0928\u093E\u092B\u093C\u093E \u0924\u0941\u0932\u0928\u093E: \u0938\u092C\u0938\u0947 \u0905\u0927\u093F\u0915 \u0906\u092F {crop}", "\u0C32\u0C3E\u0C2D\u0C02 \u0C2A\u0C4B\u0C32\u0C3F\u0C15: \u0C0E\u0C15\u0C4D\u0C15\u0C41\u0C35 \u0C06\u0C26\u0C3E\u0C2F\u0C02 {crop}")


def _known_crops() -> set[str]:
    b = registry.yield_model()
    return set((b or {}).get("known_values", {}).get("crop", []))


def addable_crops() -> list[str]:
    known = _known_crops()
    return sorted(c for c in prices.priced_crops() if c in known)


def candidates(state: str, district: str | None, season: str | None, limit: int = 8) -> list[str]:
    """Priced crops that the government data shows are really grown in this district/state and season."""
    rows = soil_service._prod()
    rows = rows[rows.State_Name.str.lower() == state.strip().lower()]
    if district:
        dd = rows[rows.District_Name.str.lower() == district.strip().lower()]
        if not dd.empty:
            rows = dd
    if season:
        ss = rows[rows.Season.str.lower().isin([season.strip().lower(), "whole year"])]
        if not ss.empty:
            rows = ss
    top = rows.groupby("Crop").Area.sum().sort_values(ascending=False)
    ok = set(addable_crops()) - {"Sugarcane"}
    out = [c for c in top.index if c in ok]
    return out[:limit]


def compare(inp: dict) -> dict:
    lang = norm(inp.get("lang"))
    unit = "hectare" if inp.get("area_unit") == "hectare" else "acre"
    area = float(inp["area"])
    area_ha = area if unit == "hectare" else area / ACRE_PER_HA
    state, district, season = inp["state"], inp.get("district"), inp["season"]
    typed = {k: float(v) for k, v in (inp.get("prices") or {}).items() if v not in (None, "") and float(v) > 0}
    crops = inp.get("crops")
    if not crops:  # auto list + any crop the farmer typed a price for
        crops = list(dict.fromkeys(candidates(state, district, season) + [c for c in typed if c in _known_crops()]))
    costs = {k: float(v) for k, v in (inp.get("costs") or {}).items() if v not in (None, "") and float(v) >= 0}
    if not crops:
        return {"model_status": "trained", "rows": [], "notes": [], "error": "no_crops"}
    rows, notes = [], []
    for crop in crops:
        r = yield_service.predict({"state": state, "district": district, "season": season, "crop": crop,
                                   "area_hectares": area_ha, "lang": lang})
        if r.get("model_status") == "unavailable":
            return r
        row = {"crop": crop, "long_duration": crop in LONG_CROPS}
        if "error" in r:
            row["error"] = r["error"]
            rows.append(row)
            continue
        y = r["predicted_yield"]
        row.update(yield_t_per_ha=y, production_tonnes=round(y * area_ha, 2),
                   production_quintals=round(y * area_ha * 10, 1), warnings=r.get("warnings", []))
        price, src, live = None, None, None
        if crop in typed:
            price, src = typed[crop], "typed"
        else:
            live = prices.latest_price(crop, state, district)
            if live:
                price, src = live["price"], "live"
        row.update(price=price, price_source=src, live=live)
        if price:
            row["income"] = round(row["production_quintals"] * price)
            row["income_per_unit"] = round(row["income"] / area)
        if crop in costs:  # cost is typed per acre/hectare, as the farmer chose
            row["cost"] = round(costs[crop] * area)
            if price:
                row["net"] = row["income"] - row["cost"]
        rows.append(row)

    priced = [r for r in rows if r.get("income") is not None]
    all_cost = bool(priced) and all("net" in r for r in priced)
    key = "net" if all_cost else "income"
    priced.sort(key=lambda r: r[key], reverse=True)
    unpriced = [r for r in rows if r.get("income") is None]
    ordered = priced + unpriced
    for i, r in enumerate(priced):
        r["rank"] = i + 1

    if all_cost:
        notes.append(t("profit_net", lang))
    else:
        notes.append(t("profit_estimate", lang, unit=t("unit_" + unit, lang)))
        if any("net" in r for r in priced):
            notes.append(t("profit_costmix", lang))
    for r in ordered:
        if r.get("long_duration"):
            notes.append(t("profit_long", lang, crop=r["crop"]))
        if r.get("income") is None and "error" not in r:
            notes.append(t("profit_noprice", lang, crop=r["crop"]))
    notes.append(t("profit_cotton", lang))
    notes.append(t("profit_olddata", lang, year=DATA_LAST_YEAR))
    return {"model_status": "trained", "rows": ordered, "ranked_by": key if priced else None,
            "best": priced[0]["crop"] if priced else None, "area": area, "area_unit": unit,
            "area_ha": round(area_ha, 3), "live_prices_enabled": prices.has_key(),
            "notes": list(dict.fromkeys(notes)), "disclaimer": t("yield_disclaimer", lang)}
