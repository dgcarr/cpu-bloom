"""Static package assertions; complements, does not replace, installed/WACK tests."""
import json
import hashlib
import os
import pathlib
import struct
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile

result = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8-sig"))
with zipfile.ZipFile(result["package"]) as archive:
    names = set(archive.namelist())
    required = {"cpu_bloom.exe", "cpu_bloom_startup.exe", "store-bridge.exe", "java/bin/javaw.exe", "lib/cpu_bloom.jar", "ThirdPartyNotices/binary-inventory.json", "Sources/README.md", "Sources/cpu-bloom-source.zip", "Sources/sources.lock.json", "ThirdPartyNotices/upstream/jna-5.19.1/AL2.0", "ThirdPartyNotices/core-4.5.7/font_ProcessingSansPro-LICENSE.txt"}
    names_normal = {name.replace("\\", "/") for name in names}
    assert required <= names_normal, required - names_normal
    for item in json.loads(archive.read("Sources/sources.lock.json")):
        assert hashlib.sha256(archive.read("Sources/" + item["file"])).hexdigest() == item["sha256"]
    assert not any(any(unused in n for unused in ("kotlin-stdlib", "antlr-", "jssc-", "serial.jar", "annotations-")) for n in names_normal if n.startswith("lib/"))
    assert not any(n.endswith((".mp4", ".pdb", ".obj", ".ps1")) for n in names_normal)
    assert not any("-natives-" in n and "windows-amd64" not in n for n in names_normal)
    assert any(n.startswith("data/orchid/") for n in names_normal)
    assert any(n.startswith("data/poppy/") for n in names_normal)
    manifest = ET.fromstring(archive.read("AppxManifest.xml"))
    nodes = {e.tag.split("}")[-1]: e for e in manifest.iter()}
    assert nodes["StartupTask"].get("Enabled") == "false"
    assert nodes["TargetDeviceFamily"].get("MinVersion") == "10.0.22000.0"
    assert nodes["Capability"].get("Name") == "runFullTrust"
    assert nodes["Identity"].get("ProcessorArchitecture") == "x64"
    for name, size in [("StoreLogo", 50), ("Square44x44Logo", 44), ("Square150x150Logo", 150)]:
        path = next(n for n in names if n.replace("\\", "/") == f"Assets/{name}.png")
        assert struct.unpack(">II", archive.read(path)[16:24]) == (size, size)
bridge = pathlib.Path(result["stage"]) / "store-bridge.exe"
sdk = json.loads((pathlib.Path(__file__).parent / "inputs.lock.json").read_text())["windowsSdk"]
mt = pathlib.Path(os.environ["ProgramFiles(x86)"]) / "Windows Kits/10/bin" / sdk / "x64/mt.exe"
with tempfile.TemporaryDirectory() as temporary:
    for name in ("cpu_bloom.exe", "cpu_bloom_startup.exe", "store-bridge.exe"):
        extracted = pathlib.Path(temporary) / (name + ".xml")
        subprocess.run([str(mt), "-nologo", f"-inputresource:{pathlib.Path(result['stage']) / name};#1", f"-out:{extracted}"], check=True, capture_output=True)
        embedded = ET.parse(extracted)
        assert embedded.find(".//{http://schemas.microsoft.com/SMI/2016/WindowsSettings}dpiAwareness").text == "PerMonitorV2"
        assert embedded.find(".//{urn:schemas-microsoft-com:asm.v3}requestedExecutionLevel").get("level") == "asInvoker"
context = subprocess.run([bridge, "context"], capture_output=True, text=True, check=True)
assert "packaged=false" in context.stdout
assert subprocess.run([bridge, "startup-query"], capture_output=True).returncode == 3
assert subprocess.run([bridge, "unexpected-command"], capture_output=True).returncode == 2
print("PASS: package contents, startup manifest, architecture, icons and helper fail-closed behavior")
