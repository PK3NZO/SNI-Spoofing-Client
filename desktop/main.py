from __future__ import annotations

import sys

from PySide6.QtCore import QTimer, Qt
from PySide6.QtGui import QColor, QFont, QPalette
from PySide6.QtWidgets import (
    QApplication,
    QButtonGroup,
    QCheckBox,
    QComboBox,
    QFormLayout,
    QFrame,
    QGridLayout,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMainWindow,
    QPushButton,
    QPlainTextEdit,
    QTextEdit,
    QVBoxLayout,
    QWidget,
)

from backends import available_backend_names
from core.app_copy import AppLanguage, DesktopCopy
from core.config import AppConfig
from core.models import ConnectionMode, WorkflowStepState
from core.runtime import AppRuntime, RuntimeState


APP_STYLESHEET = """
QWidget {
    background: #f6f8fc;
    color: #233347;
    font-family: Segoe UI, Inter, Arial, sans-serif;
    font-size: 13px;
}
QMainWindow {
    background: #eef3fa;
}
QFrame#Card {
    background: #ffffff;
    border: 1px solid #d8e1ef;
    border-radius: 22px;
}
QFrame#SoftCard {
    background: #f8fbff;
    border: 1px solid #d8e1ef;
    border-radius: 18px;
}
QLabel#Title {
    font-size: 28px;
    font-weight: 700;
}
QLabel#Subtitle {
    color: #6d7f95;
}
QLabel#Section {
    font-size: 15px;
    font-weight: 700;
    color: #31445d;
}
QLabel#Caption {
    color: #6d7f95;
    font-size: 12px;
}
QLabel#StatusHeadline {
    font-size: 18px;
    font-weight: 700;
}
QLabel#StatusDot {
    min-width: 12px;
    min-height: 12px;
    max-width: 12px;
    max-height: 12px;
    border-radius: 6px;
    background: #9aa9bc;
}
QLineEdit, QComboBox, QTextEdit, QPlainTextEdit {
    background: #fdfefe;
    border: 1px solid #d3dceb;
    border-radius: 14px;
    padding: 10px 12px;
    selection-background-color: #5b9dff;
}
QTextEdit {
    padding-top: 12px;
}
QPushButton {
    background: #f4f8ff;
    border: 1px solid #d6e0ee;
    border-radius: 14px;
    padding: 10px 16px;
    min-height: 20px;
}
QPushButton:hover {
    background: #ebf3ff;
}
QPushButton#Primary {
    background: #30445c;
    border: 1px solid #30445c;
    color: white;
    font-weight: 700;
}
QPushButton#Danger {
    background: #ffffff;
    border: 1px solid #d6e0ee;
    color: #30445c;
    font-weight: 700;
}
QPushButton#ModeButton {
    min-width: 86px;
    min-height: 34px;
    font-weight: 700;
}
QPushButton#ModeButton[active="true"] {
    background: #2d6cdf;
    border: 1px solid #2d6cdf;
    color: white;
}
QCheckBox {
    spacing: 10px;
}
QCheckBox::indicator {
    width: 18px;
    height: 18px;
}
QCheckBox::indicator:unchecked {
    border: 1px solid #aab9cc;
    background: #ffffff;
    border-radius: 4px;
}
QCheckBox::indicator:checked {
    border: 1px solid #2d6cdf;
    background: #2d6cdf;
    border-radius: 4px;
}
"""


class MainWindow(QMainWindow):
    def __init__(self, runtime: AppRuntime) -> None:
        super().__init__()
        self.runtime = runtime
        self.copy = DesktopCopy(AppLanguage.normalize(self.runtime.config.ui_language))
        self._detail_keys = ["Mode", "Connection", "Allowlist", "System Route", "Original Server", "Probe"]
        self._details_expanded = False
        self._workflow_expanded = False
        self.setWindowTitle(self.copy.app_title)
        self.setMinimumSize(1220, 860)

        central = QWidget(self)
        self.setCentralWidget(central)

        root_layout = QVBoxLayout(central)
        root_layout.setContentsMargins(24, 24, 24, 24)
        root_layout.setSpacing(16)

        root_layout.addWidget(self._build_header())
        root_layout.addWidget(self._build_main_card(), 1)

        self.timer = QTimer(self)
        self.timer.setInterval(150)
        self.timer.timeout.connect(self.poll_runtime)
        self.timer.start()

        self.load_config_to_form()
        self.refresh_ui_state()

    def _build_header(self) -> QWidget:
        frame = QFrame()
        frame.setObjectName("Card")
        layout = QHBoxLayout(frame)
        layout.setContentsMargins(24, 22, 24, 22)
        layout.setSpacing(16)

        copy_layout = QVBoxLayout()
        copy_layout.setSpacing(4)
        self.title_label = QLabel(self.copy.app_title)
        self.title_label.setObjectName("Title")
        self.subtitle_label = QLabel(self.copy.app_subtitle)
        self.subtitle_label.setObjectName("Subtitle")
        self.subtitle_label.setWordWrap(True)
        copy_layout.addWidget(self.title_label)
        copy_layout.addWidget(self.subtitle_label)

        layout.addLayout(copy_layout, 1)

        self.language_label = QLabel(self.copy.language_label)
        self.language_label.setObjectName("Caption")
        self.language_picker = QComboBox()
        self.language_picker.addItem(self.copy.language_name(AppLanguage.ENGLISH), AppLanguage.ENGLISH)
        self.language_picker.addItem(self.copy.language_name(AppLanguage.PERSIAN), AppLanguage.PERSIAN)
        self.language_picker.currentIndexChanged.connect(self.on_language_changed)
        language_layout = QVBoxLayout()
        language_layout.setSpacing(4)
        language_layout.addWidget(self.language_label)
        language_layout.addWidget(self.language_picker)
        layout.addLayout(language_layout)

        status_card = QFrame()
        status_card.setObjectName("SoftCard")
        status_layout = QVBoxLayout(status_card)
        status_layout.setContentsMargins(18, 14, 18, 14)
        status_layout.setSpacing(4)

        top = QHBoxLayout()
        top.setSpacing(10)
        self.status_dot = QLabel()
        self.status_dot.setObjectName("StatusDot")
        self.status_headline = QLabel(self.copy.ready_headline)
        self.status_headline.setObjectName("StatusHeadline")
        top.addWidget(self.status_dot)
        top.addWidget(self.status_headline)
        top.addStretch(1)

        self.status_detail = QLabel(self.copy.ready_detail)
        self.status_detail.setObjectName("Subtitle")
        self.status_detail.setWordWrap(True)

        status_layout.addLayout(top)
        status_layout.addWidget(self.status_detail)
        layout.addWidget(status_card, 0)

        return frame

    def _build_main_card(self) -> QWidget:
        frame = QFrame()
        frame.setObjectName("Card")
        layout = QVBoxLayout(frame)
        layout.setContentsMargins(22, 22, 22, 22)
        layout.setSpacing(18)

        top_row = QHBoxLayout()
        top_row.setSpacing(12)
        top_row.addLayout(self._build_mode_switch())
        top_row.addStretch(1)
        layout.addLayout(top_row)

        body = QGridLayout()
        body.setHorizontalSpacing(16)
        body.setVerticalSpacing(16)
        body.addWidget(self._build_connection_panel(), 0, 0)
        body.addWidget(self._build_runtime_panel(), 0, 1)
        body.setColumnStretch(0, 3)
        body.setColumnStretch(1, 2)
        layout.addLayout(body, 1)

        action_row = QHBoxLayout()
        action_row.setSpacing(12)
        self.connect_button = QPushButton(self.copy.connect)
        self.connect_button.setObjectName("Primary")
        self.connect_button.clicked.connect(self.on_start)
        self.disconnect_button = QPushButton(self.copy.disconnect)
        self.disconnect_button.setObjectName("Danger")
        self.disconnect_button.clicked.connect(self.on_stop)
        self.save_button = QPushButton(self.copy.save_profile)
        self.save_button.clicked.connect(self.on_save)
        action_row.addWidget(self.connect_button, 1)
        action_row.addWidget(self.disconnect_button, 1)
        action_row.addWidget(self.save_button)
        layout.addLayout(action_row)

        return frame

    def _build_mode_switch(self) -> QHBoxLayout:
        wrapper = QHBoxLayout()
        wrapper.setSpacing(8)
        self.connection_mode_label = self._section_label(self.copy.connection_mode)
        wrapper.addWidget(self.connection_mode_label)

        self.mode_group = QButtonGroup(self)
        self.proxy_mode_button = QPushButton(self.copy.proxy)
        self.proxy_mode_button.setObjectName("ModeButton")
        self.proxy_mode_button.clicked.connect(lambda: self._select_mode(ConnectionMode.PROXY.value))
        self.tunnel_mode_button = QPushButton(self.copy.tunnel)
        self.tunnel_mode_button.setObjectName("ModeButton")
        self.tunnel_mode_button.clicked.connect(lambda: self._select_mode(ConnectionMode.TUNNEL.value))
        self.mode_group.addButton(self.proxy_mode_button)
        self.mode_group.addButton(self.tunnel_mode_button)
        wrapper.addWidget(self.proxy_mode_button)
        wrapper.addWidget(self.tunnel_mode_button)
        return wrapper

    def _build_connection_panel(self) -> QWidget:
        frame = QFrame()
        frame.setObjectName("SoftCard")
        layout = QVBoxLayout(frame)
        layout.setContentsMargins(18, 18, 18, 18)
        layout.setSpacing(14)

        self.connection_section_label = self._section_label(self.copy.connection)
        layout.addWidget(self.connection_section_label)

        row = QHBoxLayout()
        row.setSpacing(12)

        self.allowlist_domain = QLineEdit()
        self.allowlist_ip = QLineEdit()

        self.allowlist_domain_group = self._field_group(self.copy.step1_domain, self.allowlist_domain)
        self.allowlist_ip_group = self._field_group(self.copy.step1_ip, self.allowlist_ip)
        row.addLayout(self.allowlist_domain_group)
        row.addLayout(self.allowlist_ip_group)
        layout.addLayout(row)

        self.proxy_link = QTextEdit()
        self.proxy_link.setPlaceholderText(self.copy.proxy_link_placeholder)
        self.proxy_link.setMinimumHeight(130)
        self.proxy_config_section_label = self._section_label(self.copy.step2_proxy)
        layout.addWidget(self.proxy_config_section_label)
        layout.addWidget(self.proxy_link)

        self.enable_system_proxy = QCheckBox(self.copy.auto_proxy_title)
        self.enable_system_proxy.setChecked(True)
        layout.addWidget(self.enable_system_proxy)
        self.proxy_toggle_hint = QLabel(self.copy.auto_proxy_hint)
        self.proxy_toggle_hint.setObjectName("Subtitle")
        self.proxy_toggle_hint.setWordWrap(True)
        layout.addWidget(self.proxy_toggle_hint)

        self.advanced_form = QFormLayout()
        self.advanced_form.setVerticalSpacing(12)
        self.listen_host = QLineEdit()
        self.listen_port = QLineEdit()
        self.log_level = QComboBox()
        self.log_level.addItems(["debug", "info", "error"])
        self.backend = QComboBox()
        backend_names = available_backend_names()
        self._backend_supported = bool(backend_names)
        if backend_names:
            self.backend.addItems(backend_names)
        else:
            self.backend.addItem("unsupported")
        self.advanced_form.addRow(self.copy.listen_host, self.listen_host)
        self.advanced_form.addRow(self.copy.listen_port, self.listen_port)
        self.advanced_form.addRow(self.copy.log_level, self.log_level)
        self.advanced_form.addRow(self.copy.backend, self.backend)
        layout.addLayout(self.advanced_form)

        return frame

    def _build_runtime_panel(self) -> QWidget:
        frame = QFrame()
        frame.setObjectName("SoftCard")
        layout = QVBoxLayout(frame)
        layout.setContentsMargins(18, 18, 18, 18)
        layout.setSpacing(14)

        stats_row = QHBoxLayout()
        stats_row.setSpacing(12)
        self.download_stat = self._build_stat_card(self.copy.download)
        self.upload_stat = self._build_stat_card(self.copy.upload)
        self.total_stat = self._build_stat_card(self.copy.total_usage)
        stats_row.addWidget(self.download_stat["card"])
        stats_row.addWidget(self.upload_stat["card"])
        stats_row.addWidget(self.total_stat["card"])
        layout.addLayout(stats_row)

        self.active_connections_label = QLabel(f"{self.copy.active_connections}: 0")
        self.active_connections_label.setObjectName("Caption")
        layout.addWidget(self.active_connections_label)

        self.details_labels: dict[str, QLabel] = {}
        self.details_toggle = QPushButton()
        self.details_toggle.clicked.connect(self.on_toggle_details)
        layout.addWidget(self.details_toggle)
        self.details_card = QFrame()
        self.details_card.setObjectName("Card")
        details_layout = QFormLayout(self.details_card)
        details_layout.setContentsMargins(14, 14, 14, 14)
        details_layout.setVerticalSpacing(10)
        for key in self._detail_keys:
            value = QLabel("-")
            value.setWordWrap(True)
            self.details_labels[key] = value
            details_layout.addRow(f"{self.copy.detail_label(key)}:", value)
        layout.addWidget(self.details_card)

        self.workflow_card = QFrame()
        self.workflow_card.setObjectName("Card")
        self.workflow_layout = QVBoxLayout(self.workflow_card)
        self.workflow_layout.setContentsMargins(14, 14, 14, 14)
        self.workflow_layout.setSpacing(8)
        self.workflow_toggle = QPushButton()
        self.workflow_toggle.clicked.connect(self.on_toggle_workflow)
        layout.addWidget(self.workflow_toggle)
        layout.addWidget(self.workflow_card)

        self.logs_section_label = self._section_label(self.copy.logs)
        layout.addWidget(self.logs_section_label)
        logs_actions = QHBoxLayout()
        logs_actions.setSpacing(8)
        self.copy_dump_button = QPushButton(self.copy.copy_diagnostic_dump)
        self.copy_dump_button.clicked.connect(self.on_copy_diagnostic_dump)
        self.clear_logs_button = QPushButton(self.copy.clear_logs)
        self.clear_logs_button.clicked.connect(self.on_clear_logs)
        logs_actions.addWidget(self.copy_dump_button)
        logs_actions.addWidget(self.clear_logs_button)
        logs_actions.addStretch(1)
        layout.addLayout(logs_actions)
        self.logs = QPlainTextEdit()
        self.logs.setReadOnly(True)
        self.logs.setPlaceholderText(self.copy.runtime_events_placeholder)
        self.logs.setMinimumHeight(210)
        layout.addWidget(self.logs, 1)

        self.error_banner = QLabel("")
        self.error_banner.setWordWrap(True)
        self.error_banner.setStyleSheet(
            "background: #fff1f2; color: #b42318; border: 1px solid #fecdd3; border-radius: 14px; padding: 12px;"
        )
        self.error_banner.hide()
        layout.addWidget(self.error_banner)

        return frame

    def _build_stat_card(self, title: str) -> dict[str, QWidget]:
        card = QFrame()
        card.setObjectName("Card")
        layout = QVBoxLayout(card)
        layout.setContentsMargins(14, 14, 14, 14)
        layout.setSpacing(6)
        heading = QLabel(title)
        heading.setObjectName("Section")
        value = QLabel("0 B")
        value.setStyleSheet("font-size: 24px; font-weight: 700; color: #233347;")
        layout.addWidget(heading)
        layout.addWidget(value)
        layout.addStretch(1)
        return {"card": card, "heading": heading, "value": value}

    def _field_group(self, title: str, widget: QWidget) -> QVBoxLayout:
        layout = QVBoxLayout()
        layout.setSpacing(6)
        label = QLabel(title)
        label.setObjectName("Section")
        layout.addWidget(label)
        layout.addWidget(widget)
        return layout

    def _section_label(self, title: str) -> QLabel:
        label = QLabel(title)
        label.setObjectName("Section")
        return label

    def _select_mode(self, mode: str) -> None:
        self.proxy_mode_button.setProperty("active", "true" if mode == ConnectionMode.PROXY.value else "false")
        self.tunnel_mode_button.setProperty("active", "true" if mode == ConnectionMode.TUNNEL.value else "false")
        self.proxy_mode_button.style().unpolish(self.proxy_mode_button)
        self.proxy_mode_button.style().polish(self.proxy_mode_button)
        self.tunnel_mode_button.style().unpolish(self.tunnel_mode_button)
        self.tunnel_mode_button.style().polish(self.tunnel_mode_button)
        self.enable_system_proxy.setVisible(mode == ConnectionMode.PROXY.value)
        self.proxy_toggle_hint.setVisible(mode == ConnectionMode.PROXY.value)
        self.refresh_ui_state()

    def load_config_to_form(self) -> None:
        config = self.runtime.config
        self.listen_host.setText(config.listen_host)
        self.listen_port.setText(str(config.listen_port))
        self.allowlist_domain.setText(config.whitelist_domain)
        self.allowlist_ip.setText(f"{config.whitelist_ip}:{config.whitelist_port}")
        self.proxy_link.setPlainText(config.proxy_link)
        self.log_level.setCurrentText(config.log_level)
        self.backend.setCurrentText(config.selected_backend())
        self.enable_system_proxy.setChecked(config.enable_system_proxy)
        language_index = self.language_picker.findData(AppLanguage.normalize(config.ui_language))
        if language_index >= 0:
            self.language_picker.setCurrentIndex(language_index)
        self._select_mode(config.connection_mode)

    def form_to_config(self) -> AppConfig:
        endpoint = self.allowlist_ip.text().strip()
        if not endpoint:
            raise ValueError("Allowlist IP is required.")
        if ":" in endpoint:
            whitelist_ip, port_text = endpoint.rsplit(":", 1)
            whitelist_port = int(port_text.strip())
        else:
            whitelist_ip = endpoint
            whitelist_port = 443
        selected_mode = ConnectionMode.PROXY.value if self.proxy_mode_button.property("active") == "true" else ConnectionMode.TUNNEL.value
        return self.runtime.config.updated(
            listen_host=self.listen_host.text().strip(),
            listen_port=int(self.listen_port.text().strip()),
            connect_ip=whitelist_ip.strip(),
            connect_port=whitelist_port,
            fake_sni=self.allowlist_domain.text().strip(),
            whitelist_domain=self.allowlist_domain.text().strip(),
            whitelist_ip=whitelist_ip.strip(),
            whitelist_port=whitelist_port,
            proxy_link=self.proxy_link.toPlainText().strip(),
            ui_language=self.current_language(),
            connection_mode=selected_mode,
            enable_system_proxy=self.enable_system_proxy.isChecked(),
            log_level=self.log_level.currentText().strip(),
            backend=self.backend.currentText().strip(),
        )

    def append_log(self, message: str) -> None:
        self.logs.appendPlainText(message)

    def refresh_ui_state(self) -> None:
        palette = {
            RuntimeState.STOPPED: "#94a3b8",
            RuntimeState.STARTING: "#3b82f6",
            RuntimeState.RUNNING: "#22c55e",
            RuntimeState.STOPPING: "#f59e0b",
            RuntimeState.ERROR: "#ef4444",
        }
        summary = self.runtime.summary
        self.status_headline.setText(self.copy.status_headline(self.runtime.state, summary.headline))
        self.status_detail.setText(summary.detail)
        self.status_dot.setStyleSheet(
            f"min-width: 12px; min-height: 12px; max-width: 12px; max-height: 12px; border-radius: 6px; background: {palette[self.runtime.state]};"
        )
        running = self.runtime.state in (RuntimeState.STARTING, RuntimeState.RUNNING, RuntimeState.STOPPING)
        self.connect_button.setEnabled((not running) and self._backend_supported)
        self.disconnect_button.setEnabled(running)
        self.details_labels["Mode"].setText(self.copy.mode_title(ConnectionMode.PROXY.value if self.proxy_mode_button.property("active") == "true" else ConnectionMode.TUNNEL.value))
        self.details_labels["Connection"].setText(summary.detail)
        self.details_labels["Allowlist"].setText(summary.active_summary)
        self.details_labels["System Route"].setText(summary.route_summary)
        self.details_labels["Original Server"].setText(summary.original_server_summary)
        self.details_labels["Probe"].setText(summary.probe_summary)
        traffic = self.runtime.traffic_snapshot
        self.download_stat["value"].setText(self._format_bytes(traffic.bytes_downloaded))
        self.upload_stat["value"].setText(self._format_bytes(traffic.bytes_uploaded))
        self.total_stat["value"].setText(self._format_bytes(traffic.total_bytes))
        self.active_connections_label.setText(f"{self.copy.active_connections}: {traffic.active_connections}")
        self._render_workflow()
        self.details_card.setVisible(self._details_expanded)
        self.workflow_card.setVisible(self._workflow_expanded)
        self.details_toggle.setText(f"{self.copy.details} • {self.copy.hide if self._details_expanded else self.copy.show}")
        self.workflow_toggle.setText(f"{self.copy.workflow} • {self.copy.workflow_subtitle(len(self.runtime.workflow_steps))} • {self.copy.hide if self._workflow_expanded else self.copy.show}")
        if self.runtime.last_error:
            self.error_banner.setText(self.runtime.last_error)
            self.error_banner.show()
        else:
            self.error_banner.hide()

    def _render_workflow(self) -> None:
        while self.workflow_layout.count():
            child = self.workflow_layout.takeAt(0)
            widget = child.widget()
            if widget is not None:
                widget.deleteLater()
        color_map = {
            WorkflowStepState.PENDING: "#94a3b8",
            WorkflowStepState.RUNNING: "#3b82f6",
            WorkflowStepState.SUCCESS: "#22c55e",
            WorkflowStepState.FAILURE: "#ef4444",
            WorkflowStepState.SKIPPED: "#64748b",
        }
        for step in self.runtime.workflow_steps:
            row = QFrame()
            row.setObjectName("SoftCard")
            row_layout = QHBoxLayout(row)
            row_layout.setContentsMargins(12, 10, 12, 10)
            row_layout.setSpacing(10)
            dot = QLabel()
            dot.setStyleSheet(
                f"min-width: 10px; min-height: 10px; max-width: 10px; max-height: 10px; border-radius: 5px; background: {color_map[step.state]};"
            )
            texts = QVBoxLayout()
            title = QLabel(self.copy.workflow_title(step.key, step.title))
            title.setStyleSheet("font-weight: 700; color: #233347;")
            detail = QLabel(step.detail)
            detail.setWordWrap(True)
            detail.setStyleSheet("color: #6d7f95;")
            texts.addWidget(title)
            texts.addWidget(detail)
            state = QLabel(self.copy.workflow_state(step.state))
            state.setStyleSheet("color: #6d7f95; font-weight: 600;")
            row_layout.addWidget(dot)
            row_layout.addLayout(texts, 1)
            row_layout.addWidget(state)
            self.workflow_layout.addWidget(row)
        self.workflow_layout.addStretch(1)

    def poll_runtime(self) -> None:
        for event in self.runtime.drain_events():
            if event.level == "error":
                self.append_log(f"[ERROR] {event.message}")
            elif event.level == "state":
                self.append_log(f"[STATE] {event.message}")
            else:
                self.append_log(f"[{event.level.upper()}] {event.message}")
        self.refresh_ui_state()

    def on_save(self) -> bool:
        try:
            config = self.form_to_config()
        except ValueError as exc:
            self.append_log(f"[ERROR] {exc}")
            return False
        try:
            self.runtime.save_config(config)
        except Exception as exc:
            self.append_log(f"[ERROR] {type(exc).__name__}: {exc}")
            return False
        self.load_config_to_form()
        self.copy = DesktopCopy(self.current_language())
        self.append_log(f"[INFO] {self.copy.configuration_saved}")
        return True

    def on_start(self) -> None:
        if not self.on_save():
            return
        self.runtime.start()
        self.append_log(f"[INFO] {self.copy.start_requested}")

    def on_stop(self) -> None:
        self.runtime.stop()
        self.append_log(f"[INFO] {self.copy.stop_requested}")

    def on_copy_diagnostic_dump(self) -> None:
        QApplication.clipboard().setText(self.runtime.diagnostic_dump())
        self.append_log(f"[INFO] {self.copy.diagnostic_dump_copied}")

    def on_clear_logs(self) -> None:
        self.logs.clear()
        self.append_log(f"[INFO] {self.copy.logs_cleared}")

    def on_toggle_details(self) -> None:
        self._details_expanded = not self._details_expanded
        self.refresh_ui_state()

    def on_toggle_workflow(self) -> None:
        self._workflow_expanded = not self._workflow_expanded
        self.refresh_ui_state()

    def current_language(self) -> str:
        return AppLanguage.normalize(self.language_picker.currentData() or self.runtime.config.ui_language)

    def on_language_changed(self) -> None:
        self.copy = DesktopCopy(self.current_language())
        self._retranslate_ui()
        self.runtime.update_config(ui_language=self.current_language())
        self.refresh_ui_state()

    def _retranslate_ui(self) -> None:
        self.setWindowTitle(self.copy.app_title)
        self.title_label.setText(self.copy.app_title)
        self.subtitle_label.setText(self.copy.app_subtitle)
        self.language_label.setText(self.copy.language_label)
        self.connect_button.setText(self.copy.connect)
        self.disconnect_button.setText(self.copy.disconnect)
        self.save_button.setText(self.copy.save_profile)
        self.proxy_mode_button.setText(self.copy.proxy)
        self.tunnel_mode_button.setText(self.copy.tunnel)
        self.enable_system_proxy.setText(self.copy.auto_proxy_title)
        self.proxy_toggle_hint.setText(self.copy.auto_proxy_hint)
        self.proxy_link.setPlaceholderText(self.copy.proxy_link_placeholder)
        self.copy_dump_button.setText(self.copy.copy_diagnostic_dump)
        self.clear_logs_button.setText(self.copy.clear_logs)
        self.logs.setPlaceholderText(self.copy.runtime_events_placeholder)
        self.connection_mode_label.setText(self.copy.connection_mode)
        self.connection_section_label.setText(self.copy.connection)
        self.allowlist_domain_group.itemAt(0).widget().setText(self.copy.step1_domain)
        self.allowlist_ip_group.itemAt(0).widget().setText(self.copy.step1_ip)
        self.proxy_config_section_label.setText(self.copy.step2_proxy)
        self.logs_section_label.setText(self.copy.logs)
        self.download_stat["heading"].setText(self.copy.download)
        self.upload_stat["heading"].setText(self.copy.upload)
        self.total_stat["heading"].setText(self.copy.total_usage)
        for index, value in enumerate([AppLanguage.ENGLISH, AppLanguage.PERSIAN]):
            self.language_picker.setItemText(index, self.copy.language_name(value))
        while self.workflow_layout.count():
            break
        for row in range(self.details_card.layout().rowCount()):
            label_item = self.details_card.layout().itemAt(row, QFormLayout.ItemRole.LabelRole)
            if label_item is not None and label_item.widget() is not None:
                key = self._detail_keys[row]
                label_item.widget().setText(f"{self.copy.detail_label(key)}:")
        for row, label_text in enumerate([self.copy.listen_host, self.copy.listen_port, self.copy.log_level, self.copy.backend]):
            label_item = self.advanced_form.itemAt(row, QFormLayout.ItemRole.LabelRole)
            if label_item is not None and label_item.widget() is not None:
                label_item.widget().setText(label_text)

    def _format_bytes(self, value: int) -> str:
        units = ["B", "KB", "MB", "GB", "TB"]
        size = float(value)
        unit_index = 0
        while size >= 1024 and unit_index < len(units) - 1:
            size /= 1024
            unit_index += 1
        if unit_index == 0:
            return f"{int(size)} {units[unit_index]}"
        return f"{size:.1f} {units[unit_index]}"

    def closeEvent(self, event) -> None:  # noqa: N802
        self.runtime.stop()
        super().closeEvent(event)


def _configure_application(app: QApplication) -> None:
    app.setStyle("Fusion")
    palette = QPalette()
    palette.setColor(QPalette.ColorRole.Window, QColor("#eef3fa"))
    palette.setColor(QPalette.ColorRole.WindowText, QColor("#233347"))
    palette.setColor(QPalette.ColorRole.Base, QColor("#ffffff"))
    palette.setColor(QPalette.ColorRole.AlternateBase, QColor("#f8fbff"))
    palette.setColor(QPalette.ColorRole.ToolTipBase, QColor("#233347"))
    palette.setColor(QPalette.ColorRole.ToolTipText, QColor("#ffffff"))
    palette.setColor(QPalette.ColorRole.Text, QColor("#233347"))
    palette.setColor(QPalette.ColorRole.Button, QColor("#ffffff"))
    palette.setColor(QPalette.ColorRole.ButtonText, QColor("#233347"))
    palette.setColor(QPalette.ColorRole.Highlight, QColor("#2d6cdf"))
    palette.setColor(QPalette.ColorRole.HighlightedText, QColor("#ffffff"))
    app.setPalette(palette)
    app.setFont(QFont("Segoe UI", 10))


def main(config_path: str | None = None) -> int:
    app = QApplication(sys.argv)
    _configure_application(app)
    app.setStyleSheet(APP_STYLESHEET)
    runtime = AppRuntime(config_path)
    window = MainWindow(runtime)
    window.show()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
