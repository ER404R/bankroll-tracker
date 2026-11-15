#!/usr/bin/env python3
"""Convert an authorized UI capture into the versioned local import format.

No personal data is bundled in this script. Keep output in a private location.
Use the same --source-id for subsequent captures of the same source database.
"""
import argparse
from datetime import date, datetime, timedelta
from decimal import Decimal
import hashlib
import json
from pathlib import Path
import re


def money(text):
    value = Decimal(text.replace('€', '').replace('.', '').replace(',', '.'))
    if not value.is_finite() or value.as_tuple().exponent < -4:
        raise ValueError('Invalid or unsupported monetary precision')
    return format(value, 'f')


def convert(capture, source_id, source_bytes):
    records = []
    seen = set()
    for raw in capture['records']:
        sid = str(raw['source_local_id'])
        if sid in seen:
            raise ValueError(f'Duplicate source ID: {sid}')
        seen.add(sid)
        h, f = raw['header'], raw['fields_display']
        d = date.fromisoformat(raw['date_iso'])
        kind = h['kind']
        if kind not in ('cash_game', 'tournament', 'deposit', 'withdrawal'):
            raise ValueError(f'Unsupported source type {kind}')
        r = dict(sourceId=sid, kind=kind, currency='EUR', date=d.isoformat(),
                 result=str(Decimal(raw['result_decimal'])),
                 note='\n'.join(raw['notes_display']), sourceRecord=raw)
        if kind in ('deposit', 'withdrawal'):
            r['money'] = {'amount': str(abs(Decimal(raw['result_decimal'])))}
        else:
            if f['WÄHRUNG'] != 'EUR':
                raise ValueError('This capture adapter requires EUR; no automatic currency conversion')
            start = datetime.fromisoformat(f"{d.isoformat()}T{f['START']}")
            end_date = d + timedelta(days=1 if 'ENDE (+1)' in f else 0)
            end = datetime.fromisoformat(f"{end_date.isoformat()}T{f.get('ENDE (+1)', f.get('ENDE'))}")
            if end < start:
                raise ValueError(f'End before start for {sid}')
            hours, minutes = map(int, f['DAUER'].split(':'))
            r.update(start=start.isoformat(timespec='minutes'), end=end.isoformat(timespec='minutes'),
                     durationSeconds=hours*3600+minutes*60,
                     tableSize=f['TISCHGRÖSSE'],
                     location={'name': h['location'], 'room': f['ART']})
            if kind == 'cash_game':
                m = re.fullmatch(r'€([\d.,]+)/([\d.,]+) (NL|PL|FL) (.+)', h['title'])
                if not m:
                    raise ValueError(f'Unrecognized stakes/game for {sid}')
                sb, bb, limit, game = money(m[1]), money(m[2]), m[3], m[4]
            else:
                m = re.fullmatch(r'€[\d.,]+ (NL|PL|FL) (.+)', h['title'])
                if not m:
                    raise ValueError(f'Unrecognized tournament title for {sid}')
                sb, bb, limit, game = '0', '0', m[1], m[2]
            r['game'] = dict(name=game, limit=limit, smallBlind=sb, bigBlind=bb)
            r['money'] = {dest: money(f.get(src, '€0')) for dest, src in (
                ('buyIn', 'BUY-IN'), ('cashOut', 'CASH-OUT'), ('rebuyCost', 'REBUY KOSTEN'),
                ('addonCost', 'ADD-ON'), ('bounty', 'BOUNTIES'))}
            for dest, src in [('rebuys', 'REBUYS'), ('placement', 'PLATZ'), ('players', 'ENTRIES'), ('paidPlaces', 'ITM')]:
                if src in f:
                    r[dest] = int(f[src])
            m = {k: Decimal(v) for k, v in r['money'].items()}
            if m['cashOut']+m['bounty']-m['buyIn']-m['rebuyCost']-m['addonCost'] != Decimal(r['result']):
                raise ValueError(f'Result does not reconcile for {sid}')
        records.append(r)
    return dict(format='bankroll-tracker-import', version=1,
                source={'id': source_id, 'name': 'Poker Bankroll Tracker · Bildschirm-Erfassung'},
                currency='EUR', coverage={
                    'Sessions und Transfers': 'mapped',
                    'Notizen': 'mapped',
                    'Ereignisverlauf und weitere Quellfelder': 'preserved-only',
                    'Exakte Sekunden, Zeitzone, Pausen und verborgene Präzision': 'missing',
                    'Einstellungen, Anhänge und weitere App-Bereiche': 'missing',
                }, warnings=[
                    'Bildschirm-Erfassung, kein vollständiger Datenbankexport. Geldbeträge haben nur die angezeigte Genauigkeit.',
                    'Zeitangaben bleiben lokale Uhrzeiten ohne bestätigte Zeitzone. Spieldauer wird separat übernommen; es werden keine Pausen erfunden.',
                    'Nicht angezeigte Zusatzkosten und Bounties werden für die abgeglichenen Ergebnisse mit 0 gerechnet; ihre Abwesenheit ist nicht bestätigt.',
                    'Turnier-Blinds sind unbekannt. 0 dient ausschließlich als technischer Platzhalter; ursprüngliche Angaben bleiben erhalten.',
                    'Ereignisse, Startstack und widersprüchliche Notizen bleiben im einsehbaren Quellbeleg erhalten. Sie werden nicht in neue Chartpunkte umgedeutet.',
                    'Screenshots bleiben im separaten privaten Belegarchiv und sind nicht in dieser Datei enthalten.',
                ], expected={'count': len(records), 'balanceEffect': str(sum((Decimal(r['result']) for r in records), Decimal(0)))},
                records=records,
                captureArchive={'sha256': hashlib.sha256(source_bytes).hexdigest(), 'original': capture})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--source-id', required=True)
    args = parser.parse_args()
    source = args.input.read_bytes()
    result = convert(json.loads(source), args.source_id, source)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n')
    print(f"Converted {len(result['records'])} distinct records; reconciliation passed.")

if __name__ == '__main__':
    main()
