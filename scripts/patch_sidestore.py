from pathlib import Path
import sys


root = Path(sys.argv[1]).resolve()


def replace_required(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise RuntimeError(f"Required source fragment not found in {path}: {old[:160]!r}")
    path.write_text(text.replace(old, new), encoding="utf-8")


# Sideloadly creates the one certificate allowed by a free developer account,
# but its certificate name does not begin with SideStore/AltStore. Upstream
# consequently ignores it and asks Apple for a second certificate, which Apple
# rejects. For free teams, show the normal revoke/replace prompt for any portal
# certificate whose private key is unavailable. Paid teams retain upstream's
# conservative filtering so unrelated distribution certificates are untouched.
authentication = (
    root
    / "SideStore/Core/Operations/StandaloneOperations/AuthenticationOperation.swift"
)
replace_required(
    authentication,
    '''        let filteredCertificates = ourCertificates.filter { a in
            a.machineName?.starts(with: "SideStore") == true || a.machineName?.starts(with: "AltStore") == true
        }
''',
    '''        let filteredCertificates: [ALTCertificate]
        if team.type == .free {
            filteredCertificates = ourCertificates
        } else {
            filteredCertificates = ourCertificates.filter { certificate in
                certificate.machineName?.starts(with: "SideStore") == true ||
                certificate.machineName?.starts(with: "AltStore") == true
            }
        }
''',
)


# In the embedded manager, the named SideStore accent can resolve against the
# host app's resource environment. The authentication error toast then becomes
# white text on a white card. Use an explicit, high-contrast color so the real
# error is always readable inside MX Location.
toast = root / "AltStore/Components/ToastView.swift"
replace_required(
    toast,
    '''        self.backgroundColor = .altPrimary
        self.textLabel.textColor = .white
        self.detailTextLabel.textColor = .white
''',
    '''        self.backgroundColor = UIColor(
            red: 0.43,
            green: 0.00,
            blue: 0.72,
            alpha: 1.00
        )
        self.textLabel.textColor = .white
        self.detailTextLabel.textColor = .white
''',
)

authentication_view = root / "AltStore/Authentication/AuthenticationViewController.swift"
replace_required(
    authentication_view,
    '''                    toastView.show(in: self)
                    toastView.backgroundColor = .white
                    toastView.textLabel.textColor = .altPrimary
                    toastView.detailTextLabel.textColor = .altPrimary
                    self.toastView = toastView
''',
    '''                    toastView.show(in: self)
                    self.toastView = toastView
''',
)

print("Patched embedded SideStore renewal engine at", root)
