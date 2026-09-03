# microduck-bridge

`robotd` listens on a Unix domain socket, `/run/robotd.sock`. A phone cannot
open a Unix socket on another machine. Either the phone speaks SSH — a real
implementation, host-key trust, key management, not a weekend — or a small
program on the robot's own computer moves the bytes. This is that program.

```sh
# on the machine robotd runs on, once
./install.sh
```

It mints a token, installs a user service, advertises `_robotd._tcp` over
Avahi if it can, and prints the token. Microduck Studio finds the machine and
asks for the token once.

## What it is

A relay, and two safety features. Every byte a client sends reaches robotd
unchanged and every byte robotd sends reaches the client unchanged: the bridge
does not parse the vocabulary, rewrite parameters or answer on robotd's
behalf. That is deliberate. A relay that understands the protocol is a second
implementation of it, and the second implementation is the one that is wrong
when they disagree.

**The first line authorises the relay.** A client sends
`{"microduck":"v1","token":"…"}` and gets the bridge's own hello back. A wrong
token is told which door it is at and closed, and never reaches robotd.

**The deadman sends a stop when a client goes quiet.** A simulator gives you a
duck that stops when nobody asks it to move; hardware does not. If the phone
goes down a lift, the Wi-Fi drops or the app is killed mid-hold, the robot is
still walking. After `--deadman` milliseconds without a byte from the client,
the bridge sends `robot.stop` once, and sends it again only after the client
has spoken and gone quiet again. Any byte re-arms it, not only a move: a client
asking for state is a client that is still there.

It cannot act if this process is the thing that died, which is why the service
restarts and why robotd's own twist deadman stays the backstop under it.

## What it is not

**The token is not a security boundary.** It stops a television or a
housemate's laptop stumbling into a robot. It does not stop anybody who can
read your Wi-Fi. Bind it to the LAN, and do not port-forward it.

**It is not a simulator.** `mock-robotd.py` is a robotd-shaped socket that
accepts every method and answers a constant, so the bridge and the app can be
exercised on a laptop with no duck. Nothing in it has physics. For a duck that
moves, use the bench.

## Proving it

```sh
python3 test_bridge.py          # 9 tests, stdlib only, no duck required
```

Nine tests against a mock robotd that records what it was sent: bytes reach
robotd unchanged, answers reach the client unchanged, a wrong token never
reaches robotd at all, a token file other users can read is refused by mode, a
silent client is stopped exactly once, talking again re-arms the deadman, and a
client that keeps talking is never stopped by its own driver.

End to end on one machine:

```sh
python3 -u mock-robotd.py --socket /tmp/duck.sock &
echo "0123456789abcdef0123456789abcdef" > /tmp/token && chmod 600 /tmp/token
python3 -u microduck-bridge.py --socket /tmp/duck.sock --port 7788 \
        --host 127.0.0.1 --token-file /tmp/token --deadman 400
```

## Where it runs

Python 3.9 or newer, standard library only, no pip and nothing to build — so
it runs wherever robotd does, and on a Mac or a Linux box for testing. The
service file is systemd; without systemd the installer prints the command to
run instead of pretending.
