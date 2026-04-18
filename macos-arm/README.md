# macOS build

In پوشه alan faghat scaffold nist; masir e native proxy baraye macOS baraye `arm64` va `x86_64` ham shoru shode.

hadaf e in scaffold:

- host app e macOS dashte bashim
- local listener e native shabih noskhe Windows dashte bashim
- `PacketTunnelProvider` dashte bashim ta backend e mac ba `Network Extension` shoru beshe
- project ro ba `xcodegen` tolid konim
- debug/release build e joda baraye `arm64` va `x86_64` dashte bashim

### che chiz tamam shode

- project spec e `XcodeGen`
- app e sade e SwiftUI
- extension e `PacketTunnelProvider`
- script e generate/build baraye `arm64` va `x86_64`
- tunnel manager dar host app
- shared config/message protocol beyn app va extension
- provider status query az tariqe `sendProviderMessage`
- native local proxy ruye `listenPort`
- relay e socket dar host app
- `libpcap` bridge baraye monitor/inject e packet ha
- builder/parsing e packet baraye fake TLS ClientHello injection

### che chiz baqi mande

- entitlements va signing e dorost
- test e runtime ruye mac ba dastresi root/admin
- hardening e logic e bypass ruye interface haye mokhtalef
- barresi دقیق‌تر e path e `PacketTunnelProvider` ya helper e privileged baraye distribution tamiz

### estefade

```bash
cd macos-arm
./generate_xcode_project.sh
./build_arm_debug.sh
./build_x86_64_debug.sh
```

ya generic:

```bash
cd macos-arm
./build_debug.sh arm64
./build_debug.sh x86_64
./build_release.sh arm64
./build_release.sh x86_64
./package_release.sh arm64
./package_release.sh x86_64
```

baraye run e helper e واقعی ba dastresi root:

```bash
cd macos-arm
./run_proxy_helper.sh ../config.json
```

ya mostaghim:

```bash
sudo ./build/$(uname -m)/Debug/sni-proxy-helper --config ../config.json
```

baraye kam o ziad kardan log:

```json
{
  "LOG_LEVEL": "info"
}
```

meghdar haye mojaz:

- `debug`: hame chiz, monaseb e debug e packet
- `info`: event haye asli mesl start/stop/bypass ready
- `error`: faghat خطاها

### note

host app alan mitune config ro save kone, native proxy ro start/stop kone, tunnel manager ro ham negah dare, va az extension status begire. Bypass e mac alan ruye local listener + `libpcap` monitor/inject chalide shode. Baraye run e واقعی, app bayad ba dastresi root/admin ejra beshe چون capture/inject e packet bedune in dastresi momken nist. `PacketTunnelProvider` hanuz negah dashte shode ta phase ba’di baraye packaging/signing va control plane tameez tar dashte bashim.
