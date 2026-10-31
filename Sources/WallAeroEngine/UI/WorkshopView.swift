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
                let room = area.size.height - area.safeAreaInsets.top - area.safeAreaInsets.bottom
                ScrollViewReader { scroller in
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
                        // As high as the room there is at least: a click below the rows closes
                        // the panel too.
                        .frame(maxWidth: .infinity, minHeight: max(0, room - 1), alignment: .top)
                        .background {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { store.selected = nil }
                        }
                    }
                    // The panel opening takes a column away: the clicked item stays in sight.
                    .onChange(of: columns) { _ in
                        if let id = store.selected?.id {
                            scroller.scrollTo(id)
                        }
                    }
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
        .contentShape(Rectangle())
        .onTapGesture { store.selected = item }
        .contextMenu {
            Button("Open in Steam") { NSWorkspace.shared.open(item.pageURL) }
            if store.download(for: item)?.phase == .waiting {
                Button("Cancel") { store.cancel(item) }
            }
        }
    }

    /// How it stands with the item. Getting it is for the panel at the side.
    @ViewBuilder
    private var action: some View {
        if store.isInLibrary(item) {
            Label("In Library", systemImage: "checkmark")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let download = store.download(for: item) {
            Text(download.phase == .waiting ? "In Queue" : "Downloading…")
                .font(.caption)
                .foregroundStyle(.secondary)
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
                let isSelected = store.selected?.id == item.id
                RoundedRectangle(cornerRadius: SystemLook.tileCornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isSelected ? 3 : 1)
            }
    }
}

/// The panel at the side of the window: what the clicked item is, and getting it.
struct WorkshopDetailsPanel: View {
    @EnvironmentObject private var store: WorkshopStore

    var body: some View {
        if let item = store.selected {
            WorkshopDetails(item: item)
                .id(item.id)
        }
    }
}

private struct WorkshopDetails: View {
    @EnvironmentObject private var store: WorkshopStore
    let item: SteamWorkshop.Item
    @State private var page: SteamWorkshop.Page?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    WorkshopMovingPreview(item: item)
                        .frame(maxWidth: .infinity)
                    Text(verbatim: item.title)
                        .font(.title3.weight(.semibold))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    properties
                    if !shownTags.isEmpty {
                        FlowLayout {
                            ForEach(shownTags, id: \.self) { tag in
                                Text(verbatim: tag)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(.quaternary, in: Capsule())
                            }
                        }
                    }
                    if !item.description.isEmpty {
                        Text(verbatim: item.description)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button("Open in Steam") { NSWorkspace.shared.open(item.pageURL) }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            action
                .frame(minHeight: 28)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .task {
            page = try? await SteamWorkshop.page(of: item)
        }
    }

    /// What the tags say beyond the type, and beyond what all of them have.
    private var shownTags: [String] {
        item.tags.filter { $0 != item.kindTag && $0 != "Wallpaper" && $0 != "Everyone" }
    }

    private var properties: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            if let author = page?.author {
                row("Author") { Text(verbatim: author).textSelection(.enabled) }
            }
            if let stars = page?.stars {
                row("Rating") {
                    Text(verbatim: String(repeating: "★", count: stars) + String(repeating: "☆", count: 5 - min(stars, 5)))
                        .accessibilityLabel(Text(verbatim: "\(stars)/5"))
                }
            }
            if let kind = kind {
                row("Type") { Text(kind) }
            }
            row("Size") { Text(verbatim: ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file)) }
            row("Subscribers") { Text(verbatim: item.subscriptions.formatted()) }
            row("In Favorites") { Text(verbatim: item.favorites.formatted()) }
            if let updated = item.updated {
                row("Updated") { Text(verbatim: updated.formatted(date: .long, time: .omitted)) }
            }
        }
    }

    private func row<Value: View>(_ title: LocalizedStringKey, @ViewBuilder value: () -> Value) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
            value()
        }
    }

    private var kind: LocalizedStringKey? {
        switch item.kindTag {
        case "Scene": "Scene"
        case "Video": "Video"
        case "Web": "Web Page"
        default: nil
        }
    }

    /// Cancel takes the other end of the row from Download, which it follows on: a second click
    /// on the same spot is not to stop what the first one started.
    @ViewBuilder
    private var action: some View {
        if store.isInLibrary(item) {
            Label("In Library", systemImage: "checkmark")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let download = store.download(for: item) {
            HStack(spacing: 10) {
                Button("Cancel") { store.cancel(item) }
                    .disabled(download.phase == .adding)
                switch download.phase {
                case .waiting:
                    Text("In Queue")
                        .foregroundStyle(.secondary)
                case .downloading(let part):
                    ProgressView(value: part)
                        .progressViewStyle(.linear)
                    Text(verbatim: "\(Int((part * 100).rounded(.down)))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                case .adding:
                    Text("Adding…")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Button("Download") { store.get(item) }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

/// The item's preview in motion. Until it has arrived, the tile's still picture stands in.
private struct WorkshopMovingPreview: View {
    /// The side of the square: nearly all previews are square, and the moving ones only about
    /// 200 pixels, which any bigger comes out as a blur.
    private static let side: CGFloat = 300

    @EnvironmentObject private var store: WorkshopStore
    let item: SteamWorkshop.Item
    @State private var picture: NSImage?

    var body: some View {
        Color.black
            .frame(width: Self.side, height: Self.side)
            .overlay {
                if let picture {
                    MovingPicture(image: picture)
                } else {
                    WorkshopPreview(url: item.previewURL, contentMode: .fit)
                }
            }
            .allowsHitTesting(false)
            .clipShape(RoundedRectangle(cornerRadius: SystemLook.tileCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SystemLook.tileCornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            }
            .task {
                guard let url = item.originalPreviewURL else { return }
                let previews = store.previews
                var data = await Task.detached { previews.keptOriginal(for: url) }.value
                if data == nil, let (got, _) = try? await URLSession.shared.data(from: url) {
                    await Task.detached { previews.keepOriginal(got, for: url) }.value
                    data = got
                }
                picture = data.flatMap(NSImage.init(data:))
            }
    }
}

/// A picture that plays if it can, drawn by AppKit as a GIF is not in SwiftUI.
private struct MovingPicture: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        view.image = image
    }
}

/// The picture of an item, from memory, from the day's pictures on disk, or else from Steam.
private struct WorkshopPreview: View {
    private static let loaded = NSCache<NSURL, NSImage>()

    @EnvironmentObject private var store: WorkshopStore
    let url: URL?
    var contentMode = ContentMode.fill
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
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
