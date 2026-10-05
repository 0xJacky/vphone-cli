import SwiftUI

// Previews of the Sections group, reproducing the design canvas's Machines
// inspector, Host Setup checks, Core Bundles list, and form rows and detail bars.

// MARK: - Machines inspector

private struct DKSectionsPreviewInspector: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DK.Space.s4) {
                DKSection("Core Bundle", accessory: DKButtonSpec("Change…"), items: [
                    DKListItem("Host Programs", badges: [.init("2.6.0")], lines: ["vphone-cli and vphone-vm, at every start"]),
                    DKListItem("Guest Environment", badges: [.init("2.6.0")], lines: ["vphoned and the hook libraries"]),
                    DKListItem("Boot Chain", badges: [.init("2.6.0")], lines: ["Fixed when the machine was created"]),
                ])
                DKSection(
                    "Patches",
                    footnote: "Boot chain: 1 patch (TXM) not applied; only a restore applies it, which erases the data.",
                    rows: [
                        DKKeyValue("Preset", "Standard"),
                        DKKeyValue("Overrides", "5"),
                        DKKeyValue("Not Applied", "5", tone: .warning),
                    ],
                )
                DKSection("Firmware", rows: [
                    DKKeyValue("iOS", "26.6.2 (23G90)"),
                    DKKeyValue("cloudOS", "26.4 (23E5207q)"),
                ])
                DKSection("Hardware", rows: [
                    DKKeyValue("CPU", "8 cores"),
                    DKKeyValue("Memory", "8 GB"),
                    DKKeyValue("Disk", "64 GB"),
                ])
                DKSection("Network", rows: [
                    DKKeyValue("Mode", "NAT"),
                    DKKeyValue("IPv4 Address", "192.168.64.12", monospaced: true),
                    DKKeyValue("MAC Address", "5e:3a:91:0c:7d:21", monospaced: true),
                    DKKeyValue("mDNS Name", "research-26.local", monospaced: true),
                    DKKeyValue("Port Forward", "2222 → 22, 8080 → 80", monospaced: true),
                ])
                DKSection("Identity", rows: [
                    DKKeyValue("UDID", "[UDID]", monospaced: true),
                    DKKeyValue("Location", "~/VPhone/research-26", monospaced: true),
                ])
            }
            .padding(.top, DK.Space.s4)
            .padding(.horizontal, DK.Space.s5)
            .padding(.bottom, DK.Space.s6)
        }
        .frame(width: 460, height: 900)
        .background(DK.Palette.window)
    }
}

#Preview("Machines inspector") {
    DKSectionsPreviewInspector()
        .preferredColorScheme(.light)
}

#Preview("Machines inspector, dark") {
    DKSectionsPreviewInspector()
        .preferredColorScheme(.dark)
}

// MARK: - Host Setup

private struct DKSectionsPreviewHostSetup: View {
    var body: some View {
        VStack(spacing: 0) {
            DKPageHeader("Host Setup", subtitle: "6 of 6 required passed · 1 advisory warning", actions: [
                DKButtonSpec("Install Skill…"),
                DKButtonSpec("Check Again", glyph: .refresh),
            ])
            ScrollView {
                VStack(alignment: .leading, spacing: DK.Space.s4) {
                    DKSection(items: [
                        DKListItem(
                            "This Mac can run machines.",
                            glyph: .check,
                            glyphTone: .success,
                            lines: ["Every required check passed. One advisory check needs a look: free disk space."],
                        ),
                    ])
                    DKSection("Required", rows: [
                        DKKeyValue("Apple silicon", "[chip]", tone: .success),
                        DKKeyValue("macOS 15 or later", "[macOS version]", tone: .success),
                        DKKeyValue("Physical Mac", "Not a virtual machine", tone: .success),
                        DKKeyValue("Library on APFS", "~/VPhone on Macintosh HD", monospaced: true, tone: .success),
                        DKKeyValue("Developer Tools access", "Allowed", tone: .success),
                        DKKeyValue("Privileged helper", "2.5.0 ready", tone: .success),
                    ])
                    DKSection("Advisory", note: "Advisory checks do not block setup.", rows: [
                        DKKeyValue("Free disk space", "41 GB free", tone: .warning),
                        DKKeyValue("CPU and memory", "[cores] · [memory]", tone: .success),
                        DKKeyValue("Network", "NAT 192.168.64.0/24", monospaced: true, tone: .success),
                    ])
                }
                .padding(DK.Space.s5)
            }
        }
        .frame(width: 820, height: 640)
        .background(DK.Palette.window)
    }
}

#Preview("Host Setup") {
    DKSectionsPreviewHostSetup()
        .preferredColorScheme(.light)
}

#Preview("Host Setup, dark") {
    DKSectionsPreviewHostSetup()
        .preferredColorScheme(.dark)
}

// MARK: - Core Bundles

private struct DKSectionsPreviewBundles: View {
    var body: some View {
        VStack(spacing: 0) {
            DKPageHeader("Core Bundles", subtitle: "3 installed · default 2.6.0") {
                DKButton("Check for Updates", glyph: .refresh) {}
                DKButton("Install Local Build…", glyph: .bundle) {}
            }
            ScrollView {
                VStack(alignment: .leading, spacing: DK.Space.s4) {
                    DKSection(
                        "Installed",
                        note: "New machines use the default. Each machine keeps its own.",
                        footnote: "Stored in /Library/Application Support/vphone-launchpad/Bundles and managed by the helper.",
                        items: [
                            DKListItem(
                                "2.6.0", glyph: .bundle, monospacedTitle: true,
                                badges: [.init("Default", tone: .accent), .init("Preflight passed", tone: .success)],
                                lines: [
                                    "Release · Installed Oct 5, 2026 · SHA-256 [digest]",
                                    "Used by research-26, ios27-hooks, ipad-lab, pcc-research-2",
                                ],
                                actions: [DKButtonSpec("Show in Finder")],
                            ),
                            DKListItem(
                                "2.5.0", glyph: .bundle, monospacedTitle: true,
                                badges: [.init("Needs Launchpad 2.5")],
                                lines: [
                                    "Release · Installed Oct 3, 2026 · SHA-256 [digest]",
                                    "Used by ios27-hooks (guest, boot chain), ipad-lab (boot chain)",
                                ],
                                actions: [DKButtonSpec("Show in Finder")],
                            ),
                            DKListItem(
                                "2.4.0", glyph: .bundle, monospacedTitle: true,
                                badges: [.init("Needs Launchpad 2.4")],
                                lines: ["Release · Installed Sep 21, 2026 · SHA-256 [digest]", "Not used by any machine"],
                                actions: [DKButtonSpec("Show in Finder"), DKButtonSpec("Remove…", variant: .danger)],
                            ),
                        ],
                    )
                    DKSection("Shared by All Machines", items: [
                        DKListItem(
                            "IPSW cache",
                            lines: ["4 downloaded images. A second machine from the same image downloads nothing."],
                            value: "38.1 GB",
                            actions: [DKButtonSpec("Manage in Firmwares")],
                        ),
                    ])
                }
                .padding(DK.Space.s5)
            }
        }
        .frame(width: 900, height: 640)
        .background(DK.Palette.window)
    }
}

#Preview("Core Bundles") {
    DKSectionsPreviewBundles()
        .preferredColorScheme(.light)
}

#Preview("Core Bundles, dark") {
    DKSectionsPreviewBundles()
        .preferredColorScheme(.dark)
}

// MARK: - Form rows and detail bars

private struct DKSectionsPreviewFormsAndDetails: View {
    @State private var name = "research-26"
    @State private var locked = true

    var body: some View {
        VStack(alignment: .leading, spacing: DK.Space.s4) {
            DKSection("General") {
                DKFormRow("Name", fill: true) {
                    TextField("Name", text: $name).textFieldStyle(.roundedBorder)
                }
                DKFormRow("Rotation Lock") {
                    Toggle("Rotation Lock", isOn: $locked).labelsHidden().toggleStyle(.switch)
                }
                DKFormRow("Location", fill: true) {
                    Text("~/VPhone/research-26").font(DK.Typeface.mono)
                    DKButton("Show in Finder", size: .small) {}
                }
            }
            .padding(.horizontal, DK.Space.s5)
            Spacer(minLength: 0)
            DKDetailBar(
                "SpringBoard",
                subtitle: "pid 61",
                facts: [
                    DKKeyValue("Bundle ID", "com.apple.springboard"),
                    DKKeyValue("PPID", "1"),
                    DKKeyValue("Started", "Today 09:41:08"),
                    DKKeyValue("Executable", "/System/Library/CoreServices/SpringBoard.app/SpringBoard"),
                ],
            )
            DKDetailBar(
                "Password",
                subtitle: "[account]",
                note: "Value is protected. Reveal asks the guest for it; Edit stores the text as its UTF-8 bytes.",
                actions: [
                    DKButtonSpec("Copy Row (TSV)", glyph: .copy),
                    DKButtonSpec("Edit Value…"),
                    DKButtonSpec("Delete…", glyph: .trash, variant: .danger),
                ],
                layout: .row,
            )
        }
        .padding(.top, DK.Space.s4)
        .frame(width: 900, height: 560)
        .background(DK.Palette.window)
    }
}

#Preview("Form rows and detail bars") {
    DKSectionsPreviewFormsAndDetails()
        .preferredColorScheme(.light)
}

#Preview("Form rows and detail bars, dark") {
    DKSectionsPreviewFormsAndDetails()
        .preferredColorScheme(.dark)
}
