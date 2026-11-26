import { useCallback, useEffect, useRef, useState } from "react";
import { api } from "../services/api.js";
import { PageHeader, Field, NumberInput, Alert, Spinner, List, Badge, SpeakButton } from "../components/ui.jsx";
import FeedbackBox from "../components/FeedbackBox.jsx";
import { useLang } from "../i18n/LanguageContext.jsx";
import { useSpeechText } from "../voice/VoiceContext.jsx";
import { useRelang } from "../i18n/useRelang.js";

const SEASON_KEY = { Kharif: "season.kharif", Rabi: "season.rabi", Summer: "season.summer", "Whole Year": "season.whole", Autumn: "season.autumn", Winter: "season.winter" };
const INIT = { state: "", district: "", season: "", area: "1", area_unit: "acre" };
const pretty = (s) => s.charAt(0) + s.slice(1).toLowerCase();
const RS = "\u20B9";
const money = (n) => (n === null || n === undefined ? "-" : RS + Number(n).toLocaleString("en-IN"));
const onlyNumbers = (obj) => Object.fromEntries(Object.entries(obj).filter(([, v]) => v !== "" && !Number.isNaN(Number(v))).map(([k, v]) => [k, Number(v)]));

export default function ProfitMode() {
  const { t } = useLang();
  const [v, setV] = useState(INIT);
  const [opts, setOpts] = useState({ crops: [], seasons: [], states: [], districts: {} });
  const [crops, setCrops] = useState([]);
  const [allCrops, setAllCrops] = useState([]);
  const [live, setLive] = useState(false);
  const [prices, setPrices] = useState({});
  const [costs, setCosts] = useState({});
  const [res, setRes] = useState(null);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const lastRun = useRef(null);
  const hid = useRef(null);
  if (res?.history_id) hid.current = res.history_id;

  useEffect(() => { api.yieldOptions().then(setOpts).catch((e) => setError(e.message)); }, []);
  // when state / district / season change, load the crops really grown there
  useEffect(() => {
    if (!v.state || !v.season) { setCrops([]); return; }
    api.profitOptions(v.state, v.district, v.season)
      .then((r) => { setCrops(r.candidates); setAllCrops(r.all_crops); setLive(r.live_prices_enabled); })
      .catch((e) => setError(e.message));
  }, [v.state, v.district, v.season]);

  const set = (k) => (val) => setV((p) => ({ ...p, [k]: val }));
  const districts = opts.districts[v.state] || [];
  const unitLabel = t(v.area_unit === "acre" ? "profit.acre" : "profit.hectare").toLowerCase();

  const reset = useCallback(() => { setV(INIT); setRes(null); setError(""); setPrices({}); setCosts({}); setCrops([]); hid.current = null; lastRun.current = null; }, []);
  useRelang(lastRun, setRes);

  function example() {
    const state = opts.states.includes("Telangana") ? "Telangana" : opts.states[0] || "";
    setV({ ...INIT, state, district: (opts.districts[state] || [])[0] || "", season: "Kharif", area: "2" });
  }

  async function run() {
    setBusy(true); setError(""); hid.current = null;
    const payload = { state: v.state, district: v.district || undefined, season: v.season, area: Number(v.area),
      area_unit: v.area_unit, crops, prices: onlyNumbers(prices), costs: onlyNumbers(costs) };
    lastRun.current = (re) => api.profitCompare({ ...payload, relocalize: !!re });
    try { setRes(await lastRun.current(false)); }
    catch (err) { setError(err.message); setRes(null); }
    finally { setBusy(false); }
  }
  const submit = (e) => { e.preventDefault(); run(); };

  const top = res?.rows?.find((r) => r.rank === 1);
  const speech = top ? t("profit.speak", { crop: top.crop, inc: top.income }) : "";
  useSpeechText(speech);

  return (
    <>
      <PageHeader icon={"\u{1F4B0}"} title={t("profit.title")} subtitle={t("profit.sub")} />
      <div className="container page two-col wide-left">
        <form className="card form" onSubmit={submit}>
          <h3>{t("profit.farm")}</h3>
          <div className="form-grid">
            <Field label={t("common.state")}>
              <select required value={v.state} onChange={(e) => setV((p) => ({ ...p, state: e.target.value, district: "" }))}>
                <option value="">{t("common.selectState")}</option>{opts.states.map((s) => <option key={s}>{s}</option>)}
              </select>
            </Field>
            <Field label={t("common.district")}>
              <select value={v.district} onChange={(e) => set("district")(e.target.value)} disabled={!v.state}>
                <option value="">{v.state ? t("common.selectDistrict") : t("common.selectStateFirst")}</option>
                {districts.map((d) => <option key={d} value={d}>{pretty(d)}</option>)}
              </select>
            </Field>
            <Field label={t("common.season")}>
              <select required value={v.season} onChange={(e) => set("season")(e.target.value)}>
                <option value="">{t("common.select")}</option>{opts.seasons.map((s) => <option key={s} value={s}>{SEASON_KEY[s] ? t(SEASON_KEY[s]) : s}</option>)}
              </select>
            </Field>
            <Field label={t("profit.area")}>
              <div className="inline-pair">
                <NumberInput required min={0.01} value={v.area} onChange={set("area")} />
                <select value={v.area_unit} onChange={(e) => set("area_unit")(e.target.value)}>
                  <option value="acre">{t("profit.acre")}</option><option value="hectare">{t("profit.hectare")}</option>
                </select>
              </div>
            </Field>
          </div>

          <h3>{t("profit.crops")}</h3>
          <p className="muted small">{t("profit.cropsHint")}</p>
          {crops.length === 0 && <p className="muted small">{t("profit.noCrops")}</p>}
          <div className="chips">
            {crops.map((c) => (
              <span className="chip" key={c}>{c}<button type="button" aria-label="remove" onClick={() => setCrops((p) => p.filter((x) => x !== c))}>{"\u00D7"}</button></span>
            ))}
          </div>
          <Field label={t("profit.addCrop")}>
            <select value="" onChange={(e) => e.target.value && setCrops((p) => (p.includes(e.target.value) ? p : [...p, e.target.value]))}>
              <option value="">{t("common.select")}</option>
              {allCrops.filter((c) => !crops.includes(c)).map((c) => <option key={c}>{c}</option>)}
            </select>
          </Field>

          <Alert kind="info">{live ? t("profit.liveOn") : t("profit.liveOff")}</Alert>
          <div className="btn-row">
            <button className="btn primary lg" disabled={busy || crops.length === 0}>{busy ? t("profit.working") : t("profit.btn")}</button>
            <button type="button" className="btn outline" onClick={example}>{t("common.example")}</button>
            <button type="button" className="btn outline" onClick={reset}>{t("common.reset")}</button>
          </div>
        </form>

        <div>
          {busy && <Spinner text={t("profit.working")} />}
          <Alert title={t("profit.couldNot")}>{error}</Alert>
          {!res && !busy && !error && <div className="card empty">{t("common.resultsHere")}</div>}
          {res && (
            <div className="results">
              {top && (
                <div className="card result big">
                  <div className="muted">{res.ranked_by === "net" ? t("profit.bestNet") : t("profit.best")}</div>
                  <div className="big-number">{top.crop}</div>
                  <p><b>{money(res.ranked_by === "net" ? top.net : top.income)}</b> {res.ranked_by !== "net" && <Badge tone="amber">{t("profit.estimateBadge")}</Badge>}</p>
                  <SpeakButton text={speech} />
                </div>
              )}
              <div className="card">
                <div className="table-wrap">
                  <table className="ptable">
                    <thead>
                      <tr>
                        <th>#</th><th>{t("profit.crop")}</th><th>{t("profit.yield")}</th><th>{t("profit.prod")}</th>
                        <th>{t("profit.price")}</th><th>{t("profit.cost", { unit: unitLabel })}</th><th>{t("profit.income")}</th><th>{t("profit.net")}</th>
                      </tr>
                    </thead>
                    <tbody>
                      {res.rows.map((r) => (
                        <tr key={r.crop} className={r.rank === 1 ? "top" : ""}>
                          <td>{r.rank || "-"}</td>
                          <td><b>{r.crop}</b>{r.error && <div className="small err">{r.error}</div>}</td>
                          <td>{r.yield_t_per_ha ?? "-"}</td>
                          <td>{r.production_quintals ?? "-"}</td>
                          <td>
                            <input className="cell" type="number" min="0" step="any" placeholder={t("profit.needPrice")}
                              value={prices[r.crop] ?? (r.price ?? "")} onChange={(e) => setPrices((p) => ({ ...p, [r.crop]: e.target.value }))} />
                            <div className="small muted">
                              {r.price_source === "typed" && t("profit.srcTyped")}
                              {r.price_source === "live" && r.live && t("profit.srcLive", { date: r.live.date })}
                            </div>
                          </td>
                          <td>
                            <input className="cell" type="number" min="0" step="any" value={costs[r.crop] ?? ""}
                              onChange={(e) => setCosts((p) => ({ ...p, [r.crop]: e.target.value }))} />
                          </td>
                          <td>{money(r.income)}</td>
                          <td>{money(r.net)}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
                <div className="btn-row mt-s"><button type="button" className="btn outline" disabled={busy} onClick={run}>{t("profit.recalc")}</button></div>
              </div>
              <div className="card">
                <h4>{t("profit.notesTitle")}</h4>
                <List items={res.notes} tone="warn" />
                <Alert kind="warn">{res.disclaimer}</Alert>
              </div>
              {hid.current && <FeedbackBox key={hid.current} module="profit_comparison" historyId={hid.current} kind="profit" />}
            </div>
          )}
        </div>
      </div>
    </>
  );
}
