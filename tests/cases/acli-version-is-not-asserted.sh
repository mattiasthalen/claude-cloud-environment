#!/bin/bash
# The carve-out, pinned. acli is the one tool whose reported version is
# deliberately not compared against anything: upstream publishes no pin, and an
# assertion against a moving upstream would turn any acli release into a
# session-blocking failure for every environment that requested it.
#
# An acli already present at a version nobody chose therefore passes — where
# kubectl in the same position fails verification (see
# wrong-version-fails-verification). The row carries what the binary reported
# and no expected-version text.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

harness_pre <<'PRE'
cat > /usr/local/bin/acli <<'STUB'
#!/bin/bash
echo "acli version 0.0.1-fromsomewhereelse"
STUB
chmod +x /usr/local/bin/acli
PRE

harness_run acli

assert_status 0
assert_output_contains "✓ acli acli version 0.0.1-fromsomewhereelse"
assert_output_lacks "expected"
assert_output_lacks "step(s) failed:"

# The presence guard held, so no repository was configured and no apt ran.
assert_output_lacks "==> repository setup"
assert_output_lacks "==> apt-get install"
