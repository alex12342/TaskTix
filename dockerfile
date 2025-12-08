FROM debian:12-slim

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    DEBIAN_FRONTEND=noninteractive

# Base packages: CUPS, Python, Flask, libcups libs, tzdata, gosu, etc.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      cups cups-client cups-bsd \
      python3 python3-pip python3-flask \
      tzdata \
      gosu \
      bash \
      ca-certificates \
      curl \
      libcups2 libcupsimage2 && \
    # Ensure unversioned libcups.so & libcupsimage.so exist for vendor filters
    ln -s /usr/lib/x86_64-linux-gnu/libcups.so.2 /usr/lib/x86_64-linux-gnu/libcups.so 2>/dev/null || true && \
    ln -s /usr/lib/x86_64-linux-gnu/libcupsimage.so.2 /usr/lib/x86_64-linux-gnu/libcupsimage.so 2>/dev/null || true && \
    rm -rf /var/lib/apt/lists/*

# Default envs (override at runtime)
ENV PUID=99 \
    PGID=100 \
    TZ=Etc/UTC \
    APP_SCRIPT=/config/print_ticket_api.py \
    PRINTER_NAME=Star \
    CUPS_USER=admin \
    CUPS_PASSWORD=adminpass

# Prepare directories and base user
RUN mkdir -p /config /app /opt/tasktix && \
    groupadd -g 1000 app && \
    useradd -u 1000 -g app -d /home/app -m app && \
    mkdir -p /var/log/cups /var/run/cups /var/spool/cups && \
    chown -R app:app /app /var/log/cups /var/run/cups /var/spool/cups

# Copy default app files into image (built-in templates that will seed /config)
COPY entrypoint.sh /entrypoint.sh
COPY print_ticket_api.py /opt/tasktix/print_ticket_api.py
COPY print_ticket.sh /opt/tasktix/print_ticket.sh
COPY settings.json /opt/tasktix/settings.json
RUN chmod +x /entrypoint.sh /opt/tasktix/print_ticket.sh

# CUPS config that enables remote web access
COPY cupsd.conf /etc/cups/cupsd.conf

# Star Printer Drivers (already laid out in correct directories under Driver/)
COPY Driver/ /

# Fix CUPS filter permissions so CUPS doesn't complain about "insecure permissions"
RUN if [ -d /usr/lib/cups/filter ]; then \
      chown -R root:root /usr/lib/cups/filter && \
      find /usr/lib/cups/filter -type d -exec chmod 755 {} \; && \
      find /usr/lib/cups/filter -type f -exec chmod 755 {} \; \
    ; fi

EXPOSE 5005 631

VOLUME ["/config"]

ENTRYPOINT ["/entrypoint.sh"]
CMD ["python3", "/config/print_ticket_api.py"]

