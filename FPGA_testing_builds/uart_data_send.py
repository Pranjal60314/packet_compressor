import time
import serial
import serial.tools.list_ports

# Configuration
# Change 'COM3' (Windows) or '/dev/ttyUSB0' (Linux/macOS) to your port
PORT = "/dev/ttyUSB0"
BAUDRATE = 115200
SEND_INTERVAL_SEC = 1.0


def list_available_ports():
    """Helper to display accessible ports if the target is wrong."""
    ports = serial.tools.list_ports.comports()
    if not ports:
        print("No serial ports found.")
    else:
        print("Available serial ports:")
        for p in ports:
            print(f"  - {p.device}: {p.description}")


def main():
    try:
        # Open port with no hardware flow control (rtscts=False, dsrdtr=False)
        # This ensures data pushes out the TX pin with nothing connected.
        with serial.Serial(
            port=PORT,
            baudrate=BAUDRATE,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=1,
            xonxoff=False,
            rtscts=False,
            dsrdtr=False,
        ) as ser:
            print(f"Opened {PORT} at {BAUDRATE} baud. Transmitting data stream...")
            print("Press Ctrl+C to stop.")

            counter = 0
            while True:
                # Prepare payload
                payload = f"STREAM_PACKET_{counter:05d}\r\n".encode("utf-8")

                # Transmit
                ser.write(payload)
                ser.flush()  # Force write buffer out to the physical TX line

                print(f"Sent: {payload.decode('utf-8').strip()}")
                counter += 1
                time.sleep(SEND_INTERVAL_SEC)

    except serial.SerialException as e:
        print(f"Serial Error: {e}\n")
        list_available_ports()
    except KeyboardInterrupt:
        print("\nTransmission stopped by user.")


if __name__ == "__main__":
    main()