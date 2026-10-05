import AppKit
import SwiftUI
import VPhoneDesignKit

/// Hands the vphone skill to the user's own coding agent. Agents keep skills in
/// different places, so Launchpad installs nothing itself: it shows a prompt
/// that names the skill folder inside this app, and the agent copies it.
struct VPhoneLaunchpadSkillInstallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    /// The skill folder the build copies into Contents/Resources/Skills.
    static var skillURL: URL? {
        let url = Bundle.main.resourceURL?
            .appendingPathComponent("Skills", isDirectory: true)
            .appendingPathComponent("vphone-guest-control", isDirectory: true)
        guard let url, FileManager.default.fileExists(atPath: url.appendingPathComponent("SKILL.md").path) else {
            return nil
        }
        return url
    }

    private var prompt: String? {
        Self.skillURL.map { url in
            """
            Install the vphone skill so you can use it in later sessions.

            The skill is the folder:
            \(url.path)

            Read SKILL.md there, then copy the whole folder, with its references/ folder beside SKILL.md, into the place where you load skills from. Check that place for your own agent first, and ask me if you are not sure. Do not change anything inside the app bundle.
            """
        }
    }

    var body: some View {
        VPhoneLaunchpadSheet(Text("Install Skill")) {
            VStack(alignment: .leading, spacing: DK.Space.s4) {
                Text("Give this to your coding agent, such as Claude Code, Codex or Grok. It reads the vphone skill from this Mac and installs it where that agent expects skills.")
                    .foregroundStyle(DK.Palette.muted)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let prompt {
                    DKSection(String(localized: "Prompt"), grow: true, card: false) {
                        ScrollView {
                            Text(prompt)
                                .font(DK.Typeface.mono)
                                .foregroundStyle(DK.Palette.ink)
                                .lineSpacing(2)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, DK.Space.s3)
                                .padding(.horizontal, 14)
                        }
                        .background(DK.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: DK.Radius.card, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DK.Radius.card, style: .continuous)
                                .strokeBorder(DK.Palette.line, lineWidth: DK.Metric.hairline),
                        )
                    }
                } else {
                    DKBanner(String(localized: "This copy of Launchpad does not contain the skill."), tone: .info)
                    Spacer(minLength: 0)
                }
            }
            .padding(DKSheetMetrics.horizontalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } accessory: {
            DKButton(DKButtonSpec(String(localized: "Show in Finder"), glyph: .folder, isEnabled: prompt != nil) {
                if let url = Self.skillURL {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            })
        } actions: {
            DKButton(DKButtonSpec(
                copied ? String(localized: "Copied") : String(localized: "Copy Prompt"),
                glyph: copied ? .check : .copy,
                isEnabled: prompt != nil,
            ) {
                guard let prompt else {
                    return
                }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(prompt, forType: .string)
                copied = true
            })
            DKButton(String(localized: "Done"), variant: .primary) { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .frame(width: 520, height: 460)
        .background(DK.Palette.window)
    }
}
