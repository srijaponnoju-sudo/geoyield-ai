import { STATES, DISTRICTS } from "../data/locations.js";
import { useLang } from "../i18n/LanguageContext.jsx";
import { Field } from "./ui.jsx";

/** State + District + Village. District is a dropdown when we have its list, otherwise a text box. */
export default function LocationFields({ value, onChange }) {
  const { t } = useLang();
  const list = DISTRICTS[value.state];
  return (
    <>
      <Field label={t("common.state")}>
        <select value={value.state} onChange={(e) => onChange({ ...value, state: e.target.value, district: "" })}>
          <option value="">{t("common.selectState")}</option>
          {STATES.map((s) => <option key={s}>{s}</option>)}
        </select>
      </Field>
      <Field label={t("common.district")} hint={!list && value.state ? t("common.districtListNote") : undefined}>
        {list ? (
          <select value={value.district} onChange={(e) => onChange({ ...value, district: e.target.value })}>
            <option value="">{t("common.selectDistrict")}</option>
            {list.map((d) => <option key={d}>{d}</option>)}
          </select>
        ) : (
          <input value={value.district} disabled={!value.state}
            placeholder={value.state ? t("common.typeDistrict") : t("common.selectStateFirst")}
            onChange={(e) => onChange({ ...value, district: e.target.value })} />
        )}
      </Field>
      <Field label={t("common.village")}>
        <input value={value.village} onChange={(e) => onChange({ ...value, village: e.target.value })} />
      </Field>
    </>
  );
}
