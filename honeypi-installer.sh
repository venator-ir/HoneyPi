#!/bin/bash

set -e

# Check root
if [ "$UID" -ne 0 ]; then
    echo "Please run this script as root: sudo honeyPI.sh"
    exit 1
fi

#### Disclaimer ####
if whiptail --yesno "You're about to install honeyPi to turn this Raspberry Pi into an IDS/honeypot. This install process will change some things on your Pi. Most notably, it will flush your iptables and turn up logging. There is no UNINSTALL script, so think hard about not doing this if you plan to use your Pi for other things. Select 'Yes' if you're cool with all that or 'No' to stop now." 20 60; then
    echo "Continuing..."
else
    exit 1
fi

#### Change password if default pi user ####
if [ "${SUDO_USER:-}" = "pi" ]; then
    if whiptail --yesno "You're currently logged in as default pi user. If you haven't changed the default password 'raspberry' would you like to do it now?" 20 60; then
        passwd
    fi
fi

#### Install Debian updates ####
if whiptail --yesno "Let's install some updates. Answer 'No' if you are just experimenting and want to save time. Updates might take 15 minutes or more. Shall we update now?" 20 60; then
    apt-get update
    apt-get -y dist-upgrade
fi

#### Name the host something enticing ####
sneakyname=$(whiptail --inputbox "Let's name your honeyPi something enticing like 'BackupServ01'. Hostnames cannot contain spaces or most special chars. Best to keep it alphanumeric and less than 24 characters." 20 60 3>&1 1>&2 2>&3)

echo "$sneakyname" > /etc/hostname

if ! grep -q "127.0.0.1 $sneakyname" /etc/hosts; then
    echo "127.0.0.1 $sneakyname" >> /etc/hosts
fi

#### Install dependencies ####
whiptail --infobox "Installing log monitoring service and dependencies..." 20 60

apt-get -y install \
    msmtp \
    msmtp-mta \
    python3 \
    python3-twisted \
    iptables-persistent \
    libnotify-bin \
    fwsnort

#### Notification defaults ####
emailaddy="test@example.com"
alertaddy="test1@example.com"
enablescript="N"
externalscript="/bin/true"
alertingmethod="ALL"
check=1

#### Choose notification option ####
OPTION=$(whiptail --menu "Choose how you want to get notified:" 20 60 5 \
    "email" "Send me an email" \
    "script" "Execute a script" \
    3>&2 2>&1 1>&3)

case "$OPTION" in
    email)
        emailaddy=$(whiptail --inputbox "What's the Gmail address alerts will be sent from (where app password is configured)?" 20 60 3>&1 1>&2 2>&3)
        alertaddy=$(whiptail --inputbox "What email address should HoneyPi alerts be sent to?" 20 60 3>&1 1>&2 2>&3)
        msmtp --configure "$emailaddy" > msmtprc

cat > msmtprc <<EOF
defaults
auth on
tls on
tls_starttls on
logfile /var/log/msmtp.log

account default
host smtp.gmail.com
port 587
user $emailaddy
from <HoneyPi> $emailaddy
password XXX
EOF

        # Add helpful instructions to the top of the config
        sed -i '1i### replace XXX with your Gmail App Password' msmtprc
        sed -i '2i### Save and exit when finished' msmtprc

        cp msmtprc /etc/msmtprc
        chmod 600 /etc/msmtprc

        check=30

        whiptail --msgbox "Now create a Gmail App Password. You will manually enter the SMTP password on the next screen with no spaces. Save and exit the editor when done." 20 60
        pico /etc/msmtprc

        whiptail --msgbox "Welcome back. Sending a test message to your email address..." 20 60
        printf "From: HoneyPi <%s>\nTo: %s\nSubject: HoneyPi test\n\nTest message from HoneyPi\n" "$emailaddy" "$alertaddy" | msmtp -vvv "$alertaddy"

        if whiptail --yesno "Wait a couple minutes and see if that test message shows up. Select Yes to continue or No to exit and fix SMTP." 20 60; then
            echo "Continuing..."
        else
            exit 1
        fi
    ;;

    script)
        externalscript=$(whiptail --inputbox "Enter the full path and name of the script to execute when an alert is triggered:" 20 60 3>&1 1>&2 2>&3)

        if [ ! -f "$externalscript" ]; then
            whiptail --msgbox "Warning: $externalscript does not exist. The honeypot config will still be written, but alerts may fail until the script exists." 20 60
        fi

        enablescript="Y"
        alertingmethod="noemail"
    ;;
esac

#### Optional whitelist IPs ####
whitelist_ips=$(whiptail --inputbox "Enter whitelist IPs separated by commas, or leave blank. Example: 192.168.1.10,10.0.0.5" 20 70 3>&1 1>&2 2>&3)

if [ -n "$whitelist_ips" ]; then
    whitelist_py=$(echo "$whitelist_ips" | awk -F',' '{
        printf "["
        for (i=1; i<=NF; i++) {
            gsub(/^ +| +$/, "", $i)
            printf "\"%s\"", $i
            if (i<NF) printf ", "
        }
        printf "]"
    }')
else
    whitelist_py="[]"
fi

#### Wrap up everything ####
whiptail --msgbox "Configuration files created. Next we will move those files to the right places." 20 60

mkdir -p /root/honeyPi

#### Configure iptables logging ####
iptables --flush
iptables -A INPUT -p igmp -j DROP
iptables -A INPUT -j LOG
iptables -A FORWARD -j LOG

service netfilter-persistent save
service netfilter-persistent restart

#### Copy honeypot files ####
cp venatorhoneypot.py /root/honeyPi/venatorhoneypot.py
cp honeypi-watchdog.sh /usr/local/bin/honeypi-watchdog.sh
chmod +x /usr/local/bin/honeypi-watchdog.sh

#### Patch venatorhoneypot.py config block ####
export ENABLESCRIPT="$enablescript"
export EXTERNALSCRIPT="$externalscript"
export ALERTINGMETHOD="$alertingmethod"
export EMAILADDY="$emailaddy"
export ALERTADDY="$alertaddy"
export WHITELIST_PY="$whitelist_py"

python3 <<'PYEOF'
import os
from pathlib import Path

path = Path("/root/honeyPi/venatorhoneypot.py")
text = path.read_text()

config = f'''# BEGIN HONEYPI_CONFIG
ENABLESCRIPT = "{os.environ["ENABLESCRIPT"]}"
EXTERNALSCRIPT = "{os.environ["EXTERNALSCRIPT"]}"
ALERTINGMETHOD = "{os.environ["ALERTINGMETHOD"]}"
EMAILADDY = "{os.environ["EMAILADDY"]}"
ALERTADDY = "{os.environ["ALERTADDY"]}"
WHITELIST_IPS = {os.environ["WHITELIST_PY"]}
# END HONEYPI_CONFIG'''

start_marker = "# BEGIN HONEYPI_CONFIG"
end_marker = "# END HONEYPI_CONFIG"

if start_marker not in text or end_marker not in text:
    raise SystemExit("ERROR: venatorhoneypot.py is missing the HONEYPI_CONFIG marker block.")

start = text.index(start_marker)
end = text.index(end_marker) + len(end_marker)

text = text[:start] + config + text[end:]
path.write_text(text)
PYEOF

#### Start watchdog ####
/usr/local/bin/honeypi-watchdog.sh

#### Add watchdog cron job ####
CRON_JOB='*/30 * * * * /usr/local/bin/honeypi-watchdog.sh'
(crontab -l 2>/dev/null | grep -Fv "/usr/local/bin/honeypi-watchdog.sh"; echo "$CRON_JOB") | crontab -

#### Start honeypot ####
#python3 /root/honeyPi/venatorhoneypot.py &

printf "\n\nNow reboot and you should be good to go.\n"
printf "Logs for the watchdog are in /var/log/honeypi-watchdog.log\n"
