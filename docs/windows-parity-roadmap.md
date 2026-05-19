# Windows Parity Roadmap

## Goal

Bring the Windows desktop flow as close as possible to the macOS app in behavior, workflow visibility, and maintenance model, while keeping platform-specific networking code isolated.

## Current state

Shared pieces already in place:

- shared config contract in `core/config.py`
- shared workflow and summary models in `core/models.py`
- shared proxy-link parsing and Xray config generation in `core/proxy_links.py`
- shared runtime orchestration in `core/runtime.py`
- Windows desktop shell in `desktop/main.py`
- Windows build and package scripts in `scripts/windows`

Windows pieces already implemented:

- local bypass listener
- Xray startup path
- optional system proxy automation
- connectivity probe through local HTTP proxy
- restore of previous Windows proxy settings on cleanup

Known gaps versus macOS:

- no tunnel mode
- no live traffic cards for upload / download / total usage
- no localized Windows UI yet
- no bundled signed Windows release artifact yet
- no diagnostic dump parity
- no helper/Xray log surfacing comparable to the macOS app

## Recommended implementation order

1. Windows `Proxy` mode completion

- add richer runtime telemetry
- surface HTTP/SOCKS/Xray logs in the desktop UI
- add diagnostic dump export
- harden startup and cleanup edge cases

2. Windows UI parity

- match macOS card layout more closely
- add localized copy
- add details/workflow expansion behavior closer to macOS
- add traffic summary cards

3. Windows packaging parity

- define signed release pipeline
- bundle `xray.exe` as a first-class release artifact
- add checksums and reproducible package naming

4. Windows `Tunnel` mode feasibility

- choose the platform adapter
- define route and cleanup rules
- keep the shared runtime contract stable while adding the Windows tunnel implementation

## Architecture rule

The repo should continue to move toward this split:

- shared domain and workflow contracts in `core/`
- platform adapters in `backends/` and platform-specific services
- UI layers that consume the same runtime contract instead of duplicating business logic
