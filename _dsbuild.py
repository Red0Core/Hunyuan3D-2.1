"""Build deepspeed from source on Windows.

Why this exists
---------------
deepspeed's setup.py has a Windows branch:

    scripts = ['bin/deepspeed.bat', 'bin/ds', 'bin/ds_report.bat', 'bin/ds_report']

but the sdist ships only the Linux launchers - no .bat files at all. So
`pip install deepspeed` dies with:

    running build_scripts
    error: [Errno 2] No such file or directory: 'bin\\deepspeed.bat'

That is an upstream packaging bug, not a problem with your machine. This
script downloads the sdist, writes the missing launchers, then installs it.

Called by Build.bat, which must already have set CUDA_HOME / DS_BUILD_OPS=0.
"""

import json
import os
import subprocess
import sys
import tarfile
import tempfile
import urllib.request

VERSION = os.environ.get("DS_VERSION", "0.19.5")


def sdist_url(version):
    api = "https://pypi.org/pypi/deepspeed/%s/json" % version
    with urllib.request.urlopen(api, timeout=60) as r:
        data = json.load(r)
    for f in data["urls"]:
        if f["packagetype"] == "sdist":
            return f["url"]
    raise RuntimeError("no sdist found for deepspeed %s" % version)


def main():
    if not os.environ.get("CUDA_HOME"):
        print("  CUDA_HOME is not set - run this from Build.bat, not directly.")
        return 1

    tmp = tempfile.mkdtemp(prefix="ds_build_")
    print("  work dir: %s" % tmp, flush=True)

    url = sdist_url(VERSION)
    tgz = os.path.join(tmp, "deepspeed.tar.gz")
    print("  downloading %s" % url.split("/")[-1], flush=True)
    urllib.request.urlretrieve(url, tgz)

    with tarfile.open(tgz) as t:
        t.extractall(tmp)
    src = os.path.join(tmp, "deepspeed-%s" % VERSION)
    if not os.path.isdir(src):
        print("  extracted layout unexpected"); return 1

    # write the launchers setup.py expects but the sdist omits
    made = []
    for name, target in (("deepspeed.bat", "deepspeed"), ("ds_report.bat", "ds_report")):
        p = os.path.join(src, "bin", name)
        if not os.path.exists(p):
            with open(p, "w", newline="\r\n") as f:
                f.write('@echo off\npython "%%~dp0%s" %%*\n' % target)
            made.append(name)
    print("  created missing launchers: %s" % (", ".join(made) or "none needed"), flush=True)

    print("  installing (DS_BUILD_OPS=%s)..." % os.environ.get("DS_BUILD_OPS", ""), flush=True)
    rc = subprocess.call([sys.executable, "-m", "pip", "install", src, "--no-build-isolation"])
    return rc


if __name__ == "__main__":
    sys.exit(main())
