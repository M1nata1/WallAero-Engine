import SwiftUI
import WallpaperCore

/// The Steam Workshop in the main window: what there is to download, in the library's own look.
struct WorkshopView: View {
    @EnvironmentObject private var store: WorkshopStore
    @EnvironmentObject private var library: WallpaperLibrary

    var body: some View {
        list
            .topBar { filters }
            .bottomBar { footer }
            .frame(minWidth: LibraryView.minimumSize.width, minHeight: LibraryView.minimumSize.height)
            .task {
                if store.items.isEmpty {
                    store.reload()
                }
            }
            .onChange(of: store.query.sort) { _ in store.reload() }
            .onChange(of: store.query.kind) { _ in store.reload() }
            .onChange(of: store.query.includesMature) { _ in store.reload() }
            .sheet(isPresented: $store.showsSignIn) {
                WorkshopSignInView()
            }
            .alert("Steam Workshop", isPresented: hasDownloadError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(verbatim: store.downloadError ?? "")
            }
    }

    private var hasDownloadError: Binding<Bool> {
        Binding(get: { store.downloadError != nil }, set: { if !$0 { store.downloadError = nil } })
    }

    // MARK: - Bars

    private var filters: some View {
        HStack(spacing: 10) {
            SearchField(text: $store.query.search, prompt: NSLocalizedString("Search the Workshop", comment: "Placeholder")) {
                store.reload()
            }
            .frame(minWidth: 160, maxWidth: 260)
            Spacer(minLength: 0)
            Picker("Type:", selection: $store.query.kind) {
                Text("All Types").tag(SteamWorkshop.Kind.all)
                Text("Scenes").tag(SteamWorkshop.Kind.scene)
                Text("Videos").tag(SteamWorkshop.Kind.video)
                Text("Web Pages").tag(SteamWorkshop.Kind.web)
            }
            .labelsHidden()
            .fixedSize()
            Picker("Sort:", selection: $store.query.sort) {
                Text("Popular This Week").tag(SteamWorkshop.Sort.popular)
                Text("Newest").tag(SteamWorkshop.Sort.recent)
                Text("Most Subscribed").tag(SteamWorkshop.Sort.subscribed)
            }
            .labelsHidden()
            .fixedSize()
            Toggle("Adult content", isOn: $store.query.includesMature)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let download = store.downloads.first(where: { $0.phase != .waiting }) {
                ProgressView(value: progress(of: download))
                    .progressViewStyle(.linear)
                    .frame(width: 120)
                Text(status(of: download))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Cancel") { store.cancel(download.item) }
                    .barButtonStyle()
                    .disabled(download.phase == .adding)
            }
            Spacer(minLength: 12)
            if let account = store.account {
                Text(verbatim: account)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button("Sign Out") { store.signOut() }
                    .barButtonStyle()
            } else {
                Button("Sign In to Steam…") { store.showsSignIn = true }
                    .barButtonStyle()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func progress(of download: WorkshopStore.Download) -> Double {
        if case .downloading(let part) = download.phase {
            return part
        }
        return 1
    }

    private func status(of download: WorkshopStore.Download) -> String {
        let waiting = store.downloads.filter { $0.phase == .waiting }.count
        var status: String
        if case .downloading(let part) = download.phase {
            status = String(format: NSLocalizedString("Downloading “%@”… %d%%", comment: "Workshop progress"),
                            download.item.title, Int((part * 100).rounded(.down)))
        } else {
            status = String(format: NSLocalizedString("Adding “%@”…", comment: "Workshop progress"), download.item.title)
        }
        if waiting > 0 {
            status += " " + String(format: NSLocalizedString("(%d more in queue)", comment: "Import progress"), waiting)
        }
        return status
    }

    // MARK: - The list

    @ViewBuilder
    private var list: some View {
        if store.items.isEmpty {
            placeholder
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            GeometryReader { area in
                let columns = LibraryView.columnCount(forWidth: area.size.width)
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(LibraryView.tileWidth), spacing: LibraryView.tileSpacing), count: columns),
                              alignment: .leading, spacing: 20) {
                        ForEach(store.items) { item in
                            WorkshopTile(item: item)
                                .onAppear {
                                    if item.id == store.items.last?.id {
                                        store.loadMore()
                                    }
                                }
                        }
                    }
                    .frame(width: CGFloat(columns) * (LibraryView.tileWidth + LibraryView.tileSpacing) - LibraryView.tileSpacing)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        if store.isLoading {
            ProgressView()
        } else if store.cannotLoad {
            VStack(spacing: 10) {
                Text("Can't open the Workshop")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Button("Try Again") { store.reload() }
            }
        } else {
            NothingFoundView(searchText: store.query.search)
        }
    }
}

/// One item of the Workshop, drawn as a wallpaper of the library is.
private struct WorkshopTile: View {
    @EnvironmentObject private var store: WorkshopStore
    @EnvironmentObject private var library: WallpaperLibrary
    let item: SteamWorkshop.Item

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            preview
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(verbatim: ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    action
                }
            }
            .padding(.horizontal, 2)
        }
        .help(item.title)
        .contextMenu {
            Button("Open in Steam") { NSWorkspace.shared.open(item.pageURL) }
            if store.download(for: item)?.phase == .waiting {
                Button("Cancel") { store.cancel(item) }
            }
        }
    }

    @ViewBuilder
    private var action: some View {
        if store.isInLibrary(item) {
            Label("In Library", systemImage: "checkmark")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let download = store.download(for: item) {
            // No button here: one in the place of Download would catch a second click on it.
            Text(download.phase == .waiting ? "In Queue" : "Downloading…")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Button("Download") { store.get(item) }
                .controlSize(.small)
        }
    }

    private var preview: some View {
        Color.black
            .aspectRatio(16 / 10, contentMode: .fit)
            .overlay {
                // A picture is cut to the tile only to look at: filling it, a tall one reaches
                // out over the buttons around it, and would take their clicks.
                WorkshopPreview(url: item.previewURL)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: SystemLook.tileCornerRadius, style: .continuous))
            .overlay(alignment: .topLeading) {
                if let kind = item.kindTag {
                    Text(verbatim: kind.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.55), in: Capsule())
                        .padding(6)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: SystemLook.tileCornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            }
    }
}

/// The picture of an item, from memory, from the day's pictures on disk, or else from Steam.
private struct WorkshopPreview: View {
    private static let loaded = NSCache<NSURL, NSImage>()

    @EnvironmentObject private var store: WorkshopStore
    let url: URL?
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    // It stands on black in the light theme too.
                    .environment(\.colorScheme, .dark)
            }
        }
        .task(id: url) {
            guard let url else { return }
            if let known = Self.loaded.object(forKey: url as NSURL) {
                image = known
                return
            }
            let previews = store.previews
            var picture = await Task.detached { previews.kept(for: url) }.value
            if picture == nil, let (data, _) = try? await URLSession.shared.data(from: url) {
                picture = await Task.detached { previews.keep(data, for: url) }.value
            }
            guard let picture else { return }
            let shown = NSImage(cgImage: picture, size: NSSize(width: picture.width, height: picture.height))
            Self.loaded.setObject(shown, forKey: url as NSURL)
            image = shown
        }
    }
}

/// Asks for the Steam account, and for whatever Steam wants to go with it.
struct WorkshopSignInView: View {
    @EnvironmentObject private var store: WorkshopStore
    @State private var account = ""
    @State private var password = ""
    @State private var code = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sign In to Steam")
                .font(.title2.weight(.semibold))
            Text("To download wallpapers you need a Steam account that owns Wallpaper Engine. The first time, the app gets SteamCMD, Valve's download tool, from Valve. Your password isn't saved.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            fields
            if let error = store.signInError {
                Text(verbatim: error)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel") {
                    password = ""
                    store.cancelSignIn()
                }
                .keyboardShortcut(.cancelAction)
                mainButton
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    @ViewBuilder
    private var fields: some View {
        switch store.signIn {
        case .idle:
            TextField("Account name", text: $account)
                .textFieldStyle(.roundedBorder)
                .textContentType(.username)
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)
        case .working:
            ProgressView()
                .controlSize(.small)
        case .updating(let percent):
            ProgressView(value: Double(percent), total: 100) {
                Text("Getting SteamCMD ready…")
            }
        case .needsCode(let source):
            Text(source == .email ? "Enter the Steam Guard code from the email Steam sent you." : "Enter the code from the Steam app on your phone.")
                .fixedSize(horizontal: false, vertical: true)
            TextField("Code", text: $code)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submitCode)
        case .needsConfirmation:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Confirm the sign-in in the Steam app on your phone.")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var mainButton: some View {
        if case .needsCode = store.signIn {
            Button("Continue", action: submitCode)
                .keyboardShortcut(.defaultAction)
                .disabled(code.isEmpty)
        } else {
            Button("Sign In", action: submit)
                .keyboardShortcut(.defaultAction)
                .disabled(store.signIn != .idle || account.isEmpty || password.isEmpty)
        }
    }

    private func submit() {
        guard !account.isEmpty, !password.isEmpty else { return }
        store.signIn(account: account, password: password)
        password = ""
    }

    private func submitCode() {
        guard !code.isEmpty else { return }
        store.send(code: code)
        code = ""
    }
}
