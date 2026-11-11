# Bankroll Tracker

Local Android poker bankroll tracker in Flutter. German is the initial locale. No account, backend or network connection is needed for local workflows.

The app includes Home, seven Bankroll tabs, five entry types (cash games, tournaments, deposits, withdrawals and staking), manual session editing, rolling monthly/yearly reports, original-style Trend controls and filters, opening-balance/location/game maintenance, recoverable live sessions and local settings. Login and cloud sync are explicitly unavailable. Benchmark and hands/hour inputs are removed; the normal UX uses one bankroll. Import/export and migration are the final 1.0 milestone, after the owner reviews the core app against the reference.

```sh
/home/erik/.local/share/flutter/bin/flutter --no-version-check pub get
/home/erik/.local/share/flutter/bin/flutter --no-version-check analyze
/home/erik/.local/share/flutter/bin/flutter --no-version-check test
JAVA_HOME=/home/erik/.local/share/android-studio/jbr \
  /home/erik/.local/share/flutter/bin/flutter --no-version-check build apk --debug
```

Use only the dedicated `felt_ledger_dev` emulator for development. Never target an attached physical phone. Private reference and validation documents are kept locally and excluded from this public repository.

See [GitHub releases and Obtainium setup](docs/DISTRIBUTION.md).
