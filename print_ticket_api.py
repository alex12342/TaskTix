#!/usr/bin/env python3
import os
import json
import logging
import sys
from pathlib import Path
from datetime import datetime
from flask import Flask, request, jsonify
import subprocess
import textwrap

app = Flask(__name__)

CONFIG_DIR = Path("/config")
STATE_DIR = CONFIG_DIR / "state"
LOG_DIR = CONFIG_DIR / "logs"
SETTINGS_FILE = CONFIG_DIR / "settings.json"
COUNTER_FILE = STATE_DIR / "ticket_counter"
PRINT_SCRIPT = CONFIG_DIR / "print_ticket.sh"

STATE_DIR.mkdir(parents=True, exist_ok=True)
LOG_DIR.mkdir(parents=True, exist_ok=True)

# ---------- Logging setup ----------
root_logger = logging.getLogger()
root_logger.setLevel(logging.INFO)

fmt = logging.Formatter(
    "%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)

# Stream handler to stdout (Docker/Unraid logs)
stream_handler = logging.StreamHandler(sys.stdout)
stream_handler.setFormatter(fmt)
root_logger.addHandler(stream_handler)

# File handler for flask.log
flask_file_handler = logging.FileHandler(LOG_DIR / "flask.log")
flask_file_handler.setFormatter(fmt)
root_logger.addHandler(flask_file_handler)

# Separate logger for ticket events (file only; still propagate to root stdout)
tickets_logger = logging.getLogger("tickets")
tickets_logger.setLevel(logging.INFO)
tickets_file_handler = logging.FileHandler(LOG_DIR / "tickets.log")
tickets_file_handler.setFormatter(fmt)
tickets_logger.addHandler(tickets_file_handler)

logger = logging.getLogger("ticket_api")


# ---------- Settings & templates ----------

def load_settings():
    if SETTINGS_FILE.exists():
        try:
            with SETTINGS_FILE.open("r", encoding="utf-8") as f:
                return json.load(f)
        except Exception as e:
            logger.error("Failed to load settings.json: %s", e)
    # Fallback built-in default
    return {
        "default": {
            "template": (
                "============================\n"
                "  TASK #{ticket_num}\n"
                "  {timestamp}\n"
                "============================\n\n"
                "{wrapped_task}\n\n"
                "----------------------------\n"
            ),
            "width": 32
        }
    }


SETTINGS = load_settings()


def get_template_and_width(ticket_type: str):
    ticket_type = ticket_type or "default"
    tmpl_cfg = SETTINGS.get(ticket_type)
    if not tmpl_cfg:
        logger.warning("Unknown ticket_type '%s', falling back to 'default'", ticket_type)
        tmpl_cfg = SETTINGS["default"]

    template = tmpl_cfg.get("template", "{wrapped_task}")
    width = tmpl_cfg.get("width", 32)

    # sanity
    try:
        width = int(width)
    except ValueError:
        width = 32
    if width <= 0:
        width = 32

    return template, width


def wrap_task_text(task: str, width: int) -> str:
    """
    Word-wrap the task text so it doesn't break words mid-line.
    Preserves blank lines (paragraphs) if present.
    """
    paragraphs = task.split("\n\n")
    wrapped_paragraphs = []
    for p in paragraphs:
        lines = p.splitlines()
        # Wrap each logical line separately to preserve intentional breaks
        wrapped_lines = [
            textwrap.fill(
                line,
                width=width,
                break_long_words=False,
                break_on_hyphens=False,
            ) if line.strip() else ""
            for line in lines
        ]
        wrapped_paragraphs.append("\n".join(wrapped_lines).rstrip())
    return "\n\n".join(wrapped_paragraphs).rstrip()


# ---------- Counter management ----------

def next_ticket_number() -> int:
    if not COUNTER_FILE.exists():
        COUNTER_FILE.write_text("0", encoding="utf-8")

    try:
        current = int(COUNTER_FILE.read_text(encoding="utf-8").strip() or "0")
    except ValueError:
        current = 0

    current += 1
    COUNTER_FILE.write_text(str(current), encoding="utf-8")
    return current


# ---------- Routes ----------

@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok"}), 200


@app.route("/print", methods=["POST"])
def print_ticket():
    data = request.get_json(silent=True) or {}
    task = (data.get("task") or "").strip()
    ticket_type = (data.get("ticket_type") or "default").strip()

    if not task:
        logger.warning("Received print request without 'task'")
        return jsonify({"error": "Missing 'task' in JSON body"}), 400

    if not PRINT_SCRIPT.is_file():
        logger.error("Print script not found at %s", PRINT_SCRIPT)
        return jsonify({"error": "Print script not found", "path": str(PRINT_SCRIPT)}), 500

    ticket_num = next_ticket_number()
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    template, width = get_template_and_width(ticket_type)
    wrapped_task = wrap_task_text(task, width)

    try:
        ticket_text = template.format(
            ticket_num=ticket_num,
            timestamp=timestamp,
            task=task,
            wrapped_task=wrapped_task,
        )
    except Exception as e:
        logger.error("Error formatting template '%s': %s", ticket_type, e)
        return jsonify({"error": "Template formatting failed"}), 500

    # Ticket log (goes to tickets.log + stdout via propagation)
    tickets_logger.info("Ticket #%d (%s): %s", ticket_num, ticket_type, task)

    try:
        subprocess.run(
            [str(PRINT_SCRIPT)],
            input=ticket_text,
            text=True,
            check=True,
        )
    except subprocess.CalledProcessError as e:
        logger.error("Print failed: %s", e)
        return jsonify({"error": "Print failed", "details": str(e)}), 500

    return jsonify({"status": "ok", "ticket_num": ticket_num}), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5005)

