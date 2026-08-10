#!/bin/bash
# A tool present at the wrong version is neither silently accepted nor silently
# reinstalled. The presence guard leaves it alone — it deliberately does not
# check versions and does not self-heal — and verification is what surfaces the
# mismatch, carrying both the version found and the version expected.
# tier: quick
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

pin=$(harness_pin KUBECTL_VERSION)

harness_pre <<'PRE'
cat > /usr/local/bin/kubectl <<'STUB'
#!/bin/bash
echo "Client Version: v1.30.0"
STUB
chmod +x /usr/local/bin/kubectl
PRE

harness_run kubectl

assert_status 1
assert_output_contains "✗ kubectl v1.30.0, expected v${pin%%-*}"
assert_output_lacks "==> apt-get install"
assert_output_contains "step(s) failed:"
