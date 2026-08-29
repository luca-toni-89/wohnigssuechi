# Euses Dihei

Gemeinsame Wohnungssuche für Gessi und Luca mit zwei exklusiven Kategorien:

- **MaxMio:** Gesamtpreis inklusive obligatorischem Parkplatz bis und mit CHF 1'000'000; Wohnungen ab 3.5 Zimmern.
- **HomeDeluxe:** Gesamtpreis inklusive obligatorischem Parkplatz über CHF 1'000'000; Wohnungen ab 4.5 Zimmern.

Ein Datensatz kann nur eine Kategorie besitzen. Bei bekanntem Gesamtpreis wird die Kategorie sowohl im Browser als auch in Supabase automatisch berechnet. Genau CHF 1'000'000 gehört zu MaxMio.

## Dateien

- `index.html`: komplette responsive Website
- `data.json`: einziger Feed für neue und aktualisierte Treffer
- `supabase-migration.sql`: erstellt die gemeinsamen Tabellen und übernimmt die bisherigen Daten

## Datenfluss

1. Die Suchtasks aktualisieren ausschließlich `data.json`.
2. Die Website liest den Feed und synchronisiert neue Einträge nach Supabase.
3. Supabase bewahrt Wohnungen, Status, Favoriten, Bewertungen und Notizen dauerhaft auf.
4. Cloudflare Pages veröffentlicht jede Änderung am GitHub-Branch `main` automatisch.

## JSON-Grundformat

```json
{
  "schema_version": 1,
  "generated_at": "2026-08-29T10:00:00Z",
  "properties": [
    {
      "external_id": "source-12345",
      "entry_type": "listing",
      "source": "Homegate",
      "source_url": "https://example.com/direktes-inserat",
      "title": "Helle 4.5-Zimmer-Wohnung",
      "address": "Beispielstrasse 1",
      "zip": "8304",
      "city": "Wallisellen",
      "canton": "ZH",
      "rooms": 4.5,
      "living_area_m2": 118,
      "purchase_price_chf": 965000,
      "mandatory_parking_price_chf": 35000,
      "total_price_chf": 1000000,
      "year_built": 2021,
      "drive_minutes_duebendorf": 12,
      "drive_minutes_wohlen": 39,
      "drive_minutes_othmarsingen": 31,
      "ai_rating": 8.7,
      "ai_recommendation_reason": "Sehr stimmiges Gesamtpaket.",
      "advantages": ["Gute Lage", "Moderner Ausbau"],
      "disadvantages": ["Nur ein Parkplatz"],
      "discovered_at": "2026-08-29T10:00:00Z"
    }
  ],
  "pipeline_projects": []
}
```

Pipeline-Projekte dürfen vorläufig noch unter `pipeline_projects` geliefert werden. Die Website wandelt sie automatisch in normale Wohnungskarten mit `entry_type: "pipeline"` um. Für künftige Updates ist die Ablage direkt in `properties` mit `entry_type: "pipeline"` bevorzugt.
