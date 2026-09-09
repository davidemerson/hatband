# Security

Report a vulnerability privately through GitHub:
https://github.com/davidemerson/hatband/security/advisories/new

The site's [`security.txt`](site/.well-known/security.txt) points here.

The assets, the adversaries this is built against, what mitigates them and what
is deliberately out of scope are in [the README](README.md#security). Read that
first: it will tell you whether what you have found is a finding.

Hatband has no server and no account, so there is no infrastructure to test and
nothing of anyone's to breach but their own phone. What is in scope is the app,
the format library under `Packages/HatbandCore`, the page under `site/`, and the
wire format in `spec/`.

Supported: the current release. There is no back-porting.
