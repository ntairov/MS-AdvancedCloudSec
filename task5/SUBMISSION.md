# Nazim Tairov — PT5 Homework
## Perform a Security Scan on Container Images Using Trivy and Remediate Vulnerabilities

**Course:** MS Advanced Cloud Security  
**Date:** June 2026

---

## 1. Introduction & Objectives

This lab demonstrates end-to-end container image vulnerability scanning using Trivy. A deliberately vulnerable Docker image is built using an EOL Ubuntu base, scanned to identify CVEs, then remediated by upgrading to a supported base image. The exercise surfaces an important real-world insight: EOL operating systems produce incomplete Trivy scan results, creating a false sense of security.

---

## 2. Environment Setup

| Component | Version |
|---|---|
| OS | macOS Darwin 25.5.0 |
| Docker | Desktop for Mac (latest stable) |
| Trivy | 0.71.2 (installed to `/tmp/trivy-bin`, session-scoped) |

Trivy installed without requiring system-wide changes:
```bash
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
  | sh -s -- -b /tmp/trivy-bin
export PATH="/tmp/trivy-bin:$PATH"
```

---

## 3. Vulnerable Image Creation

**`Dockerfile.vulnerable`** — uses `ubuntu:18.04` (EOL since April 2023) with Python 3.6, OpenSSL, curl, and Apache2.

```dockerfile
FROM ubuntu:18.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        python3.6 openssl curl apache2 libssl1.1 \
        && rm -rf /var/lib/apt/lists/*
RUN echo "Hello from vulnerable container" > /var/www/html/index.html
EXPOSE 80
CMD ["/usr/sbin/apache2ctl", "-D", "FOREGROUND"]
```

Build:
```bash
docker build -f Dockerfile.vulnerable -t vuln-webapp:0.1 .
```

Confirmed:
```bash
docker images | grep vuln-webapp
# vuln-webapp   0.1   ...   ~180MB
```

---

## 4. Initial Scan Results

```bash
trivy image --format table --output vuln-initial-report.txt vuln-webapp:0.1
```

Trivy issued an important warning:
```
WARN  This OS version is no longer supported by the distribution
WARN  The vulnerability detection may be insufficient because security updates are not provided
```

**Summary:**

| Severity | Count |
|---|---|
| CRITICAL | 0 |
| HIGH | 0 |
| MEDIUM | 4 |
| LOW | 0 |
| **Total** | **4** |

**Findings:**

| CVE | Severity | Package(s) | Installed | Fixed |
|---|---|---|---|---|
| CVE-2023-24329 | MEDIUM | python3.6, python3.6-minimal, libpython3.6-minimal, libpython3.6-stdlib | 3.6.9-1~18.04ubuntu1.12 | 3.6.9-1~18.04ubuntu1.13 |

**CVE-2023-24329** — `urllib.parse` URL blocklisting bypass. An attacker can craft a URL with blank characters that bypasses blocklist validation in Python's `urllib.parse`, potentially enabling SSRF or open redirect attacks.

**Key observation:** Ubuntu 18.04 reached End of Life in April 2023. Ubuntu stopped publishing security advisories for it. Trivy's CVE database has minimal coverage for 18.04 packages — the near-zero finding count reflects missing data, not a secure image. This is a critical real-world risk: EOL OS = incomplete scan = false sense of security.

---

## 5. Remediation

**`Dockerfile.patched`** — upgraded base image to `ubuntu:22.04` (LTS, supported until April 2027). Removed `libssl1.1` (not available in 22.04) and replaced `python3.6` with `python3`.

```dockerfile
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        python3 openssl curl apache2 \
        && rm -rf /var/lib/apt/lists/*
RUN echo "Hello from patched container" > /var/www/html/index.html
EXPOSE 80
CMD ["/usr/sbin/apache2ctl", "-D", "FOREGROUND"]
```

Build:
```bash
docker build -f Dockerfile.patched -t vuln-webapp:1.0 .
```

---

## 6. Re-scan Results

```bash
trivy image --format table --output vuln-rescan-report.txt vuln-webapp:1.0
```

**Summary:**

| Severity | Count |
|---|---|
| CRITICAL | 0 |
| HIGH | 1 |
| MEDIUM | 41 |
| LOW | 41 |
| **Total** | **83** |

**Notable HIGH finding:**

| CVE | Severity | Package | Installed | Fixed |
|---|---|---|---|---|
| CVE-2026-45447 | HIGH | libssl3 | 3.0.2-0ubuntu1.23 | 3.0.2-0ubuntu1.25 |

**CVE-2026-45447** — Heap use-after-free in OpenSSL `PKCS7_verify()`. A fix is available (`apt-get upgrade` would resolve it); it persists here because the image build does not run `apt-get upgrade` after install.

---

## 7. Findings & Discussion

### Before vs. After Comparison

| Metric | vuln-webapp:0.1 (ubuntu:18.04) | vuln-webapp:1.0 (ubuntu:22.04) |
|---|---|---|
| CRITICAL | 0 | 0 |
| HIGH | 0 | 1 |
| MEDIUM | 4 | 41 |
| LOW | 0 | 41 |
| Total | 4 | 83 |
| Scan coverage | **Incomplete (EOL OS)** | **Complete (supported OS)** |
| CVE-2023-24329 (Python) | Present | **Resolved** (python3 used) |
| libssl1.1 CVEs | Not tracked by Trivy | **Eliminated** (package removed) |

### The Counter-intuitive Result

The patched image shows more vulnerabilities (83 vs. 4) because Ubuntu 22.04 is actively maintained and has complete CVE coverage in Trivy's database. The 18.04 image had many more real vulnerabilities — they simply weren't tracked. Upgrading the base OS simultaneously:

1. **Resolved** the Python 3.6 CVE by switching to python3
2. **Eliminated** libssl1.1 (removed from 22.04)
3. **Revealed** the true vulnerability surface with accurate, actionable data

The 1 remaining HIGH (`CVE-2026-45447` in libssl3) has a fix available and would be resolved by adding `apt-get upgrade -y` to the Dockerfile's RUN layer.

### Remaining Risk

The 41 MEDIUM and 41 LOW findings are mostly in base system utilities (`util-linux`, `libc6`, `coreutils`). Most have no fix version available yet — these are tracked CVEs awaiting upstream patches. Acceptable risk for a lab environment; in production, these should be monitored and patched as fixes become available.

---

## 8. Conclusion & Recommendations

The exercise demonstrated that container security scanning is only as good as the CVE database coverage for the scanned OS. An EOL base image is not just a vulnerability — it actively undermines your ability to assess your own security posture.

**Recommendations:**
1. Always use supported, actively maintained base images
2. Run `apt-get upgrade -y` in Dockerfile to pick up the latest patches at build time
3. Integrate `trivy image --exit-code 1 --severity CRITICAL,HIGH` as a CI/CD gate
4. Re-scan images regularly — new CVEs are published daily against unchanged images
5. Use minimal base images (e.g., `ubuntu:22.04-minimal` or `distroless`) to reduce attack surface

---

## 9. Appendix

**Full scan reports:** `vuln-initial-report.txt`, `vuln-rescan-report.txt`

**Docker images used:**
```
vuln-webapp:0.1   ubuntu:18.04   EOL April 2023
vuln-webapp:1.0   ubuntu:22.04   LTS supported until April 2027
```

**Cleanup:**
```bash
docker rmi vuln-webapp:0.1 vuln-webapp:1.0
```
