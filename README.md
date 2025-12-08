# TaskTix – CUPS-Backed Ticket Printer API

TaskTix is a Docker container that provides:

* A Flask-based HTTP API for printing tickets
* A fully functional CUPS server inside the container
* Persistent printer configuration across updates
* Optional bundled drivers
* Template-based ticket formatting
* Integrations for Home Assistant
* Support for USB thermal printers

This container is built for printing small "task tickets" from automations.

---

# Features

* REST API endpoint at `/print`
* CUPS web interface on port `631`
* Printer configuration persisted across container updates
* Templates defined in `/config/settings.json`
* PUID/PGID support for Unraid
* Word wrapping and variable substitution in templates
* Logs stored in `/config/logs`
* USB passthrough support using `/dev/serial/by-id/...`
* Optional custom drivers included at build time

---

# Ports

| Container Port | Description        |
| -------------- | ------------------ |
| `5005`         | Flask API          |
| `631`          | CUPS Web Interface |

---

# Environment Variables

| Variable        | Default                       | Description                     |
| --------------- | ----------------------------- | ------------------------------- |
| `PUID`          | `99`                          | Container user ID               |
| `PGID`          | `100`                         | Container group ID              |
| `TZ`            | `Etc/UTC`                     | Time zone                       |
| `PRINTER_NAME`  | `Star`                        | Target printer name for `lp -d` |
| `APP_SCRIPT`    | `/config/print_ticket_api.py` | API entry script                |
| `CUPS_USER`     | `admin`                       | CUPS UI admin username          |
| `CUPS_PASSWORD` | `adminpass`                   | CUPS UI admin password          |
| `USB_DEVICE`    | *(optional)*                  | USB device path for logging     |

---

# Volume Mapping

Example:

```
-v /mnt/user/appdata/tasktix:/config
```

The `/config` volume contains:

```
/config/print_ticket_api.py
/config/print_ticket.sh
/config/settings.json
/config/state/
/config/logs/
/config/cups/etc/   (persistent printer configuration)
```

On first start, missing files are automatically populated.

---

# Persistent CUPS Configuration

The container performs the following on startup:

1. Copies the built-in `/etc/cups` into `/config/cups/etc` if it does not already exist
2. Replaces `/etc/cups` with a symlink pointing to `/config/cups/etc`

This ensures:

* Installed printers persist across updates
* PPDs remain installed
* CUPS settings remain intact

---

# USB Printer Passthrough

Locate the printer's persistent device path:

```
ls -l /dev/serial/by-id/
```

Then map it into the container:

```
--device /dev/serial/by-id/<your-printer-id>:/dev/usbprinter
```

When adding the printer inside CUPS, select the device `/dev/usbprinter`.

---

# REST API

## Health Check

```
GET /health
```

Response:

```json
{ "status": "ok" }
```

---

## Print Ticket

```
POST /print
Content-Type: application/json
```

Example body:

```json
{
  "task": "Sweep hallway near science wing",
  "ticket_type": "default"
}
```

Fields:

| Field         | Required | Description                       |
| ------------- | -------- | --------------------------------- |
| `task`        | Yes      | Text printed on the ticket        |
| `ticket_type` | No       | Template key from `settings.json` |

Response:

```json
{
  "status": "ok",
  "ticket_num": 42
}
```

---

# Template System (`settings.json`)

Example file:

```json
{
  "default": {
    "template": "TASK #{ticket_num}\n{timestamp}\n\n{wrapped_task}\n",
    "width": 32
  },
  "maintenance": {
    "template": "MAINTENANCE #{ticket_num}\n{timestamp}\n\n{wrapped_task}\n",
    "width": 32
  }
}
```

Template variables:

| Variable         | Description                      |
| ---------------- | -------------------------------- |
| `{ticket_num}`   | Auto-incrementing ticket number  |
| `{timestamp}`    | Current date/time                |
| `{task}`         | Raw input text                   |
| `{wrapped_task}` | Word-wrapped version of the task |

The `width` parameter controls wrapping length.

---

# Logs

### Docker Logs

Shown in the container logs (Flask output, CUPS info).

### Persistent Logs

Stored in:

```
/config/logs/flask.log
/config/logs/tickets.log
```

Example entry:

```
2025-12-07 15:00:00 Ticket #42: Sweep hallway near science wing
```

---

# Home Assistant Integration

## `rest_command`

```
rest_command:
  tasktix_print_ticket:
    url: "http://tasktix:5005/print"
    method: POST
    headers:
      Content-Type: application/json
    payload: >
      {
        "task": "{{ task }}",
        "ticket_type": "{{ ticket_type | default('default') }}"
      }
```

---

## Automation Example

(Triggers when an item is added to a specific todo list)

```
alias: Print ticket when new todo item is added
mode: single

triggers:
  - trigger: event
    event_type: call_service
    event_data:
      domain: todo
      service: add_item

variables:
  raw_entity_ids: "{{ trigger.event.data.service_data.entity_id }}"
  entity_id: >
    {% if raw_entity_ids is list %}
      {{ raw_entity_ids[0] }}
    {% else %}
      {{ raw_entity_ids }}
    {% endif %}
  list_name: "{{ state_attr(entity_id, 'friendly_name') }}"
  task: "{{ (trigger.event.data.service_data.item or '') | trim }}"

conditions:
  - condition: template
    value_template: "{{ entity_id == 'todo.tasks' }}"
  - condition: template
    value_template: "{{ task != '' }}"

actions:
  - action: rest_command.tasktix_print_ticket
    data:
      task: "{{ task }}"
      ticket_type: default
```

---

# Manual Run Example

```
docker run -d \
  --name tasktix \
  -p 5005:5005 \
  -p 8631:631 \
  -e PUID=99 \
  -e PGID=100 \
  -e TZ=America/New_York \
  -e CUPS_USER=admin \
  -e CUPS_PASSWORD=supersecret \
  -v /mnt/user/appdata/tasktix:/config \
  --device /dev/serial/by-id/usb-YourPrinterID:/dev/usbprinter \
  alex12342/tasktix:latest
```

Access CUPS:

```
http://<host>:8631
```

---


