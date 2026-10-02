import SwiftUI

struct ExpenseAutomationGuide: View {
    @Environment(\.openURL) private var openURL
    @State private var method = Method.wallet
    @State private var cannotOpenShortcuts = false

    private enum Method: String, CaseIterable {
        case wallet = "Apple Pay"
        case backTap = "Back Tap"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Less typing. Every expense.")
                    .font(.system(size: 28, weight: .bold))
                Text("Start an expense from Wallet or a tap on the back of your iPhone. Review the details in Settlr and save.")
                    .foregroundStyle(Theme.muted)
                Picker("Method", selection: $method) {
                    ForEach(Method.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                SectionCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("YOU’LL NEED", systemImage: "checkmark.circle")
                            .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                        Text("An iPhone running iOS 17 or newer")
                        Text(method == .wallet ? "A payment card added to Apple Wallet" : "An iPhone that supports Back Tap")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if method == .wallet {
                    step(1, "Open Shortcuts", "Open Apple’s Shortcuts app and select the Automation tab.", icon: "square.grid.3x3")
                    step(2, "Create an automation", "Tap + (or New Automation). Choose Wallet or Transaction, depending on your iOS version.", icon: "plus.circle")
                    step(3, "Choose your cards", "Select the payment cards to track. Choose Run Immediately and turn off Notify When Run if shown. Tap Next.", icon: "creditcard")
                    step(4, "Add the Wallet action", "Choose a blank automation, search for Settlr, and add “Wallet Payment → Settlr”. Use this action for Wallet payments; Quick Expense opens a blank form.", icon: "bolt")
                    step(5, "Connect the transaction", "Tap Amount and select the transaction’s Amount variable. Repeat for Merchant. Under the action’s additional options, you can also connect Card or Pass and Name. Use Select Variable and the transaction input if the variables aren’t visible.", icon: "slider.horizontal.3")
                    step(6, "Review, then save", "Tap Done. When the automation runs, Settlr opens an expense draft. Check the amount, workspace, category and payment method, then tap Add Expense. Missing Wallet details can be entered manually.", icon: "checkmark.circle")
                } else {
                    step(1, "Create a shortcut", "In Shortcuts, tap +, search for Settlr and add “Quick Expense”. Name and save the shortcut.", icon: "plus.circle")
                    step(2, "Assign Back Tap", "Open iPhone Settings → Accessibility → Touch → Back Tap. Choose Double Tap or Triple Tap, then select your saved shortcut.", icon: "hand.tap")
                    step(3, "Tap and log", "Tap the back of your iPhone to open Settlr. Enter the amount and description, choose a category and payment method, then save.", icon: "checkmark.circle")
                }

                Button {
                    openURL(URL(string: "shortcuts://")!) { accepted in
                        cannotOpenShortcuts = !accepted
                    }
                } label: {
                    Label("Open Shortcuts", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())

                Text("Set up the automation yourself in Shortcuts. You may need to unlock your iPhone to open Settlr. Wallet details depend on the card and transaction; this does not import past purchases or save expenses without your review.")
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
            .padding(20)
            .padding(.bottom, 24)
        }
        .background(Theme.bg)
        .navigationTitle("Expense Shortcuts")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Couldn’t open Shortcuts", isPresented: $cannotOpenShortcuts) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Open or install Apple’s Shortcuts app, then follow the steps above.")
        }
    }

    private func step(_ number: Int, _ title: String, _ detail: String, icon: String) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Text("\(number)")
                        .font(.headline).foregroundStyle(Theme.accent)
                        .frame(width: 30, height: 30)
                        .background(Theme.accent.opacity(0.12), in: Circle())
                    Label(title, systemImage: icon).font(.headline)
                }
                Text(detail).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
