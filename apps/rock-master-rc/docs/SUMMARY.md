# Rock Master RC: How It Works and Our Custom App

## 1. How the car and remote work

The Wonder Toys Rock Master is controlled by a small chip that drives two motors, one for driving and one for steering. It has two separate radios:

| Radio | Used by | Details |
|---|---|---|
| Private 2.4 GHz link | Handheld remote | About 50 m range. It isn't Wi-Fi or Bluetooth, so a phone can't copy it without extra hardware. The remote is paired to the car and sends trigger and wheel positions continuously. |
| Bluetooth Low Energy (BLE) | Phone apps | The low-power kind of Bluetooth, used by the official **LCW_RCcar** app (by LCW, Shenzhen Lichuang Microelectronics). Wonder Toys sells the board under its own brand. |

## 2. What a phone needs to control it

- BLE support (any Android from version 7, or any iPhone).
- Permission to scan for and connect to nearby Bluetooth devices.
- A way to send short commands many times a second. When the commands stop, the car stops.

## 3. The communication protocol

- **Advertised name:** `YC_CAR_DEMO`
- **Service:** `0000fff0-0000-1000-8000-00805f9b34fb`
- **Write characteristic:** `0000fff2-...` (commands go here)
- **Notify characteristic:** `0000fff1-...` (the car's replies)

### Command format (10 bytes)

```
AA 00 02 00 00 00 00 [CTRL] [SPEED] [TYPE]
```

**CTRL byte** (one bit per switch, most significant bit first):

| Bit | 7 | 6-5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|---|
| Meaning | Light | Play mode (`10`) | Spray | Right | Left | Back | Forward |

- **SPEED:** 30 to 100 (`0x1E` to `0x64`)
- **TYPE:** `01` Car, `02` Dump truck, `03` Excavator
- There's no password, encryption, or checksum.

### Example messages (Car type, speed 100)

| Action | Message |
|---|---|
| Stop | `AA 00 02 00 00 00 00 40 64 01` |
| Forward | `AA 00 02 00 00 00 00 41 64 01` |
| Back | `AA 00 02 00 00 00 00 42 64 01` |
| Left | `AA 00 02 00 00 00 00 44 64 01` |
| Right | `AA 00 02 00 00 00 00 48 64 01` |
| Forward + left | `AA 00 02 00 00 00 00 45 64 01` |
| Forward + right | `AA 00 02 00 00 00 00 49 64 01` |

**How this was found:** I decompiled the official Android app. It's built with uni-app, so its Bluetooth logic is plain JavaScript. A debug screenshot from the real car then confirmed the name and IDs.

## 4. How our app works

1. **Scan:** finds nearby Bluetooth devices and highlights `YC_CAR_DEMO`.
2. **Connect:** finds the service that has one write channel and one reply channel, then subscribes to the replies.
3. **Control:** touches set the direction bits. The speed slider and vehicle type fill in the other bytes.
4. **Send:** a timer sends the message every 100 ms. Letting go, disconnecting, or leaving the app sends stop.
5. **Control modes:** Buttons, Joystick, or Dual sticks (throttle and steering).
6. **Editable layouts:** tap Edit layout to swap sides (joystick and dual sticks) or reorder the three columns (buttons), then lock. The layout is saved for each mode.
7. **Debug panel:** shows the connected IDs, the last message sent, and a switch between writing with and without a reply.

## 5. Technology used

| Area | Choice |
|---|---|
| Framework | Flutter (Dart), one codebase for Android and iOS |
| Bluetooth | `flutter_blue_plus` |
| Permissions | `permission_handler` |
| Saved settings | `shared_preferences` |
| Android build | Signed APK, current version 1.0.2, minimum Android 7 (SDK 24) |
| iOS | Project included; building it needs a Mac with Xcode |
| Network | None: no internet, accounts, or tracking |

## 6. Version history

- **1.0.0:** scan, connect, button controls, speed, lights, vehicle type, debug panel
- **1.0.1:** joystick and dual-stick control modes
- **1.0.2:** editable, lockable layouts and named vehicle types (Car, Dump truck, Excavator)

## 7. Possible next steps

- Web version (works in Chrome on Android and desktop, not on iPhone), hosted free on Firebase Hosting.
- Kotlin Multiplatform version using the architecture skills from the transactions-platform repo.
