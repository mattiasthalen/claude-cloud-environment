# Helm is pinned on the Helm 4 line, not Helm 3

Helm 3 is still maintained and is what most clusters are driven with today, so a
reader finding `HELM_VERSION=4.x` in the lockfile would reasonably assume it was
a version roll that overshot. It is not: this script provisions a fresh box per
environment and pins nothing else that Helm's major touches — no charts, no
plugins, no `helm` Go library consumer — so the compatibility cost that keeps
most estates on 3 does not land here, and starting an environment on the older
major would only mean carrying a migration later.

## Consequences

A chart or plugin that a session brings with it has to be one Helm 4 accepts,
and this box offers no Helm 3 alongside it to fall back to. An
environment that needs the older major is a lockfile change and a second pin,
not a flag on the existing one — the same shape as any other version decision
here.
