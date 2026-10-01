#!/usr/bin/env python3
"""Generate a SideStore source from a packaged Finance IPA."""

import argparse
import json
import plistlib
import re
import sys
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse


APP_ID = "com.getincouch.Finance"
WIDGET_ID = "com.getincouch.Finance.FinanceWidgetExtension"
SOURCE_ID = "com.getincouch.Finance.sidestore"


def https_url(value: str) -> str:
    parsed = urlparse(value)
    if parsed.scheme != "https" or not parsed.netloc:
        raise argparse.ArgumentTypeError("La URL debe usar HTTPS y tener un host")
    return value


def info_from_ipa(ipa: Path) -> tuple[dict, dict]:
    with zipfile.ZipFile(ipa) as archive:
        app_info = plistlib.loads(archive.read("Payload/Finance.app/Info.plist"))
        widget_info = plistlib.loads(
            archive.read(
                "Payload/Finance.app/PlugIns/FinanceWidgetExtension.appex/Info.plist"
            )
        )
    return app_info, widget_info


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ipa", type=Path, required=True)
    parser.add_argument("--source-url", type=https_url, required=True)
    parser.add_argument("--download-url", type=https_url, required=True)
    parser.add_argument("--icon-url", type=https_url, required=True)
    parser.add_argument("--previous", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    try:
        app_info, widget_info = info_from_ipa(args.ipa)
        if app_info.get("CFBundleIdentifier") != APP_ID:
            raise ValueError(f"Bundle ID inesperado: {app_info.get('CFBundleIdentifier')}")
        if widget_info.get("CFBundleIdentifier") != WIDGET_ID:
            raise ValueError(f"Widget inesperado: {widget_info.get('CFBundleIdentifier')}")
        version = str(app_info["CFBundleShortVersionString"])
        build = str(app_info["CFBundleVersion"])
        widget_version = str(widget_info.get("CFBundleShortVersionString"))
        widget_build = str(widget_info.get("CFBundleVersion"))
        if (widget_version, widget_build) != (version, build):
            raise ValueError("La versión o el build del widget no coinciden con Finance")
        if not re.fullmatch(r"\d+\.\d+\.\d+", version):
            raise ValueError(f"Versión no válida para SideStore: {version}")
        if not re.fullmatch(r"\d+(?:\.\d+)*", build):
            raise ValueError(f"Build no válido: {build}")

        previous_versions = []
        if args.previous and args.previous.exists():
            previous = json.loads(args.previous.read_text(encoding="utf-8"))
            if previous.get("identifier") != SOURCE_ID:
                raise ValueError("La fuente anterior tiene otro identifier")
            previous_app = next(
                app for app in previous["apps"] if app["bundleIdentifier"] == APP_ID
            )
            previous_versions = previous_app["versions"]

        if previous_versions:
            latest = previous_versions[0]
            current_parts = tuple(int(part) for part in version.split("."))
            latest_parts = tuple(int(part) for part in latest["version"].split("."))
            if current_parts < latest_parts:
                raise ValueError("La versión es anterior a la última publicada")
            current_build = tuple(int(part) for part in build.split("."))
            latest_build = tuple(
                int(part) for part in latest.get("buildVersion", "0").split(".")
            )
            if current_parts == latest_parts and current_build < latest_build:
                raise ValueError("El build es anterior al último publicado")

        version_entry = {
            "version": version,
            "buildVersion": build,
            "date": datetime.now(timezone.utc).isoformat(timespec="seconds").replace(
                "+00:00", "Z"
            ),
            "localizedDescription": f"Finance {version} ({build})",
            "downloadURL": args.download_url,
            "size": args.ipa.stat().st_size,
        }
        if app_info.get("MinimumOSVersion"):
            version_entry["minOSVersion"] = app_info["MinimumOSVersion"]

        for old in previous_versions:
            if old["version"] == version and old.get("buildVersion") == build:
                if old["downloadURL"] != args.download_url:
                    raise ValueError("La versión y el build ya existen con otra URL")
                version_entry["date"] = old["date"]
                previous_versions = [
                    entry for entry in previous_versions if entry is not old
                ]
                break

        versions = [version_entry, *previous_versions]
        source = {
            "name": "Finance",
            "identifier": SOURCE_ID,
            "sourceURL": args.source_url,
            "apps": [
                {
                    "name": "Finance",
                    "bundleIdentifier": APP_ID,
                    "developerName": "IsmaelP19",
                    "subtitle": "Finanzas personales en tu dispositivo",
                    "localizedDescription": "Gestiona cuentas, movimientos, presupuestos e inversiones de forma local.",
                    "iconURL": args.icon_url,
                    "version": version,
                    "versionDate": version_entry["date"],
                    "downloadURL": args.download_url,
                    "size": version_entry["size"],
                    "versions": versions,
                }
            ],
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(
            json.dumps(source, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
    except (OSError, KeyError, ValueError, zipfile.BadZipFile, StopIteration) as error:
        print(f"No se pudo generar la fuente: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
