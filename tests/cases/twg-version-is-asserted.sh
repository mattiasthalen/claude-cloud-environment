#!/bin/bash
# The carve-out is gone: twg is pinnable where acli was not, so its reported
# version is compared against the lockfile the way every pinned tool's is. A twg
# already present at a version nobody chose fails verification, carrying both
# the version found and the version expected — where acli in the same position
# used to pass with whatever it printed.
#
# The presence guard still leaves the impostor alone — it deliberately does not
# check versions and does not self-heal — and verification is what surfaces the
# mismatch.
# tier: quick
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

pin=$(harness_pin TWG_VERSION)

harness_pre <<'PRE'
cat > /usr/local/bin/twg <<'STUB'
#!/bin/bash
echo "0.0.1"
STUB
chmod +x /usr/local/bin/twg
PRE

harness_run twg

assert_status 1
assert_output_contains "✗ twg 0.0.1, expected ${pin}"
assert_output_contains "step(s) failed:"
assert_output_contains "  - verify twg"

# The presence guard held, so nothing was downloaded and nothing installed.
assert_output_lacks "==> release install"
assert_output_lacks "==> apt-get install"
