# ADR 0004 — Daily activity contributes to training pressure

The training ring includes ordinary walking as well as exercise. Its 0–21 number is a product estimate, not a clinical stress measurement. All calculations stay in Postgres; the app displays the published result.

`nb.activity_ticks` is the single contribution stream for the total, cumulative curve and source breakdown. Each recorded five-minute tick contributes the greater of the existing heart-rate-zone load and movement load. Taking the greater signal avoids counting the same activity twice. Missing personal resting heart rate disables heart-rate zones, but does not discard recorded steps or MET. Missing observations stay missing; an observed zero step count can produce zero movement.

Movement uses the recorded MET when present. Otherwise steps provide an explicitly approximate walking intensity: 500 steps in five minutes corresponds to 3 MET, with the estimate capped at 5 MET. The fallback assumes walking cadence and is not a vendor measurement. Movement contributes `0.375 × max(MET − 1, 0)` raw points per five minutes. This matches the existing zone-1 contribution at 3 MET and gives stronger heart-rate exercise zones greater emphasis. These product coefficients need future calibration against observed activity; they are not claimed to be clinically validated.

Daytime HRV does not multiply accumulated physical work. HRV depends on acquisition conditions and movement artifacts; the existing night-HRV → night inputs → Body Battery → suggested target path is retained. Reference: [HRV standardisation checklist](https://pmc.ncbi.nlm.nih.gov/articles/PMC7082649/). MET definition and activity context: [2024 Compendium of Physical Activities](https://pacompendium.com/).

Energy uses net MET above resting, body weight and recorded duration. Vendor calories are not added to calculated basal energy because their basal component is not separable. The UI identifies movement calories as estimates. Missing movement observations or required body measurements remain null. Basal and active components are rounded separately, and their exact sum is the total displayed.

A day prefers the latest weight before local 04:00. If none exists, the first weight recorded during that day becomes available once received. Future measurements never fill earlier days. All calculations use the effective profile and calculation instant, preserving replay behavior. Existing published days are invalidated when the migration installs so the next sync recomputes them.
