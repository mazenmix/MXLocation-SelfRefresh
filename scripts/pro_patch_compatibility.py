#!/usr/bin/env python3
"""Adapt MXPro R5 overlay injection to the compact custom RootView currently used by MX Location.
Runs against a disposable unpacked overlay, never against a shipped binary or main branch.
"""
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8")
start = s.index("view = root_view.read_text(encoding='utf-8')")
new = """view = root_view.read_text(encoding='utf-8')
# MX Location v1.4.2 uses switch-selectedTab and a custom compactTabBar instead of a TabView.
old = '            case 2:\\n                SettingsView()'
new = '''            case 2:
                MXProDiscoveryDashboardView()
            case 3:
                MXPlaceExplorerView()
            case 4:
                SettingsView()'''
if view.count(old) != 1:
    raise RuntimeError('Cannot uniquely locate Settings case in compact root; refusing unsafe injection')
view = view.replace(old, new, 1)
old_tab = '            compactTabButton(title: "Settings", systemImage: "gearshape.fill", tag: 2)'
new_tab = '''            compactTabButton(title: "Discover", systemImage: "sparkles", tag: 2)
            compactTabButton(title: "Places", systemImage: "mappin.and.ellipse", tag: 3)
            compactTabButton(title: "Settings", systemImage: "gearshape.fill", tag: 4)'''
if view.count(old_tab) != 1:
    raise RuntimeError('Cannot uniquely locate compact Settings tab; refusing unsafe injection')
view = view.replace(old_tab, new_tab, 1)
root_view.write_text(view, encoding='utf-8')
files = sorted(source_dir.glob('*.swift'))
assert len(files) >= 8, 'Missing expected Pro feature modules'
for source in files:
    (target_dir / source.name).write_text(source.read_text(encoding='utf-8'), encoding='utf-8')
print(f'MX Location Pro GPS First: installed {len(files)} Swift modules; GPS tab still index zero')
"""
p.write_text(s[:start] + new, encoding="utf-8")
print("Prepared custom TabBar injection without altering the GPS engine")
