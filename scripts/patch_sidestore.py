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


# The embedded manager can receive two near-simultaneous foreground starts
# while LiveContainer switches from the map guest to SideStore. Core Data must
# coalesce those requests instead of asking one coordinator to add AltStore.sqlite
# twice (NSCocoaErrorDomain 134081: "Can't add the same store twice").
persistent_container = root / "AltStoreCore/Roxas/RSTPersistentContainer.swift"
replace_required(
    persistent_container,
    '''    private let parentBackgroundContexts = NSHashTable<NSManagedObjectContext>.weakObjects()
    private let pendingSaveParentBackgroundContexts = NSHashTable<NSManagedObjectContext>.weakObjects()
''',
    '''    private let parentBackgroundContexts = NSHashTable<NSManagedObjectContext>.weakObjects()
    private let pendingSaveParentBackgroundContexts = NSHashTable<NSManagedObjectContext>.weakObjects()

    private let persistentStoreLoadLock = NSLock()
    private var isLoadingPersistentStores = false
    private var persistentStoreLoadWaiters = [(NSPersistentStoreDescription, Error?) -> Void]()
''',
)

replace_required(
    persistent_container,
    '''    open override func loadPersistentStores(completionHandler: @escaping (NSPersistentStoreDescription, Error?) -> Void) {
        let dispatchGroup = DispatchGroup()
''',
    '''    open override func loadPersistentStores(completionHandler: @escaping (NSPersistentStoreDescription, Error?) -> Void) {
        persistentStoreLoadLock.lock()

        if let existingStore = persistentStoreCoordinator.persistentStores.first,
           let existingURL = existingStore.url?.standardizedFileURL,
           let existingDescription = persistentStoreDescriptions.first(where: {
               $0.url?.standardizedFileURL == existingURL
           }) {
            persistentStoreLoadLock.unlock()
            configure(viewContext, parent: nil)
            completionHandler(existingDescription, nil)
            return
        }

        persistentStoreLoadWaiters.append(completionHandler)
        guard !isLoadingPersistentStores else {
            persistentStoreLoadLock.unlock()
            return
        }
        isLoadingPersistentStores = true
        persistentStoreLoadLock.unlock()

        let dispatchGroup = DispatchGroup()
''',
)

replace_required(
    persistent_container,
    '''        let finish: (NSPersistentStoreDescription, Error?) -> Void = { [weak self] description, error in
            guard let self = self else { return }
            self.configure(self.viewContext, parent: nil)
            completionHandler(description, error)
        }
''',
    '''        let finish: (NSPersistentStoreDescription, Error?) -> Void = { [weak self] description, error in
            guard let self = self else { return }
            self.configure(self.viewContext, parent: nil)

            self.persistentStoreLoadLock.lock()
            self.isLoadingPersistentStores = false
            let waiters = self.persistentStoreLoadWaiters
            self.persistentStoreLoadWaiters.removeAll()
            self.persistentStoreLoadLock.unlock()

            waiters.forEach { $0(description, error) }
        }
''',
)


# A free Apple developer team is allowed one active development certificate.
# If Apple's first certificate listing is stale/empty, requesting a new one can
# return tooManyCertificates. Refresh the portal list, present the normal revoke
# chooser, and retry exactly once after the user's explicit selection.
replace_required(
    authentication,
    '''    private func requestCertificate(for team: ALTTeam, session: ALTAppleAPISession) async throws -> ALTCertificate {
''',
    '''    private func requestCertificate(for team: ALTTeam, session: ALTAppleAPISession, allowLimitRecovery: Bool = true) async throws -> ALTCertificate {
''',
)
replace_required(
    authentication,
    '''    private func replaceCertificate(portalCertificates: [ALTX509Certificate], for team: ALTTeam, session: ALTAppleAPISession) async throws -> ALTCertificate {
''',
    '''    private func replaceCertificate(portalCertificates: [ALTX509Certificate], for team: ALTTeam, session: ALTAppleAPISession, allowLimitRecovery: Bool = true) async throws -> ALTCertificate {
''',
)
replace_required(
    authentication,
    '''            return try await self.requestCertificate(for: team, session: session)
        }
        
        self.debugLog("[Authentication] replaceCertificate: Presenting revoke alert for \\(replaceableCertificates.count) development cert(s)...")
''',
    '''            return try await self.requestCertificate(for: team, session: session, allowLimitRecovery: allowLimitRecovery)
        }
        
        self.debugLog("[Authentication] replaceCertificate: Presenting revoke alert for \\(replaceableCertificates.count) development cert(s)...")
''',
)
replace_required(
    authentication,
    '''                self.verboseLog("[Authentication] replaceCertificate: Keeping existing, calling requestCertificate...")
                return try await self.requestCertificate(for: team, session: session)
''',
    '''                self.verboseLog("[Authentication] replaceCertificate: Keeping existing, calling requestCertificate...")
                return try await self.requestCertificate(for: team, session: session, allowLimitRecovery: allowLimitRecovery)
''',
)
replace_required(
    authentication,
    '''                    self.debugLog("[Authentication] replaceCertificate: Selected certificates successfully revoked. Requesting new certificate...")
                    return try await self.requestCertificate(for: team, session: session)
''',
    '''                    self.debugLog("[Authentication] replaceCertificate: Selected certificates successfully revoked. Requesting new certificate...")
                    return try await self.requestCertificate(for: team, session: session, allowLimitRecovery: allowLimitRecovery)
''',
)
replace_required(
    authentication,
    '''            if underlying.domain == ALTAppleAPIErrorDomain && 
               underlying.code == ALTAppleAPIError.tooManyCertificates.rawValue 
            {
                let friendlyError: AuthenticationError = (team.type == .free) 
''',
    '''            if underlying.domain == ALTAppleAPIErrorDomain &&
               underlying.code == ALTAppleAPIError.tooManyCertificates.rawValue
            {
                if team.type == .free && allowLimitRecovery {
                    let latestPortalCertificates = try await AuthManager.shared.fetchCertificates(for: team, session: session)
                    self.context.portalCertificates = latestPortalCertificates
                    if !latestPortalCertificates.isEmpty {
                        self.debugLog("[Authentication] Certificate limit reached with a stale/empty portal list. Offering one-time replacement recovery.")
                        return try await self.replaceCertificate(
                            portalCertificates: latestPortalCertificates,
                            for: team,
                            session: session,
                            allowLimitRecovery: false
                        )
                    }
                }

                let friendlyError: AuthenticationError = (team.type == .free) 
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
