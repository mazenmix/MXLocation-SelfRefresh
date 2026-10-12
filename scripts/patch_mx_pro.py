from pathlib import Path
import shutil
import sys

root = Path(sys.argv[1]).resolve()
repo = Path(__file__).resolve().parent.parent
project = root / "project.yml"
plist = root / "Locus/Resources/Info.plist"
root_view = root / "Locus/Features/Map/RootView.swift"
source = project.read_text(encoding="utf-8")
assert "PRODUCT_BUNDLE_IDENTIFIER: com.mazenmix.mxlocation" in source
assert "PRODUCT_NAME: MXLocation" in source
source = source.replace("PRODUCT_BUNDLE_IDENTIFIER: com.mazenmix.mxlocation",
                        "PRODUCT_BUNDLE_IDENTIFIER: com.mazenmix.mxlocationpro")
source = source.replace("PRODUCT_NAME: MXLocation",
                        "PRODUCT_NAME: MXLocationPro")
source = source.replace('MARKETING_VERSION: "1.4.2"', 'MARKETING_VERSION: "4.0.0"')
source = source.replace('CURRENT_PROJECT_VERSION: "29"', 'CURRENT_PROJECT_VERSION: "40"')
project.write_text(source,encoding="utf-8")

info = plist.read_text(encoding="utf-8")
info = info.replace("com.mazenmix.mxlocation", "com.mazenmix.mxlocationpro")
info = info.replace("<string>mxlocation</string>", "<string>mxlocationpro</string>")
info = info.replace("<string>MX Location</string>", "<string>MX Location Pro</string>")
info = info.replace("MX Location uses", "MX Location Pro uses")
info = info.replace("MX Location keeps", "MX Location Pro keeps")
plist.write_text(info,encoding="utf-8")

ui = root_view.read_text(encoding="utf-8")
anchor = '''            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(2)'''
replacement = '''            MXProSuiteView()
                .tabItem {
                    Label("MX Pro", systemImage: "sparkles")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(3)'''
if anchor not in ui: raise RuntimeError("RootView tab anchor no longer matches")
root_view.write_text(ui.replace(anchor,replacement,1),encoding="utf-8")

src = repo / "overlays/MXLocationProSuite.swift"
dst = root / "Locus/Features/Map/MXLocationProSuite.swift"
assert src.is_file()
shutil.copy2(src,dst)

print("MX Location Pro: unique bundle ID, URL scheme, storage sandbox, separate root tab, 41-module discovery suite.")
