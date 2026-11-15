# Local JSON imports (version 1)

Account → **JSON importieren / Importverlauf** opens Android's document picker.
Select a local `.json`, inspect the preview, acknowledge its limitations and
confirm saving. Canceling the picker or preview changes no app data.

Use UTF-8 JSON with `format: "bankroll-tracker-import"` and integer `version: 1`.
The public synthetic example is `examples/import-v1.json`. Files are limited to
16 MiB / 10,000 records. Money is a decimal **string** with a dot and up to four
fractional digits, never a floating-point JSON number. No currency conversion
is performed; the file must match the single destination bankroll's currency.

Top-level fields:

- `source`: stable `id` identifying the source database and human-readable `name`.
  Reuse this ID when creating overlapping captures of that same database.
- `currency`: EUR, USD, GBP or CHF.
- `coverage`: category names mapped to `mapped`, `preserved-only`, `missing`, or
  `empty-confirmed`. Missing facts must not be described as confirmed empty.
- `warnings`: readable descriptions of source limitations.
- `expected`: integer `count` and decimal-string `balanceEffect`. Both must
  reconcile with parsed records or the entire file is rejected.
- `records`: each has stable string `sourceId`, `kind`, `currency`, `date`
  (YYYY-MM-DD), decimal-string `result` and `money` object. Optional `note` and
  arbitrary additional source fields are retained.

Kinds and fields:

| Kind | Required fields |
| --- | --- |
| `deposit`, `withdrawal` | Positive `money.amount`; result sign must match direction |
| `staking` | `money.stakingBoughtCost`, `stakingBoughtReturn`, signed `stakingSettlement` |
| `cash_game`, `tournament` | `start`, `end` as local YYYY-MM-DDTHH:mm; integer `durationSeconds`; `tableSize`; `location` with `name`/`room`; `game` with `name`, `limit` (NL/PL/FL), decimal-string `smallBlind`/`bigBlind`; `money` with `buyIn`, `cashOut`, `rebuyCost`, `addonCost`, `bounty` |

Sessions optionally include integer `rebuys`, `placement`, `players`, `paidPlaces`.
Results must equal cash-out + bounty − buy-in − rebuy cost − add-on cost.
Add-on costs join additional purchase cost in current calculations while their
original separate amount is retained. Playing duration is stored independently
from the start/end interval; absent break events are never fabricated. Captured
clock times have local-minute precision, without asserting a source timezone.
Transfers have date precision. Unknown fields and all original source bytes are
preserved in the local migration archive. This format currently supports the
listed types, not arbitrary legacy entry types or binary attachment bundles.

## Duplicates and recovery

Source database ID + source record ID identify repeat imports. Same content is
skipped; changed content for an imported ID blocks the batch. Similar existing
entries (same date/type/currency/result) are shown for explicit review and never
silently merged. Existing records/settings/opening balance are not overwritten.
A stale preview is rejected if the destination changed before confirmation.

The batch, new definitions, original bytes/SHA-256 and pre-import snapshot commit
in one SQLite transaction. Import history supports source JSON export, complete
import-archive export, and rollback of unchanged imported entries. Rollback
refuses edited records and preserves unrelated later records and settings.

For conflicts, **Sicherungsstand wiederherstellen** separately previews entry
counts and requires confirmation: it replaces ALL current entries, definitions,
settings and live state with the pre-import snapshot. This deliberately removes
changes since that snapshot. It is distinct from ordinary batch rollback.
The exported import archive contains source bytes and snapshot data for recovery,
but importing that archive as a full replacement backup is not implemented.

## Converting an authorized UI capture

```sh
python3 scripts/convert_session_capture.py capture-records.json private-import.json \
  --source-id YOUR-STABLE-SOURCE-DATABASE-ID
```

This adapter maps the captured German display fields, validates distinct IDs and
financial reconciliation, and embeds the complete captured JSON. History events
and conflicting source notes remain available through **Importierter Quellbeleg /
Verlauf**; they are not interpreted as newly timestamped chart events. Screenshots
stay in the separate private evidence archive. Unexposed fees/bounties and
unknown tournament blinds use explicitly disclosed calculation placeholders.
This limited capture import is not a claim of full source-app migration.

Never commit personal captures or import files, and never put them in Flutter
assets. Existing private captures under `docs/` are ignored by Git. Full backup
restore, CSV support, additional source formats and complete migration coverage
remain outstanding work for version 1.0.
