import SwiftUI

struct QRCodeContentForm: View {
    let kind: QRContentKind
    @Binding var fields: QRContentFields
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var addressExpanded = false
    @State private var passwordVisible = false
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            switch kind {
            case .freeText: EmptyView()
            case .url:
                field("URL",$fields.url,"https://example.com",id:"url")
                Text("Include https://. International characters are encoded for QR reader compatibility.").font(.caption).foregroundStyle(.secondary)
            case .contact:
                field("First name",$fields.firstName,id:"first-name")
                field("Last name",$fields.lastName,id:"last-name")
                field("Organization",$fields.organization,id:"organization")
                field("Job title",$fields.jobTitle,id:"job-title")
                field("Phone",$fields.contactPhone,id:"contact-phone")
                field("Email",$fields.contactEmail,id:"contact-email")
                field("Website",$fields.contactWebsite,"https://example.com",id:"website")
                DisclosureGroup("Address",isExpanded:$addressExpanded) {
                    VStack(spacing:10) {
                        field("Street",$fields.street,id:"street"); field("City",$fields.city,id:"city")
                        field("Region",$fields.region,id:"region"); field("Postal code",$fields.postalCode,id:"postal")
                        field("Country",$fields.country,id:"country")
                    }.padding(.top,8)
                }
                Text("vCard 3.0 · at least a first or last name is required.").font(.caption).foregroundStyle(.secondary)
            case .wifi:
                field("Network name (SSID)",$fields.ssid,id:"ssid")
                Picker("Security",selection:$fields.security) { ForEach(QRWiFiSecurity.allCases,id:\.self) { Text($0.title).tag($0) } }.pickerStyle(.menu)
                if fields.security != .open {
                    VStack(alignment:.leading,spacing:4) {
                        HStack { Text("Password").font(.caption).foregroundStyle(.secondary); Spacer(); Toggle("Show password",isOn:$passwordVisible).font(.caption) }
                        Group {
                            if passwordVisible { TextField("Network password",text:$fields.password) }
                            else { SecureField("Network password",text:$fields.password) }
                        }.textFieldStyle(.roundedBorder).accessibilityLabel("Wi-Fi password").accessibilityIdentifier("qr-field-password")
                    }
                }
                Toggle("Hidden network",isOn:$fields.hiddenNetwork)
                Text("Personal WPA/WPA2, WEP or open networks. No connection is made.").font(.caption).foregroundStyle(.secondary)
            case .email:
                field("To",$fields.emailAddress,"name@example.com",id:"email")
                field("Subject",$fields.emailSubject,id:"subject")
                bodyField("Message",$fields.emailBody,id:"email-body")
            case .phone:
                field("Phone number",$fields.phoneNumber,"+420 123 456 789",id:"phone")
                Text("Include + and the country code. Visual separators are removed from the encoded number.").font(.caption).foregroundStyle(.secondary)
            case .sms:
                field("Phone number",$fields.smsNumber,"+420 123 456 789",id:"sms-phone")
                bodyField("Message",$fields.smsBody,id:"sms-body")
                Text("Uses the standard sms: URI. Message prefill support varies by scanner and messaging app.").font(.caption).foregroundStyle(.secondary)
            }
        }.animation(reduced || ProcessInfo.processInfo.arguments.contains("--reduce-motion") ? nil : .easeInOut(duration:0.2),value:addressExpanded)
    }
    private func field(_ title: String,_ value: Binding<String>,_ hint: String = "",id: String) -> some View {
        VStack(alignment:.leading,spacing:4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(hint,text:value).textFieldStyle(.roundedBorder).accessibilityLabel(title).accessibilityIdentifier("qr-field-"+id)
                #if os(iOS)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                #endif
        }
    }
    private func bodyField(_ title: String,_ value: Binding<String>,id: String) -> some View {
        VStack(alignment:.leading,spacing:4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title,text:value,axis:.vertical).lineLimit(3...6).textFieldStyle(.roundedBorder)
                .accessibilityLabel(title).accessibilityIdentifier("qr-field-"+id)
                #if os(iOS)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                #endif
        }
    }
}
