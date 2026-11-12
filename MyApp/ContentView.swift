import SwiftUI

struct ContentView: View {
  @Environment(SidebarModel.self) private var model
  @Environment(\.scenePhase) private var scenePhase
  #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  #endif
  @State private var selection: ToolID?
  @State private var compactColumn: NavigationSplitViewColumn = .detail
  @State private var visibility: NavigationSplitViewVisibility = .all
  @State private var jsonWorkspace = JSONWorkspaceSession()
  @State private var treeWorkspace = JSONTreeWorkspaceSession()
  @State private var diffWorkspace = JSONDiffWorkspaceSession()
  @State private var pathWorkspace = JSONPathWorkspaceSession()
  @State private var schemaWorkspace = JSONSchemaWorkspaceSession()
  @State private var yamlWorkspace = JSONYAMLWorkspaceSession()
  @State private var tomlWorkspace = JSONTOMLWorkspaceSession()
  @State private var xmlWorkspace = JSONXMLWorkspaceSession()
  @State private var csvWorkspace = JSONCSVWorkspaceSession()
  @State private var tableWorkspace = CSVTableWorkspaceSession()
  @State private var modelsWorkspace = JSONModelsWorkspaceSession()
  @State private var base64Workspace = Base64WorkspaceSession()
  @State private var base64FileWorkspace = Base64FileWorkspaceSession()
  @State private var urlPercentWorkspace = URLPercentWorkspaceSession()
  @State private var urlQueryWorkspace = URLQueryWorkspaceSession()
  @State private var htmlEntityWorkspace = HTMLEntityWorkspaceSession()
  @State private var stringEscapeWorkspace = StringEscapeWorkspaceSession()
  @State private var hexBytesWorkspace = HexBytesWorkspaceSession()
  @State private var gzipWorkspace = GZipWorkspaceSession()
  @State private var jwtWorkspace = JWTWorkspaceSession()
  @State private var jwtEncoderWorkspace = JWTEncoderWorkspaceSession()
  @State private var basicAuthWorkspace = BasicAuthWorkspaceSession()
  @State private var identifierWorkspace = IdentifierWorkspaceSession()
  @State private var passwordWorkspace = SecretGeneratorWorkspaceSession(kind: .password)
  @State private var passphraseWorkspace = SecretGeneratorWorkspaceSession(kind: .passphrase)
  @State private var tokenWorkspace = TokenWorkspaceSession()
  @State private var hashWorkspace = DigestWorkspaceSession()
  @State private var hmacWorkspace = DigestWorkspaceSession(isHMAC: true)
  @State private var qrWorkspace = QRCodeWorkspaceSession()
  @State private var qrDecoderWorkspace = QRCodeDecoderWorkspaceSession()
  @State private var certificateWorkspace = CertificateWorkspaceSession()
  @State private var strengthWorkspace = PasswordStrengthWorkspaceSession()
  @State private var verifierWorkspace = JWTVerifierWorkspaceSession()

  @State private var textDiffWorkspace = TextWorkspaces.diff()
  @State private var listsWorkspace = TextWorkspaces.lists()
  @State private var regexWorkspace = TextWorkspaces.regex()
  @State private var casingWorkspace = TextWorkspaces.casing()
  @State private var lineSortWorkspace = TextWorkspaces.sort()
  @State private var unicodeWorkspace = TextWorkspaces.unicode()
  @State private var loremWorkspace = TextWorkspaces.lorem()
  @State private var mockWorkspace = TextWorkspaces.mock()
  @State private var statisticsWorkspace = TextWorkspaces.statistics()
  @State private var replaceWorkspace = TextWorkspaces.regex(replace: true)

  @State private var date43 = DateNetworkWorkspaces.date(.unix)
  @State private var date44 = DateNetworkWorkspaces.date(.iso)
  @State private var date45 = DateNetworkWorkspaces.date(.zones)
  @State private var date46 = DateNetworkWorkspaces.date(.arithmetic)
  @State private var date47 = DateNetworkWorkspaces.date(.cron)
  @State private var network48 = DateNetworkWorkspaces.network(.cidr)
  @State private var network49 = DateNetworkWorkspaces.network(.http)
  @State private var network50 = DateNetworkWorkspaces.network(.mime)
  @State private var network51 = DateNetworkWorkspaces.network(.chmod)
  @State private var number52 = DateNetworkWorkspaces.number()

  @State private var colorWorkspace = ColorWorkspace()
  @State private var contrastWorkspace = ColorWorkspace()
  @State private var imageConverter = ImageWorkspace()
  @State private var imageResizer = ImageWorkspace(resize: true)
  @State private var imageMetadata = ImageWorkspace()
  @State private var svgWorkspace = SVGWorkspace()
  @State private var curlWorkspace = CurlWorkspace()
  @State private var connectionWorkspace = ConnectionWorkspace()

  @State private var pkiWorkspaces = Dictionary(uniqueKeysWithValues: PKITool.allCases.filter { $0 != .expiry }.map { (String(format: "T-%03d", $0.rawValue), PKIWorkspace(tool: $0)) })
  @State private var expirationWorkspace = PKIExpirationWorkspace()

  @State private var markupWorkspaces = Dictionary(uniqueKeysWithValues: MarkupTool.allCases.map { ($0.id, MarkupWorkspace($0)) })

  init(initialSelection: ToolID? = nil) {
    _selection = State(initialValue: initialSelection)
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--navigation-ui-tests"),
        ProcessInfo.processInfo.arguments.contains("--tree-stress-array")
      {
        let session = JSONTreeWorkspaceSession()
        session.input = "[" + Array(repeating: "0", count: 131_070).joined(separator: ",") + ",9]"
        session.inputCollapsed = true
        _treeWorkspace = State(initialValue: session)
        _selection = State(initialValue: .t002)
      }
    #endif
  }

  var body: some View {
    NavigationSplitView(columnVisibility: $visibility, preferredCompactColumn: $compactColumn) {
      ToolSidebar(
        selection: $selection,
        openHome: {
          selection = nil
          compactColumn = .detail
        }
      ) { id in
        selection = id
        compactColumn = .detail
      }
      .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 440)
      .background { ShellBackground() }
      #if os(macOS)
        .toolbar {
          ToolbarItem(placement: .automatic) { brandLabel }
          .sharedBackgroundVisibility(.hidden)
        }
      #endif
    } detail: {
      Group {
        if let selected = selection {
          if selected == .t001 {
            JSONFormatterView(workspace: jsonWorkspace)
          } else if selected == .t002 {
            JSONTreeViewerView(workspace: treeWorkspace)
          } else if selected == .t003 {
            JSONDiffView(workspace: diffWorkspace)
          } else if selected == .t004 {
            JSONPathExplorerView(workspace: pathWorkspace)
          } else if selected == .t005 {
            JSONSchemaValidatorView(workspace: schemaWorkspace)
          } else if selected == .t006 {
            JSONYAMLConverterView(workspace: yamlWorkspace)
          } else if selected == .t007 {
            JSONCSVConverterView(workspace: csvWorkspace)
          } else if selected == .t008 {
            JSONXMLConverterView(workspace: xmlWorkspace)
          } else if selected == .t009 {
            JSONTOMLConverterView(workspace: tomlWorkspace)
          } else if selected == .t010 {
            CSVTableViewerView(workspace: tableWorkspace)
          } else if selected == .t011 {
            JSONModelsView(workspace: modelsWorkspace)
          } else if selected == .t012 {
            Base64TextView(workspace: base64Workspace)
          } else if selected == .t013 {
            Base64FileView(workspace: base64FileWorkspace)
          } else if selected == .t014 {
            URLPercentView(workspace: urlPercentWorkspace)
          } else if selected == .t015 {
            URLQueryView(workspace: urlQueryWorkspace)
          } else if selected == .t016 {
            HTMLEntityView(workspace: htmlEntityWorkspace)
          } else if selected == .t017 {
            StringEscapeView(workspace: stringEscapeWorkspace)
          } else if selected == .t018 {
            HexBytesView(workspace: hexBytesWorkspace)
          } else if selected == .t021 {
            BasicAuthHeaderView(workspace: basicAuthWorkspace)
          } else if selected == .t022 {
            IdentifierGeneratorView(workspace: identifierWorkspace)
          } else if selected == .t023 {
            PasswordGeneratorView(workspace: passwordWorkspace)
          } else if selected == .t024 {
            PassphraseGeneratorView(workspace: passphraseWorkspace)
          } else if selected == .t025 {
            TokenGeneratorView(workspace: tokenWorkspace)
          } else if selected == .t026 {
            HashGeneratorView(workspace: hashWorkspace)
          } else if selected == .t027 {
            HMACGeneratorView(workspace: hmacWorkspace)
          } else if selected == .t028 {
            QRCodeGeneratorView(workspace: qrWorkspace)
          } else if selected == .t029 {
            QRCodeDecoderView(workspace: qrDecoderWorkspace)
          } else if selected == .t030 {
            CertificateInspectorView(workspace: certificateWorkspace)
          } else if selected == .t031 {
            PasswordStrengthView(workspace: strengthWorkspace)
          } else if selected == .t032 {
            JWTVerifierView(workspace: verifierWorkspace)
          } else if selected.rawValue >= "T-043" && selected.rawValue <= "T-052" {
            dateNetworkTool(selected)
              .navigationTitle(ToolCatalog.tool(selected).displayName)
          } else if selected.rawValue >= "T-033" && selected.rawValue <= "T-042" {
            textTool(selected)
          } else if selected == .t078 {
            JWTEncoderView(workspace: jwtEncoderWorkspace)
          } else if selected == .t020 {
            JWTInspectorView(workspace: jwtWorkspace)
          } else if selected == .t019 {
            GZipView(workspace: gzipWorkspace)
          } else if selected == .t061 {
            ColorConverterView(workspace: colorWorkspace)
              .navigationTitle(ToolCatalog.tool(selected).displayName)
          } else if selected == .t062 {
            ContrastView(workspace: contrastWorkspace)
              .navigationTitle(ToolCatalog.tool(selected).displayName)
          } else if selected == .t063 {
            ImageWorkspaceView(workspace: imageConverter, tool: 63)
              .navigationTitle(ToolCatalog.tool(selected).displayName)
          } else if selected == .t064 {
            ImageWorkspaceView(workspace: imageResizer, tool: 64)
              .navigationTitle(ToolCatalog.tool(selected).displayName)
          } else if selected == .t065 {
            ImageWorkspaceView(workspace: imageMetadata, tool: 65)
              .navigationTitle(ToolCatalog.tool(selected).displayName)
          } else if selected == .t066 {
            SVGWorkspaceView(workspace: svgWorkspace)
              .navigationTitle(ToolCatalog.tool(selected).displayName)
          } else if selected == .t067 {
            CurlWorkspaceView(workspace: curlWorkspace)
              .navigationTitle(ToolCatalog.tool(selected).displayName)
          } else if selected == .t068 {
            ConnectionWorkspaceView(workspace: connectionWorkspace)
              .navigationTitle(ToolCatalog.tool(selected).displayName)
          } else if selected == .t076 {
            PKIExpirationView(workspace: expirationWorkspace)
          } else if let workspace = pkiWorkspaces[selected.rawValue] {
            PKIWorkspaceView(workspace: workspace)
          } else if let workspace = markupWorkspaces[selected.rawValue] {
            CodeMarkupWorkspaceView(workspace: workspace)
              .navigationTitle(ToolCatalog.tool(selected).displayName)
          } else {
            ToolPlaceholderView(tool: ToolCatalog.tool(selected))
          }
        } else {
          HomeView(showsBrowseTools: !isSidebarVisible) {
            visibility = .all
            compactColumn = .sidebar
          }
        }
      }
      .background {
        if selection == nil {
          ShellBackground()
        } else {
          ShellWorkspaceBackground()
        }
      }
      .toolbar {
        #if os(iOS)
          ToolbarItem(placement: .topBarLeading) {
            if horizontalSizeClass == .regular { brandLabel }
          }
        #endif
        ToolbarItem(placement: .primaryAction) { AppearanceMenu() }
      }
    }
    .modifier(ShellWindowChrome())
    .preferredColorScheme(model.preferences.appearance.colorScheme)
    .onChange(of: scenePhase) { _, phase in
      if phase == .background {
        for workspace in pkiWorkspaces.values { workspace.concealSecrets() }
        curlWorkspace.masked = true
        connectionWorkspace.masked = true
        imageMetadata.revealGPS = false
        passwordWorkspace.concealSecrets()
        passphraseWorkspace.concealSecrets()
        tokenWorkspace.concealSecrets()
        hmacWorkspace.concealSecrets()
      }
    }
    .onChange(of: selection) { _, selected in
      model.preferences.selectedTool = selected
    }
    #if os(macOS)
    // Losing a window's key status (menus, panels, another app window) is not
    // app deactivation. App switching must conceal every retained PKI workspace.
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
      for workspace in pkiWorkspaces.values { workspace.concealSecrets() }
    }
    #endif
  }

  private var isSidebarVisible: Bool {
    #if os(iOS)
      // Column visibility is ignored in a collapsed split view: the preferred
      // compact column tracks which screen is presented on iPhone/narrow iPad.
      if horizontalSizeClass == .compact {
        return compactColumn == .sidebar
      }
    #endif
    return visibility != .detailOnly
  }

  @ViewBuilder private func dateNetworkTool(_ selected: ToolID) -> some View {
    if selected == .t043 {
      DateToolsView(workspace: date43)
    } else if selected == .t044 {
      DateToolsView(workspace: date44)
    } else if selected == .t045 {
      DateToolsView(workspace: date45)
    } else if selected == .t046 {
      DateToolsView(workspace: date46)
    } else if selected == .t047 {
      DateToolsView(workspace: date47)
    } else if selected == .t048 {
      NetworkToolsView(workspace: network48)
    } else if selected == .t049 {
      NetworkToolsView(workspace: network49)
    } else if selected == .t050 {
      NetworkToolsView(workspace: network50)
    } else if selected == .t051 {
      NetworkToolsView(workspace: network51)
    } else if selected == .t052 {
      NumberConverterView(workspace: number52)
    }
  }

  @ViewBuilder private func textTool(_ selected: ToolID) -> some View {
    if selected == .t033 {
      TextDiffView(workspace: textDiffWorkspace)
    } else if selected == .t034 {
      TextListView(workspace: listsWorkspace)
    } else if selected == .t035 {
      TextRegexView(workspace: regexWorkspace)
    } else if selected == .t036 {
      TextCaseView(workspace: casingWorkspace)
    } else if selected == .t037 {
      TextSortView(workspace: lineSortWorkspace)
    } else if selected == .t038 {
      TextUnicodeView(workspace: unicodeWorkspace)
    } else if selected == .t039 {
      LoremGeneratorView(workspace: loremWorkspace)
    } else if selected == .t040 {
      MockDataView(workspace: mockWorkspace)
    } else if selected == .t041 {
      TextStatisticsView(workspace: statisticsWorkspace)
    } else if selected == .t042 {
      TextRegexView(workspace: replaceWorkspace, replacement: true)

    }
  }

  private var brandLabel: some View {
    Text("ToolHold")
      #if os(macOS)
        .font(.title3.weight(.semibold))
      #else
        .font(.headline)
      #endif
      .foregroundStyle(.secondary)
      .lineLimit(1)
      .accessibilityIdentifier("app-brand")
  }
}

private struct ToolPlaceholderView: View {
  let tool: ToolDescriptor
  var body: some View {
    ContentUnavailableView {
      Label(tool.displayName, systemImage: tool.symbol)
    } description: {
      VStack(spacing: 8) {
        Text(tool.category.title)
        Text("Not implemented").font(.headline)
        Text("This tool is included in the navigation preview.")
      }
    }
    .navigationTitle(tool.displayName)
  }
}

#Preview { ContentView().environment(SidebarModel()) }
