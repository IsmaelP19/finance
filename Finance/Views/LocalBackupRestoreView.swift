//
//  LocalBackupRestoreView.swift
//  Finance
//

import SwiftUI

struct LocalBackupRestoreView: View {
    @Environment(\.dismiss) private var dismiss

    let backups: [LocalRepairBackupService.BackupInfo]
    let onRestore: (LocalRepairBackupService.BackupInfo) -> Void

    @State private var selectedBackup: LocalRepairBackupService.BackupInfo?

    var body: some View {
        NavigationStack {
            Group {
                if backups.isEmpty {
                    ContentUnavailableView(
                        "No hay backups previos",
                        systemImage: "externaldrive.badge.questionmark",
                        description: Text("La app creará un backup local antes de la próxima reparación o restauración.")
                    )
                } else {
                    List {
                        Section {
                            ForEach(backups) { backup in
                                Button {
                                    selectedBackup = backup
                                } label: {
                                    LocalBackupRow(backup: backup)
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            Text("Selecciona una copia para reemplazar los datos actuales")
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Backups locales")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                "Restaurar backup local",
                isPresented: Binding(
                    get: { selectedBackup != nil },
                    set: { isPresented in
                        if !isPresented {
                            selectedBackup = nil
                        }
                    }
                ),
                titleVisibility: .visible
            ) {
                Button("Cancelar", role: .cancel) {}
                Button("Restaurar y crear backup", role: .destructive) {
                    guard let backup = selectedBackup else { return }
                    selectedBackup = nil
                    dismiss()
                    onRestore(backup)
                }
            } message: {
                if let selectedBackup {
                    Text("Se reemplazarán todos los datos actuales por la copia del \(selectedBackup.exportDate.formatted(date: .abbreviated, time: .shortened)). Antes se creará otro backup local del estado actual.")
                }
            }
        }
    }
}

private struct LocalBackupRow: View {
    let backup: LocalRepairBackupService.BackupInfo

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.down.document.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.blue)
                .frame(width: 38, height: 38)
                .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(backup.exportDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)

                Text("Backup previo · \(ByteCountFormatter.string(fromByteCount: backup.fileSize, countStyle: .file))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Abre la confirmación para restaurar esta copia.")
    }
}
