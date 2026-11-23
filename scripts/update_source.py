"""Adds a build to source.json in the public releases repo through the GitHub contents API.

usage: update_source.py OWNER/REPO path/to/App/Info.plist path/to/App.ipa "release notes"
"""
import base64, datetime, json, os, plistlib, subprocess, sys

repo, info_path, ipa_path, notes = sys.argv[1:5]
ICON = f"https://raw.githubusercontent.com/{repo}/main/icon.png"


def gh(*args, input=None):
    return subprocess.run(["gh", *args], input=input, capture_output=True, text=True, check=True).stdout


meta = json.loads(gh("api", f"repos/{repo}/contents/source.json"))
source = json.loads(base64.b64decode(meta["content"]))
info = plistlib.load(open(info_path, "rb"))
build = info["CFBundleVersion"]
entry = {
    "version": info["CFBundleShortVersionString"],
    "buildVersion": build,
    "date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "localizedDescription": notes,
    "downloadURL": f"https://github.com/{repo}/releases/download/build-{build}/{os.path.basename(ipa_path)}",
    "size": os.path.getsize(ipa_path),
    "minOSVersion": info["MinimumOSVersion"],
}

if not source["apps"]:
    source["apps"].append({
        "name": "Gamepad",
        "bundleIdentifier": info["CFBundleIdentifier"],
        "developerName": "S0ya13",
        "subtitle": "Геймпад для Mac по Wi-Fi",
        "localizedDescription": "Два плавающих стика и восемь кнопок. Управляет играми на Mac по UDP в локальной сети; на Mac нужен MacServer.",
        "iconURL": ICON,
        "tintColor": "#FF9500",
        "category": "utilities",
        "versions": [],
    })
app = source["apps"][0]
if any(v["buildVersion"] == build for v in app["versions"]):
    sys.exit(f"Build {build} is already in source.json.")
app["versions"].insert(0, entry)
# Legacy flat fields: some clients read only these.
app.update(version=entry["version"], versionDate=entry["date"], downloadURL=entry["downloadURL"], size=entry["size"])

gh("api", "-X", "PUT", f"repos/{repo}/contents/source.json", "--input", "-", input=json.dumps({
    "message": f"build {build}",
    "sha": meta["sha"],
    "content": base64.b64encode(json.dumps(source, ensure_ascii=False, indent=2).encode()).decode(),
}))
print(f"source.json: build {build} ({entry['version']})")
