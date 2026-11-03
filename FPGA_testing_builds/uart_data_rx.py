import threading
import time
import serial
import serial.tools.list_ports

BAUDRATE = 115200
READ_TIMEOUT_SEC = 0.5  # Prevents thread locking when no data arrives


def port_listener(port_name: str, stop_event: threading.Event):
    """Worker thread that continuously reads from a single serial port."""
    try:
        with serial.Serial(
            port=port_name,
            baudrate=BAUDRATE,
            timeout=READ_TIMEOUT_SEC,
            xonxoff=False,
            rtscts=False,
            dsrdtr=False,
        ) as ser:
            print(f"[ACTIVE] Listening on {port_name}...")

            while not stop_event.is_set():
                # Read all currently buffered bytes
                bytes_to_read = ser.in_waiting
                if bytes_to_read > 0:
                    raw_data = ser.read(bytes_to_read)
                    try:
                        # Attempt UTF-8 decoding; fall back to hex representation for binary
                        decoded = raw_data.decode("utf-8", errors="replace").strip()
                        print(f"[{port_name}] {decoded}")
                    except Exception:
                        print(f"[{port_name}] (HEX) {raw_data.hex()}")
                else:
                    # Sleep briefly to release the GIL and prevent pegging the CPU
                    time.sleep(0.05)

    except serial.SerialException as e:
        print(f"[ERROR] Could not maintain connection on {port_name}: {e}")
    finally:
        print(f"[CLOSED] Stopped listening on {port_name}")


def main():
    # Detect all currently available COM / tty ports
    ports = serial.tools.list_ports.comports()

    if not ports:
        print("No serial ports detected on the system.")
        return

    print("Detected ports:")
    for p in ports:
        print(f"  - {p.device} ({p.description})")

    stop_event = threading.Event()
    threads = []

    # Spawn an independent background listener for each detected port
    for p in ports:
        t = threading.Thread(
            target=port_listener,
            args=(p.device, stop_event),
            daemon=True
        )
        t.start()
        threads.append(t)

    print("\nAll listener threads initialized. Press Ctrl+C to exit.\n" + ("-" * 50))

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\nShutting down listeners...")
        stop_event.set()
        for t in threads:
            t.join(timeout=1.0)
        print("Done.")


if __name__ == "__main__":
    main()