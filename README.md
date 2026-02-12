# Finance (iOS)

![iOS](https://img.shields.io/badge/iOS-17%2B-0A84FF)
![Swift](https://img.shields.io/badge/Swift-6-F05138)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-0A84FF)
![Persistence](https://img.shields.io/badge/Persistence-SwiftData-34C759)
![Privacy](https://img.shields.io/badge/Data-Local%20Only-111111)

Aplicacion iOS para gestionar patrimonio financiero personal de forma local: cuentas bancarias, saldos y analitica visual.

## Capturas

![Inicio](docs/screenshots/home.png)
![Graficos](docs/screenshots/charts.png)
![Ajustes](docs/screenshots/settings.png)


## Objetivo

- Llevar control manual de saldos por cuenta y banco
- Ver patrimonio total y desglose por tipo de cuenta
- Mantener privacidad total (sin backend ni sincronizacion externa)

## Stack tecnico

- SwiftUI
- SwiftData
- Swift Charts
- Xcode (iOS 17+)

## Funcionalidades actuales

- Gestion de cuentas bancarias
  - Alta, edicion y eliminacion de cuentas
  - Tipos de cuenta (corriente, ahorro, inversion, etc.)
  - Saldos con formato monetario consistente (`1.234,56 €`)
- Gestion de bancos
  - Entidad dinamica (no hardcodeada)
  - Crear, editar y eliminar bancos
  - Banco con icono y color personalizado
- Dashboard (Inicio)
  - Tarjeta de patrimonio total
  - Tarjeta de patrimonio por tipo
  - Listado agrupado por tipo de cuenta
- Graficos
  - Donut de patrimonio por tipo
  - Barras de saldo por banco
  - Tarjetas de resumen rapido
- Ajustes de datos
  - Exportar datos a JSON
  - Importar datos (mantener o reemplazar datos actuales)
  - Eliminar todos los datos con confirmacion
- App Icon
  - Variantes light/dark/tinted

## Privacidad y RGPD

- Sin llamadas de red para datos financieros
- Sin APIs de bancos
- Sin analitica de terceros
- Persistencia local en dispositivo mediante SwiftData
- Export/import manual controlado por el usuario

## Estructura del proyecto

```text
Finance/
  README.md
  docs/
    screenshots/
      home.png
      charts.png
      settings.png
  FinanceApp.swift
  ContentView.swift
  Models/
    AccountType.swift
    Bank.swift
    BankAccount.swift
    BankColor.swift
    BankIcon.swift
  Views/
    AccountListView.swift
    AddAccountView.swift
    AccountDetailView.swift
    BankManagementView.swift
    ChartsView.swift
    SettingsView.swift
    Charts/
      PatrimonyPieChart.swift
      BalanceByBankBarChart.swift
    Components/
      AccountRowView.swift
      TotalBalanceCard.swift
      BalanceByTypeCard.swift
  Services/
    DataExportService.swift
  Utilities/
    CurrencyFormatter.swift
```

## Ejecutar en local

1. Abrir `Finance.xcodeproj` en Xcode
2. Seleccionar un simulador iOS
3. `Cmd + R`

Si cambias modelos de SwiftData y hay inconsistencias de esquema en pruebas:

- `Product > Clean Build Folder`
- Borrar la app del simulador
- Ejecutar de nuevo

## Formato de numeros

La aplicacion usa este formato monetario:

- Separador de miles: `.`
- Separador decimal: `,`
- Ejemplo: `12.345,67 €`

## Roadmap (proximos pasos)

- Movimientos (gastos/ingresos)
- Categorias por movimiento
- Filtros temporales en graficos
- Backups versionados

---

Proyecto personal en evolucion. Enfocado en simplicidad, privacidad y control local de datos.
