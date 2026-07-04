#!/usr/bin/env python3
"""Send an Intel HEX file to the b8008 monitor's L command, paced.

The 8008 polls the USART at ~47 us/instruction and buffers exactly one
received byte, so it cannot take back-to-back characters at 115200 baud.
This sender paces characters and prints everything the monitor sends back
('.' per record, '?' per bad record, then OK / ERR n).

No dependencies - uses POSIX termios from the standard library.

Typical use (kill minicom first - one process owns the port):

  ./send_hex.py test_programs/samples/mandelbrot_ram.hex --go 2040

Which does: L <hexfile> then G 2040. Watch the picture arrive; the
program jumps back to the monitor (banner + prompt) when done.
"""

import argparse
import os
import sys
import termios
import time

DEFAULT_PORT = "/dev/tty.usbserial-AB0JK5WC"


def open_port(path, baud):
    fd = os.open(path, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    attrs = termios.tcgetattr(fd)
    baud_const = getattr(termios, "B%d" % baud)
    attrs[0] = 0                                        # iflag: raw
    attrs[1] = 0                                        # oflag: raw
    attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL   # cflag: 8N1
    attrs[3] = 0                                        # lflag: raw
    attrs[4] = baud_const                               # ispeed
    attrs[5] = baud_const                               # ospeed
    attrs[6][termios.VMIN] = 0
    attrs[6][termios.VTIME] = 0
    termios.tcsetattr(fd, termios.TCSANOW, attrs)
    return fd


transcript = bytearray()


def drain(fd):
    try:
        data = os.read(fd, 4096)
    except BlockingIOError:
        return
    if data:
        transcript.extend(data)
        sys.stdout.write(data.decode("ascii", "replace"))
        sys.stdout.flush()


def send(fd, text, char_delay):
    for ch in text:
        os.write(fd, ch.encode("ascii"))
        termios.tcdrain(fd)
        time.sleep(char_delay)
        drain(fd)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("hexfile", help="Intel HEX file to send")
    ap.add_argument("--port", default=DEFAULT_PORT)
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--char-delay", type=float, default=0.005,
                    help="seconds between characters (default 5 ms - the "
                         "monitor's echo path takes ~4 ms per character)")
    ap.add_argument("--line-delay", type=float, default=0.05,
                    help="extra seconds between records (default 50 ms)")
    ap.add_argument("--no-l", action="store_true",
                    help="don't send the L command first (loader already waiting)")
    ap.add_argument("--go", metavar="ADDR",
                    help="send 'G ADDR' after a clean load (hex, e.g. 2040)")
    args = ap.parse_args()

    with open(args.hexfile) as f:
        records = [ln.strip() for ln in f if ln.strip()]
    if not records:
        sys.exit("empty hex file")

    fd = open_port(args.port, args.baud)
    try:
        if not args.no_l:
            send(fd, "L\r", args.char_delay)
            time.sleep(0.3)          # monitor prints "SEND HEX (ESC ends)"
            drain(fd)

        for i, rec in enumerate(records, 1):
            send(fd, rec + "\r", args.char_delay)
            time.sleep(args.line_delay)
            drain(fd)
            print(f"  [{i}/{len(records)}]", end="\r", file=sys.stderr)

        # loader prints OK + prompt + one empty-enter cycle (trailing CR)
        time.sleep(0.5)
        drain(fd)
        print(file=sys.stderr)

        # A dropped record leaves NO checksum error - the loader just
        # resyncs at the next ':' and a silent gap lands in RAM. The dot
        # count is the only truth: one '.' per accepted record.
        dots = transcript.count(b"."[0])
        # data records answer '.'; the EOF record (type 01) answers OK
        expected = sum(1 for r in records if len(r) >= 9 and r[7:9] != "01")
        if dots != expected or b"OK" not in bytes(transcript) or \
           b"ERR" in transcript or b"?" in transcript:
            sys.exit(f"\nLOAD INCOMPLETE: {dots}/{expected} data records "
                     "acknowledged ('.') plus OK expected. RAM image is NOT "
                     "trustworthy - reset the board and rerun this load.")
        print(f"verified: {dots}/{expected} data records acknowledged + OK",
              file=sys.stderr)

        if args.go and (b"ERR" in transcript or b"?" in transcript):
            sys.exit("\nload had errors ('?' records / ERR) - NOT sending "
                     f"G {args.go}. RAM image is incomplete; rerun the load.")

        if args.go:
            send(fd, f"G {args.go}\r", args.char_delay)
            print(f"\nsent: G {args.go} - reattach minicom to watch the output",
                  file=sys.stderr)
            # show the first seconds of program output
            end = time.time() + 5
            while time.time() < end:
                drain(fd)
                time.sleep(0.05)
    finally:
        drain(fd)
        os.close(fd)


if __name__ == "__main__":
    main()
