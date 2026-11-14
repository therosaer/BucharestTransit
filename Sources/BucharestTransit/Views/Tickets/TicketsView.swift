import SwiftUI

public struct TicketsView: View {
    @ObservedObject var appState: AppState

    @State private var usernameInput = ""
    @State private var passwordInput = ""
    @State private var isLoggingIn = false
    @State private var loginError: String?
    @State private var savedBrightness: CGFloat?

    private enum Field { case username, password }
    @FocusState private var focusedField: Field?

    public var body: some View {
        NavigationStack {
            Group {
                if appState.biletStatus.authenticated {
                    ScrollView {
                        authenticatedDashboardView
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                            .padding(.bottom, 24)
                    }
                    .background(Color.appBackground)
                    .refreshable {
                        await appState.loadBiletActiveTickets()
                    }
                } else {
                    unauthenticatedLoginView
                }
            }
            .navigationTitle("Elevi și studenți")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if appState.biletStatus.authenticated {
                    ToolbarItem(placement: .topBarTrailing) { accountMenu }
                }
            }
        }
    }

    private var accountMenu: some View {
        Menu {
            Section {
                Text(appState.biletStatus.account?.fullName ?? "Cont Bilet TB")
                Text(appState.biletStatus.account?.email ?? "")
            }
            Button(role: .destructive) {
                Task { await appState.logoutBilet() }
            } label: {
                Label("Deconectare", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            Text(appState.biletStatus.account?.initials ?? "AI")
                .font(.system(.footnote, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Color.appleBlue, in: Circle())
        }
        .accessibilityLabel("Cont")
    }

    // MARK: - Date helpers

    private func parseDate(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: string) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: string) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Bucharest")
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss"] {
            f.dateFormat = format
            if let d = f.date(from: string) { return d }
        }
        return nil
    }

    private func displayDate(_ string: String?) -> String? {
        guard let string else { return nil }
        guard let date = parseDate(string) else { return string }
        return date.formatted(.dateTime.day().month(.abbreviated).year().hour().minute().locale(Locale(identifier: "ro_RO")))
    }

    private var canSubmit: Bool {
        !usernameInput.trimmingCharacters(in: .whitespaces).isEmpty && !passwordInput.isEmpty && !isLoggingIn
    }

    private func submitLogin() {
        guard canSubmit else { return }
        focusedField = nil
        HapticFeedback.trigger(.medium)
        isLoggingIn = true
        loginError = nil
        appState.clearBiletLoginError()
        Task {
            let success = await appState.loginBilet(username: usernameInput, pass: passwordInput)
            isLoggingIn = false
            if !success {
                loginError = appState.biletLoginError ?? "Autentificarea nu a reușit. Verifică datele contului."
            }
        }
    }

    private var authenticatedDashboardView: some View {
        VStack(spacing: 16) {
            activeTicketsTab
        }
        .onAppear { raiseBrightness() }
        .onDisappear { restoreBrightness() }
    }

    private func raiseBrightness() {
        #if canImport(UIKit)
        guard savedBrightness == nil else { return }
        savedBrightness = UIScreen.main.brightness
        UIScreen.main.brightness = max(UIScreen.main.brightness, 0.9)
        #endif
    }

    private func restoreBrightness() {
        #if canImport(UIKit)
        if let saved = savedBrightness {
            UIScreen.main.brightness = saved
            savedBrightness = nil
        }
        #endif
    }

    private var activeTicketsTab: some View {
        VStack(spacing: 14) {
            if appState.biletTicketsLoading && appState.biletActiveTickets.isEmpty {
                ProgressView("Se încarcă titlurile...")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else if let error = appState.biletTicketsError {
                ContentUnavailableView {
                    Label("Titlurile nu au putut fi încărcate", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Încearcă din nou") {
                        Task { await appState.loadBiletActiveTickets() }
                    }
                    .buttonStyle(.bordered)
                }
            } else if appState.biletActiveTickets.isEmpty {
                ContentUnavailableView {
                    Label("Niciun titlu activ", systemImage: "ticket")
                } description: {
                    Text("Aici apar titlurile anuale pentru elevi și studenți deja înregistrate în YouthTB.")
                }
            } else {
                ForEach(appState.biletActiveTickets) { ticket in
                    ticketCard(ticket)
                }
            }
        }
    }

    private func ticketCard(_ ticket: Ticket) -> some View {
        VStack(spacing: 16) {
            // QR first: it is the only thing an inspector needs.
            VStack(spacing: 10) {
                QRCodeView(base64Image: ticket.qrBase64Payload)

                if let series = ticket.seriesCode {
                    Text("Seria: \(series)")
                        .font(.system(.caption, design: .monospaced, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("Activ", systemImage: "checkmark.seal.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.appleGreenText)
                        Text(ticket.title)
                            .font(.title3.weight(.bold))
                        Text("Titlu înregistrat în YouthTB")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if ticket.isStudentElev {
                        Text("Elev / Student")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.appleGreenText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.appleGreen.opacity(0.15), in: Capsule())
                    }
                }

                Divider()

                remainingRow(ticket)

                if ticket.validFromDate != nil || ticket.validToDate != nil {
                    VStack(spacing: 6) {
                        if let from = displayDate(ticket.validFromDate) {
                            LabeledContent("Valabil de la", value: from)
                        }
                        if let to = displayDate(ticket.validToDate) {
                            LabeledContent("Valabil până la", value: to)
                        }
                    }
                    .font(.footnote)
                }
            }
        }
        .padding(18)
        .groupedCardBackground(cornerRadius: 22)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func remainingRow(_ ticket: Ticket) -> some View {
        let endDate = parseDate(ticket.validToDate)
            ?? ticket.remainingSeconds.map { Date().addingTimeInterval(TimeInterval($0)) }
        if let endDate {
            let seconds = Int(endDate.timeIntervalSinceNow)
            HStack {
                Label("Timp rămas", systemImage: "hourglass")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Group {
                    if seconds <= 0 {
                        Text("Expirat")
                    } else if seconds < 86_400 {
                        Text(timerInterval: Date.now...endDate, countsDown: true)
                    } else {
                        Text(TransitTimeFormatter.formatRemaining(seconds: seconds))
                    }
                }
                .font(.system(.headline, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(seconds < 600 ? Color.appleRed : Color.appleGreenText)
            }
        }
    }

    private var unauthenticatedLoginView: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: "ticket.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.appleBlue)
                        .accessibilityHidden(true)
                    Text("Titluri pentru elevi și studenți")
                        .font(.system(.title3, design: .rounded, weight: .heavy))
                        .multilineTextAlignment(.center)
                    Text("Autentifică-te pentru a vedea titlurile anuale deja înregistrate în YouthTB și codul QR pentru control. Nu se pot cumpăra titluri din această secțiune.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section {
                TextField("Email sau număr de telefon", text: $usernameInput)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focusedField, equals: .username)
                    .onSubmit { focusedField = .password }

                SecureField("Parolă", text: $passwordInput)
                    .textContentType(.password)
                    .submitLabel(.go)
                    .focused($focusedField, equals: .password)
                    .onSubmit { submitLogin() }
            } footer: {
                if let message = appState.biletLoginError ?? loginError {
                    Text(message)
                        .foregroundStyle(Color.appleRed)
                }
            }

            Section {
                Button(action: submitLogin) {
                    Group {
                        if isLoggingIn {
                            ProgressView()
                        } else {
                            Text("Autentificare")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canSubmit)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .sensoryFeedback(.error, trigger: loginError) { _, new in new != nil }
    }
}
