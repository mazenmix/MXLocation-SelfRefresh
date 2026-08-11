from pathlib import Path
import sys


root = Path(sys.argv[1]).resolve()


def replace_required(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise RuntimeError(f"Required source fragment not found in {path}: {old[:160]!r}")
    path.write_text(text.replace(old, new), encoding="utf-8")


# Sideloadly creates the one certificate allowed by a free developer account,
# but Apple may report it under a generic Apple Development name. The upstream
# LiveContainer build filters the revoke prompt to legacy iOS Development names,
# then incorrectly asks Apple for a second certificate when that list is empty.
# For free teams, show the normal revoke/replace prompt for any portal certificate
# whose private key is unavailable. Paid teams retain upstream's conservative
# filtering so unrelated distribution certificates are untouched.
authentication = (
    root
    / "SideStore/Core/Operations/StandaloneOperations/AuthenticationOperation.swift"
)
replace_required(
    authentication,
    '''        let iosCertificates = portalCertificates.filter { cert in
            let nameLower = cert.name.lowercased()
            return nameLower.contains("ios development") || nameLower.contains("iphone developer")
        }

        self.debugLog("[Authentication] replaceCertificate: Starting. Total certs on portal: \\(portalCertificates.count), iOS Development certs: \\(iosCertificates.count)")
        
        if iosCertificates.isEmpty {
            self.verboseLog("[Authentication] replaceCertificate: No iOS Development certificates found on portal. Requesting new...")
            return try await self.requestCertificate(for: team, session: session)
        }
        
        self.debugLog("[Authentication] replaceCertificate: Presenting revoke alert for \\(iosCertificates.count) iOS Development cert(s)...")
        let action = try await self.context.authenticationHandler.resolveRevocation(certificates: iosCertificates, teamType: team.type)
''',
    '''        let iosCertificates = portalCertificates.filter { cert in
            let nameLower = cert.name.lowercased()
            return nameLower.contains("ios development") || nameLower.contains("iphone developer")
        }

        let replaceableCertificates = team.type == .free ? portalCertificates : iosCertificates
        self.debugLog("[Authentication] replaceCertificate: Starting. Total certs on portal: \\(portalCertificates.count), replaceable certs: \\(replaceableCertificates.count)")
        
        if replaceableCertificates.isEmpty {
            self.verboseLog("[Authentication] replaceCertificate: No replaceable development certificates found on portal. Requesting new...")
            return try await self.requestCertificate(for: team, session: session)
        }
        
        self.debugLog("[Authentication] replaceCertificate: Presenting revoke alert for \\(replaceableCertificates.count) development cert(s)...")
        let action = try await self.context.authenticationHandler.resolveRevocation(certificates: replaceableCertificates, teamType: team.type)
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
