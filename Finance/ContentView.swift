//
//  ContentView.swift
//  Finance
//
//  Created by Ismael Pérez on 11/02/2026.
//

import SwiftUI
import SwiftData

/// Vista raíz de la aplicación con navegación inferior por pestañas.
struct ContentView: View {
    var body: some View {
        TabView {
            AccountListView()
                .tabItem {
                    Label("Inicio", systemImage: "house.fill")
                }

            ChartsView()
                .tabItem {
                    Label("Gráficos", systemImage: "chart.xyaxis.line")
                }

            SettingsView()
                .tabItem {
                    Label("Ajustes", systemImage: "gearshape.fill")
                }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Bank.self, BankAccount.self], inMemory: true)
}
