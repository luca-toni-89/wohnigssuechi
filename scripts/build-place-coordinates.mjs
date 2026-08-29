import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";

const input = process.argv[2];
const output = process.argv[3] || resolve("place-coordinates.json");
const includedCantons = new Set((process.argv[4] || "AG,ZH").split(",").map(value => value.trim().toUpperCase()).filter(Boolean));

if (!input) {
  throw new Error("Usage: node scripts/build-place-coordinates.mjs <AMTOVZ_CSV_WGS84.csv> [output]");
}

const slug = (value) => String(value || "")
  .toLowerCase()
  .normalize("NFD")
  .replace(/[\u0300-\u036f]/g, "")
  .replace(/[^a-z0-9]+/g, "-")
  .replace(/^-|-$/g, "");

const rows = readFileSync(input, "utf8").replace(/^\uFEFF/, "").trim().split(/\r?\n/);
const headers = rows.shift().split(";");
const column = Object.fromEntries(headers.map((header, index) => [header, index]));
const groups = { by_zip_city: new Map(), by_city: new Map(), by_zip: new Map() };

function add(group, key, latitude, longitude) {
  if (!key || !Number.isFinite(latitude) || !Number.isFinite(longitude)) return;
  const current = group.get(key) || { latitude: 0, longitude: 0, count: 0 };
  current.latitude += latitude;
  current.longitude += longitude;
  current.count += 1;
  group.set(key, current);
}

for (const line of rows) {
  const values = line.split(";");
  const locality = values[column["Ortschaftsname"]];
  const municipality = values[column["Gemeindename"]];
  const zip = values[column.PLZ4];
  const canton = values[column["Kantonskürzel"]]?.toUpperCase();
  const longitude = Number(values[column.E]);
  const latitude = Number(values[column.N]);
  if (includedCantons.size && !includedCantons.has(canton)) continue;
  const localityKey = slug(locality);
  const municipalityKey = slug(municipality);

  add(groups.by_zip_city, `${zip}|${localityKey}`, latitude, longitude);
  add(groups.by_zip_city, `${zip}|${municipalityKey}`, latitude, longitude);
  add(groups.by_city, localityKey, latitude, longitude);
  add(groups.by_city, municipalityKey, latitude, longitude);
  add(groups.by_zip, zip, latitude, longitude);
}

function serialize(group) {
  return Object.fromEntries([...group.entries()]
    .sort(([a], [b]) => a.localeCompare(b, "de-CH"))
    .map(([key, value]) => [key, [
      Number((value.latitude / value.count).toFixed(6)),
      Number((value.longitude / value.count).toFixed(6))
    ]]));
}

const payload = {
  schema_version: 1,
  generated_at: new Date().toISOString(),
  source: "https://data.geo.admin.ch/ch.swisstopo-vd.ortschaftenverzeichnis_plz/",
  source_note: "Amtliches Ortschaftenverzeichnis mit Postleitzahl und Perimeter, WGS84, Stand 2026-08-11",
  included_cantons: [...includedCantons].sort(),
  by_zip_city: serialize(groups.by_zip_city),
  by_city: serialize(groups.by_city),
  by_zip: serialize(groups.by_zip)
};

writeFileSync(output, `${JSON.stringify(payload)}\n`);
console.log(`Wrote ${output}: ${Object.keys(payload.by_city).length} places, ${Object.keys(payload.by_zip).length} ZIP codes.`);
