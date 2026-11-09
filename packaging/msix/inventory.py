"""Write a binary inventory and extract upstream notices without executing JARs."""
import hashlib
import json
import pathlib
import re
import sys
import zipfile

stage = pathlib.Path(sys.argv[1])
notices = stage / "ThirdPartyNotices"
notices.mkdir(exist_ok=True)
inventory = []
for jar in sorted((stage / "lib").glob("*.jar")):
    inventory.append({"file": "lib/" + jar.name, "sha256": hashlib.sha256(jar.read_bytes()).hexdigest()})
    with zipfile.ZipFile(jar) as archive:
        for name in archive.namelist():
            leaf = pathlib.PurePosixPath(name).name
            if not name.endswith("/") and re.search(r"(?i)(^|[-_.])(license|notice|copying|copyright)([-_.]|$)", leaf):
                destination = notices / jar.stem / name.replace("/", "_").replace("\\", "_")
                destination.parent.mkdir(exist_ok=True)
                destination.write_bytes(archive.read(name))
(notices / "binary-inventory.json").write_text(json.dumps(inventory, indent=2) + "\n")
