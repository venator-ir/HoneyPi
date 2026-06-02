#!/usr/bin/env python3

import subprocess
import socket
import binascii
import time
import shlex

from twisted.internet.protocol import Protocol, Factory
from twisted.internet import reactor

# BEGIN HONEYPI_CONFIG
ENABLESCRIPT = "N"
EXTERNALSCRIPT = "/bin/true"
ALERTINGMETHOD = "ALL"
EMAILADDY = "test@example.com"
ALERTADDY="test1@example.com"
WHITELIST_IPS = []
# END HONEYPI_CONFIG

interface = "0.0.0.0"

VNC_RFB = binascii.unhexlify("524642203030332e3030380a")
FTP_response = binascii.unhexlify(
    "3232302050726f4654504420312e332e306120536572766572202850726f4654504420416e6f6e796d6f75732053657276657229205b3139322e3136382e312e3233315d0d0a"
)
TELNET_response = binascii.unhexlify("fffd25")
SSH_response = b"SSH-2.0-OpenSSH_8.2p1 Ubuntu-4ubuntu0.5\r\n"


def formattedprint(toprint):
    curr = time.strftime("%Y-%m-%d %H:%M:%S: ")
    print(curr + toprint, flush=True)


def is_whitelisted(src_ip):
    return src_ip in WHITELIST_IPS


def send_email_alert(subject, body):
    msg = (
        "From: HoneyPi <{}>\n"
        "To: {}\n"
        "Subject: {}\n\n"
        "{}"
    ).format(EMAILADDY, ALERTADDY, subject, body)

    subprocess.run(
        ["/usr/bin/msmtp", "-a", "default", ALERTADDY],
        input=msg.encode("utf-8"),
        check=False,
    )


def run_script_alert(proto, src_ip, src_port, dst_port):
    if not EXTERNALSCRIPT:
        return

    cmd = shlex.split(EXTERNALSCRIPT)

    subprocess.run(
        cmd + [str(src_ip)],
        check=False,
    )


def send_alert(proto, src_ip, src_port, dst_port):
    if is_whitelisted(src_ip):
        formattedprint(
            "Whitelisted {} connection ignored from: {} ({} -> {})".format(
                proto, src_ip, src_port, dst_port
            )
        )
        return

    hostname = socket.gethostname()

    subject = "[HoneyPi] {} hit on {}:{} from {}:{}".format(
        proto, hostname, dst_port, src_ip, src_port
    )

    body = "{} UTC Inbound {} connection from {}:{} to local port {}\n".format(
        time.strftime("%Y-%m-%d %H:%M:%S"),
        proto,
        src_ip,
        src_port,
        dst_port,
    )

    formattedprint(body.strip())

    if ALERTINGMETHOD != "noemail":
        send_email_alert(subject, body)

    if ENABLESCRIPT == "Y":
        run_script_alert(proto, src_ip, src_port, dst_port)


class FakeTELNETClass(Protocol):
    def connectionMade(self):
        src_ip = self.transport.getPeer().host
        src_port = self.transport.getPeer().port

        formattedprint(
            "Inbound TELNET connection from: {} ({}/TCP)".format(src_ip, src_port)
        )
        send_alert("TELNET", src_ip, src_port, 23)
        self.transport.write(TELNET_response)
        formattedprint("Sending TELNET response...")


class FakeFTPClass(Protocol):
    def connectionMade(self):
        src_ip = self.transport.getPeer().host
        src_port = self.transport.getPeer().port

        formattedprint(
            "Inbound FTP connection from: {} ({}/TCP)".format(src_ip, src_port)
        )
        send_alert("FTP", src_ip, src_port, 21)
        self.transport.write(FTP_response)
        formattedprint("Sending FTP response...")


class FakeSSHClass(Protocol):
    def connectionMade(self):
        src_ip = self.transport.getPeer().host
        src_port = self.transport.getPeer().port

        formattedprint(
            "Inbound SSH connection from: {} ({}/TCP)".format(src_ip, src_port)
        )
        send_alert("SSH", src_ip, src_port, 2222)
        self.transport.write(SSH_response)
        formattedprint("Sending SSH response...")


class FakeVNCClass(Protocol):
    def connectionMade(self):
        src_ip = self.transport.getPeer().host
        src_port = self.transport.getPeer().port

        formattedprint(
            "Inbound VNC connection from: {} ({}/TCP)".format(src_ip, src_port)
        )
        send_alert("VNC", src_ip, src_port, 5900)
        self.transport.write(VNC_RFB)
        formattedprint("Sending VNC response...")


FakeVNC = Factory()
FakeVNC.protocol = FakeVNCClass

FakeFTP = Factory()
FakeFTP.protocol = FakeFTPClass

FakeTELNET = Factory()
FakeTELNET.protocol = FakeTELNETClass

FakeSSH = Factory()
FakeSSH.protocol = FakeSSHClass


formattedprint("Starting up honeypot python program...")

reactor.listenTCP(5900, FakeVNC, interface=interface)
reactor.listenTCP(21, FakeFTP, interface=interface)
reactor.listenTCP(23, FakeTELNET, interface=interface)
reactor.listenTCP(2222, FakeSSH, interface=interface)

reactor.run()

formattedprint("Shutting down honeypot python program...")