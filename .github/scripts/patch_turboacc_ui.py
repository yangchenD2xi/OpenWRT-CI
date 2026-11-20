#!/usr/bin/env python3
"""Safely modernize only TurboACC's LuCI status presentation.

Run from the OpenWrt source root AFTER feeds install and package sources exist.
Never changes init, firewall, NSS, RPC, UCI, or package dependencies.
Targets the legacy LuCI view (compatible with the lede reference in
mufeng05/turboacc). Stops on an unfamiliar page rather than guessing.
"""
from pathlib import Path
import sys

TARGET = Path('htdocs/luci-static/resources/view/turboacc.js')
root = Path.cwd()
found = sorted({p for base in [root / 'package', root / 'feeds'] if base.exists()
               for p in base.rglob(str(TARGET)) if 'luci-app-turboacc' in p.parts})
if len(found) != 1:
    print(f'ERROR: expected exactly one TurboACC LuCI page; found {len(found)}:', file=sys.stderr)
    for p in found:
        print(f'  {p.relative_to(root)}', file=sys.stderr)
    print('Remove duplicate TurboACC package definitions or adjust the build feeds.', file=sys.stderr)
    sys.exit(1)
p = found[0]
s = p.read_text(encoding='utf-8')
marker = '/* YangChen TurboACC status cards: UI-only */'
if marker in s:
    print(f'Already patched: {p.relative_to(root)}')
    sys.exit(0)

start = "\t\t\treturn E('fieldset', { 'class': 'cbi-section' }, ["
end = "\n\t\t}\n\n\t\ts = m.section(form.NamedSection, 'config', 'turboacc');"
i = s.find(start)
j = s.find(end, i)
if i < 0 or j < 0 or 'getServiceStatus()' not in s or "var tds = [ 'fastpath_state', 'fullcone_state', 'tcpcca_state' ];" not in s:
    print(f'ERROR: upstream TurboACC UI has changed; refusing unsafe patch: {p}', file=sys.stderr)
    sys.exit(2)

replacement = '''\t\t\t/* YangChen TurboACC status cards: UI-only */
\t\t\tvar cardStyle = 'flex:1 1 190px;min-width:160px;padding:14px 18px;border:1px solid var(--cbi-border-color,#d7dce2);border-radius:10px;background:var(--cbi-section-bg,#fff)';
\t\t\tvar labelStyle = 'display:block;opacity:.72;font-size:.86em;margin-bottom:8px';
\t\t\tvar valueStyle = 'display:block;font-size:1.05em;font-weight:600;line-height:1.5';
\t\t\tfunction statusCard(label, id) {
\t\t\t\treturn E('div', { 'style': cardStyle }, [
\t\t\t\t\tE('span', { 'style': labelStyle }, label),
\t\t\t\t\tE('div', { 'id': id, 'style': valueStyle }, E('em', {}, _('Collecting data...')))
\t\t\t\t]);
\t\t\t}
\t\t\treturn E('fieldset', { 'class': 'cbi-section' }, [
\t\t\t\tE('legend', {}, _('Acceleration Status')),
\t\t\t\tE('div', { 'style': 'display:flex;flex-wrap:wrap;gap:12px;margin:10px 0' }, [
\t\t\t\t\tstatusCard(_('FastPath Engine'), 'fastpath_state'),
\t\t\t\t\tstatusCard(_('Full Cone NAT'), 'fullcone_state'),
\t\t\t\t\tstatusCard(_('TCP CCA'), 'tcpcca_state')
\t\t\t\t])
\t\t\t]);'''
s = s[:i] + replacement + s[j:]
p.write_text(s, encoding='utf-8')
print(f'Success: patched LuCI status cards only: {p.relative_to(root)}')
print('Existing backend, NSS integration, config keys, and options untouched.')
