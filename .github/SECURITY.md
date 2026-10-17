# Security Policy

The **Tachyon** project takes the security, reliability, and privacy of its users very seriously. This document outlines our security policies, supported versions, and procedures for reporting vulnerabilities responsibly.

---

## 🛡️ Supported Versions

We provide security updates and patches for the following versions:

| Version | Supported          | Status                              |
| :------ | :----------------- | :---------------------------------- |
| 0.1.x   | :white_check_mark: | Currently active development (main) |
| < 0.1.0 | :x:                | Unsupported                         |

We recommend all users and packagers always update to the latest stable release or build from the latest commit on `main`.

---

## 🔍 Security Architecture & Threat Model

Tachyon is designed from the ground up with defensive programming principles:

1. **Zero External CLI Subprocesses:**
   - Tachyon **never** invokes external shell tools (`ffmpeg`, `ffprobe`, etc.) via `Process.run`. This eliminates an entire class of shell injection and command execution vulnerabilities.
2. **Robust Native FFI Interop:**
   - Audio decoding and DSP pipelines use low-level C FFI via [`miniaudio_player`](https://pub.dev/packages/miniaudio_player). Memory buffers and audio streams are bounds-checked and managed defensively.
3. **Isolate Sandboxing for Media Parsing:**
   - Tag extraction (`haudiotagger`) and cover extraction occur inside isolated worker isolates (`Isolate.spawn`). Any parser failure or abnormal memory consumption in malformed media files does not crash or destabilize the main UI process.
4. **Defensive Network Operations:**
   - Remote lyrics resolution (`lrclib.net`, `lyrics.ovh`) uses secure HTTPS endpoints only, enforces strict timeouts, applies rate-limiting logic, and strips untrusted input before query dispatch.

---

## 🚨 Reporting a Vulnerability

If you discover a security vulnerability in Tachyon, please **DO NOT open a public issue or discuss it in public chat channels**. Doing so could put users at risk before a fix is ready.

### How to Report

Please report vulnerabilities through one of the following private channels:

1. **GitHub Private Vulnerability Reporting (Preferred):**
   - Navigate to the [Security tab](https://github.com/chomusuke-mk/tachyon/security) of the Tachyon repository.
   - Click on **"Report a vulnerability"** to open a private draft advisory.
2. **Direct Security Email:**
   - Send an encrypted or plain email to the maintainer: **<7k9mc4urn@mozmail.com>**
   - Use the subject line: `[SECURITY] Potential Vulnerability in Tachyon - <Brief Summary>`.

### What to Include in Your Report

To help us triage and resolve the issue quickly, please include:

- A clear description of the vulnerability and its potential security impact.
- Affected components (e.g., `miniaudio_player` FFI, metadata worker isolates, lyrics network client).
- Step-by-step instructions or scripts to reproduce the issue.
- A minimal Proof of Concept (PoC) or sample audio file (if the issue is triggered by malformed media tags).
- Affected platform(s) and environment details (Linux, Windows, Android, architecture).

---

## ⏱️ Response & Disclosure Timelines

When a vulnerability report is received, the maintainers will:

- **Acknowledge Receipt:** Respond within **48 hours** confirming that the report has been received.
- **Triage & Assessment:** Verify the vulnerability and evaluate its severity within **5 business days**.
- **Remediation:** Develop and test a security patch in a private repository or advisory draft.
- **Release & Advisory:** Publish a coordinated release with a detailed security advisory crediting the reporter (unless anonymity is requested).

---

## 🏅 Hall of Fame & Acknowledgments

We greatly appreciate the efforts of security researchers and open-source contributors who identify vulnerabilities responsibly. Legitimate security reports will be publicly credited in our release notes and repository advisories.
