from __future__ import annotations

import sys

from PySide6.QtCore import QTimer, Qt
from PySide6.QtGui import QColor, QFont, QPalette
from PySide6.QtWidgets import (
    QApplication,
    QButtonGroup,
    QCheckBox,
    QComboBox,
    QDialog,
    QFormLayout,
    QFrame,
    QGraphicsDropShadowEffect,
    QGridLayout,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMainWindow,
    QPushButton,
    QPlainTextEdit,
    QScrollArea,
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
    background: #f4f7fa;
    color: #2c3e50;
    font-family: Segoe UI Variable, Segoe UI, Arial, sans-serif;
    font-size: 14px;
}
QMainWindow {
    background: #f4f7fa;
}
QFrame#MainCard {
    background: #ffffff;
    border: 1px solid #e2e8f0;
    border-radius: 26px;
}
QFrame#Panel {
    background: #f8fafc;
    border: 1px solid #e2e8f0;
    border-radius: 16px;
}
QFrame#StatCard {
    background: #f8fafc;
    border: 1px solid #e2e8f0;
    border-radius: 16px;
}
QFrame#StatusBadge {
    background: #f8fafc;
    border: 1px solid #e2e8f0;
    border-radius: 24px;
}
QFrame#StatusBadge[status="running"] {
    background: #ecfdf3;
    border: 1px solid #bbf7d0;
}
QFrame#StatusBadge[status="error"] {
    background: #fff1f2;
    border: 1px solid #fecdd3;
}
QFrame#Segmented {
    background: rgba(255, 255, 255, 220);
    border: 1px solid #e2e8f0;
    border-radius: 16px;
}
QFrame#InfoPill {
    background: rgba(255, 255, 255, 210);
    border: 1px solid #e2e8f0;
    border-radius: 14px;
}
QLabel#Title {
    font-size: 30px;
    font-weight: 700;
    color: #2c3e50;
}
QLabel#Subtitle {
    color: #64748b;
    font-size: 14px;
    font-weight: 600;
}
QLabel#Section {
    font-size: 16px;
    font-weight: 700;
    color: #64748b;
}
QLabel#Caption {
    color: #64748b;
    font-size: 13px;
    font-weight: 600;
}
QLabel#InfoPillText {
    color: #64748b;
    font-size: 12px;
    font-weight: 700;
}
QLabel#ConnectionTitle {
    font-size: 30px;
    font-weight: 700;
    color: #2c3e50;
}
QLabel#StatusHeadline {
    font-size: 22px;
    font-weight: 800;
    color: #2c3e50;
}
QLabel#StatusDot {
    min-width: 44px;
    min-height: 44px;
    max-width: 44px;
    max-height: 44px;
    border-radius: 22px;
    background: #94a3b8;
    color: #ffffff;
    font-size: 24px;
    font-weight: 900;
}
QLineEdit, QComboBox, QTextEdit, QPlainTextEdit {
    background: #ffffff;
    border: 1px solid #e2e8f0;
    border-radius: 14px;
    padding: 13px 18px;
    selection-background-color: #7aa7ff;
    color: #2c3e50;
    font-size: 15px;
    font-weight: 600;
}
QTextEdit {
    font-family: Cascadia Mono, Consolas, monospace;
    color: #64748b;
    font-size: 15px;
}
QPlainTextEdit {
    font-family: Cascadia Mono, Consolas, monospace;
    font-size: 12px;
}
QPushButton {
    background: #f8fafc;
    border: 1px solid #e2e8f0;
    border-radius: 14px;
    padding: 12px 18px;
    min-height: 22px;
    color: #2c3e50;
    font-weight: 700;
}
QPushButton:hover {
    background: #ffffff;
}
QPushButton#Primary {
    background: #2c3e50;
    border: 1px solid #2c3e50;
    color: white;
    font-size: 15px;
}
QPushButton#Secondary {
    background: #ffffff;
    border: 1px solid #e2e8f0;
    color: #2c3e50;
}
QPushButton#ModeButton[active="true"] {
    background: #1e6fff;
    border: 1px solid #1e6fff;
    color: white;
}
QPushButton#ModeButton {
    min-width: 92px;
    min-height: 36px;
    border-radius: 12px;
    border: 0;
    background: transparent;
    color: #94a3b8;
    font-size: 16px;
    font-weight: 800;
}
QPushButton#FlagButton {
    min-width: 56px;
    max-width: 56px;
    min-height: 56px;
    max-height: 56px;
    border-radius: 28px;
    background: #ffffff;
    border: 1px solid #e2e8f0;
    font-size: 16px;
    font-weight: 900;
    padding: 0;
}
QPushButton#IconButton {
    min-width: 34px;
    max-width: 34px;
    min-height: 34px;
    max-height: 34px;
    border-radius: 17px;
    background: rgba(255, 255, 255, 210);
    border: 0;
    color: #64748b;
    font-size: 11px;
    font-weight: 900;
    padding: 0;
}
QCheckBox {
    spacing: 16px;
    color: #94a3b8;
    font-size: 16px;
    font-weight: 800;
}
QCheckBox::indicator {
    width: 22px;
    height: 22px;
}
QCheckBox::indicator:unchecked {
    border: 2px solid #cbd5e1;
    background: #ffffff;
    border-radius: 5px;
}
QCheckBox::indicator:checked {
    border: 2px solid #1e6fff;
    background: #1e6fff;
    border-radius: 5px;
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
        self._workflow_render_signature: tuple[tuple[str, str, str], ...] | None = None
        self.setWindowTitle(self.copy.app_title)
        self.setMinimumSize(1180, 780)

        central = QWidget(self)
        self.setCentralWidget(central)

        outer_layout = QVBoxLayout(central)
        outer_layout.setContentsMargins(0, 0, 0, 0)

        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QFrame.Shape.NoFrame)
        scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        outer_layout.addWidget(scroll)

        page = QWidget()
        scroll.setWidget(page)
        root_layout = QVBoxLayout(page)
        root_layout.setContentsMargins(22, 20, 22, 20)
        root_layout.setSpacing(16)

        root_layout.addWidget(self._build_header())
        root_layout.addWidget(self._build_main_card(), 1)
        root_layout.addWidget(self._build_footer())

        self.timer = QTimer(self)
        self.timer.setInterval(150)
        self.timer.timeout.connect(self.poll_runtime)
        self.timer.start()

        self.load_config_to_form()
        self.refresh_ui_state()

    def _apply_shadow(self, widget: QWidget, blur: int = 24, y: int = 10, alpha: int = 18) -> None:
        shadow = QGraphicsDropShadowEffect(widget)
        shadow.setBlurRadius(blur)
        shadow.setOffset(0, y)
        shadow.setColor(QColor(15, 23, 42, alpha))
        widget.setGraphicsEffect(shadow)

    def _build_header(self) -> QWidget:
        frame = QWidget()
        layout = QHBoxLayout(frame)
        layout.setContentsMargins(18, 12, 18, 6)
        layout.setSpacing(18)

        copy_layout = QVBoxLayout()
        copy_layout.setSpacing(7)
        self.title_label = QLabel(self.copy.app_title)
        self.title_label.setObjectName("Title")
        self.subtitle_label = QLabel(self.copy.app_subtitle)
        self.subtitle_label.setObjectName("Subtitle")
        self.subtitle_label.setWordWrap(True)
        copy_layout.addWidget(self.title_label)
        copy_layout.addWidget(self.subtitle_label)

        layout.addLayout(copy_layout, 1)

        layout.addWidget(self._build_mode_switch())

        self.language_picker = QComboBox()
        self.language_picker.addItem(self.copy.language_name(AppLanguage.ENGLISH), AppLanguage.ENGLISH)
        self.language_picker.addItem(self.copy.language_name(AppLanguage.PERSIAN), AppLanguage.PERSIAN)
        self.language_picker.currentIndexChanged.connect(self.on_language_changed)
        self.language_picker.hide()
        self.language_button = QPushButton("EN")
        self.language_button.setObjectName("FlagButton")
        self.language_button.clicked.connect(self.on_toggle_language)
        layout.addWidget(self.language_button)

        return frame

    def _build_main_card(self) -> QWidget:
        frame = QFrame()
        frame.setObjectName("MainCard")
        self._apply_shadow(frame)
        layout = QVBoxLayout(frame)
        layout.setContentsMargins(26, 26, 26, 26)
        layout.setSpacing(22)

        header_row = QHBoxLayout()
        header_row.setSpacing(18)
        title_col = QVBoxLayout()
        title_col.setSpacing(7)
        self.connection_section_label = QLabel(self.copy.connection)
        self.connection_section_label.setObjectName("ConnectionTitle")
        self.connection_hint_label = QLabel("Set the allowlist and proxy config, then connect.")
        self.connection_hint_label.setObjectName("Subtitle")
        title_col.addWidget(self.connection_section_label)
        title_col.addWidget(self.connection_hint_label)
        header_row.addLayout(title_col, 1)
        header_row.addWidget(self._build_status_badge())
        layout.addLayout(header_row)

        layout.addWidget(self._build_connection_panel())
        self.stats_panel = self._build_stats_panel()
        layout.addWidget(self.stats_panel)

        sections_row = QHBoxLayout()
        sections_row.setSpacing(14)
        self.details_toggle = QPushButton()
        self.details_toggle.setMinimumHeight(72)
        self.details_toggle.clicked.connect(self.on_toggle_details)
        self.workflow_toggle = QPushButton()
        self.workflow_toggle.setMinimumHeight(72)
        self.workflow_toggle.clicked.connect(self.on_toggle_workflow)
        sections_row.addWidget(self.details_toggle, 1)
        sections_row.addWidget(self.workflow_toggle, 1)
        layout.addLayout(sections_row)

        self.details_card = QFrame()
        self.details_card.setObjectName("Panel")
        details_layout = QFormLayout(self.details_card)
        details_layout.setContentsMargins(18, 16, 18, 16)
        details_layout.setVerticalSpacing(10)
        self.details_labels: dict[str, QLabel] = {}
        for key in self._detail_keys:
            value = QLabel("-")
            value.setWordWrap(True)
            self.details_labels[key] = value
            details_layout.addRow(f"{self.copy.detail_label(key)}:", value)
        layout.addWidget(self.details_card)

        self.workflow_card = QFrame()
        self.workflow_card.setObjectName("Panel")
        self.workflow_layout = QVBoxLayout(self.workflow_card)
        self.workflow_layout.setContentsMargins(18, 16, 18, 16)
        self.workflow_layout.setSpacing(10)
        layout.addWidget(self.workflow_card)

        self.error_banner = QLabel("")
        self.error_banner.setWordWrap(True)
        self.error_banner.setStyleSheet(
            "background: #fff1f2; color: #b42318; border: 1px solid #fecdd3; border-radius: 14px; padding: 14px;"
        )
        self.error_banner.hide()
        layout.addWidget(self.error_banner)

        action_row = QHBoxLayout()
        action_row.setSpacing(12)
        self.connect_button = QPushButton(self.copy.connect)
        self.connect_button.setObjectName("Primary")
        self.connect_button.clicked.connect(self.on_primary_action)
        self.logs_button = QPushButton(self.copy.logs)
        self.logs_button.setObjectName("Secondary")
        self.logs_button.clicked.connect(self.on_show_logs)
        action_row.addWidget(self.connect_button, 1)
        action_row.addWidget(self.logs_button, 1)
        layout.addLayout(action_row)

        self.disconnect_button = QPushButton(self.copy.disconnect)
        self.disconnect_button.clicked.connect(self.on_stop)
        self.disconnect_button.hide()
        self.save_button = QPushButton(self.copy.save_profile)
        self.save_button.clicked.connect(self.on_save)
        self.save_button.hide()

        self.logs_section_label = QLabel(self.copy.logs)
        self.logs = QPlainTextEdit()
        self.logs.setReadOnly(True)
        self.logs.setPlaceholderText(self.copy.runtime_events_placeholder)
        self.copy_dump_button = QPushButton(self.copy.copy_diagnostic_dump)
        self.copy_dump_button.clicked.connect(self.on_copy_diagnostic_dump)
        self.clear_logs_button = QPushButton(self.copy.clear_logs)
        self.clear_logs_button.clicked.connect(self.on_clear_logs)

        return frame

    def _build_mode_switch(self) -> QWidget:
        frame = QFrame()
        frame.setObjectName("Segmented")
        layout = QHBoxLayout(frame)
        layout.setContentsMargins(5, 5, 5, 5)
        layout.setSpacing(0)
        self.connection_mode_label = QLabel(self.copy.connection_mode)
        self.connection_mode_label.hide()

        self.mode_group = QButtonGroup(self)
        self.proxy_mode_button = QPushButton(self.copy.proxy)
        self.proxy_mode_button.setObjectName("ModeButton")
        self.proxy_mode_button.clicked.connect(lambda: self._select_mode(ConnectionMode.PROXY.value))
        self.tunnel_mode_button = QPushButton(self.copy.tunnel)
        self.tunnel_mode_button.setObjectName("ModeButton")
        self.tunnel_mode_button.clicked.connect(lambda: self._select_mode(ConnectionMode.TUNNEL.value))
        self.tunnel_mode_button.setToolTip("Windows Tunnel mode is not implemented yet.")
        self.mode_group.addButton(self.proxy_mode_button)
        self.mode_group.addButton(self.tunnel_mode_button)
        layout.addWidget(self.proxy_mode_button)
        layout.addWidget(self.tunnel_mode_button)
        return frame

    def _build_status_badge(self) -> QWidget:
        self.status_card = QFrame()
        self.status_card.setObjectName("StatusBadge")
        self.status_card.setMinimumWidth(430)
        layout = QHBoxLayout(self.status_card)
        layout.setContentsMargins(16, 12, 20, 12)
        layout.setSpacing(14)
        self.status_dot = QLabel("✓")
        self.status_dot.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.status_dot.setObjectName("StatusDot")
        self.status_headline = QLabel(self.copy.ready_headline)
        self.status_headline.setObjectName("StatusHeadline")
        self.status_detail = QLabel("")
        self.status_detail.hide()
        layout.addWidget(self.status_dot)
        layout.addWidget(self.status_headline)
        return self.status_card

    def _build_footer(self) -> QWidget:
        frame = QWidget()
        layout = QHBoxLayout(frame)
        layout.setContentsMargins(18, 0, 18, 0)
        layout.setSpacing(8)
        layout.addWidget(self._info_pill("i", "v1.2.1"))
        layout.addWidget(self._info_pill("●", "by PK3NZO"))
        layout.addStretch(1)
        layout.addWidget(self._info_pill("♥", "Shoutout to patterniha for his great project"))
        return frame

    def _info_pill(self, icon: str, text: str) -> QWidget:
        pill = QFrame()
        pill.setObjectName("InfoPill")
        layout = QHBoxLayout(pill)
        layout.setContentsMargins(10, 7, 10, 7)
        layout.setSpacing(6)
        icon_label = QLabel(icon)
        icon_label.setObjectName("InfoPillText")
        text_label = QLabel(text)
        text_label.setObjectName("InfoPillText")
        layout.addWidget(icon_label)
        layout.addWidget(text_label)
        return pill

    def _build_connection_panel(self) -> QWidget:
        frame = QWidget()
        layout = QVBoxLayout(frame)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(18)

        row = QHBoxLayout()
        row.setSpacing(18)

        self.allowlist_domain = QLineEdit()
        self.allowlist_ip = QLineEdit()
        self.allowlist_domain.setMinimumHeight(56)
        self.allowlist_ip.setMinimumHeight(56)

        self.allowlist_domain_group = self._field_group(self.copy.step1_domain, self.allowlist_domain)
        self.allowlist_ip_group = self._field_group(self.copy.step1_ip, self.allowlist_ip)
        row.addLayout(self.allowlist_domain_group)
        row.addLayout(self.allowlist_ip_group)
        layout.addLayout(row)

        self.proxy_link = QTextEdit()
        self.proxy_link.setPlaceholderText(self.copy.proxy_link_placeholder)
        self.proxy_link.setMinimumHeight(142)
        self.proxy_config_section_label = self._section_label(self.copy.step2_proxy)
        layout.addWidget(self.proxy_config_section_label)
        proxy_editor = QWidget()
        proxy_editor_layout = QGridLayout(proxy_editor)
        proxy_editor_layout.setContentsMargins(0, 0, 0, 0)
        proxy_editor_layout.setSpacing(0)
        self.proxy_visibility_button = QPushButton("EYE")
        self.proxy_visibility_button.setObjectName("IconButton")
        self.proxy_visibility_button.setToolTip("Show / hide config")
        proxy_editor_layout.addWidget(self.proxy_link, 0, 0)
        proxy_editor_layout.addWidget(
            self.proxy_visibility_button,
            0,
            0,
            Qt.AlignmentFlag.AlignTop | Qt.AlignmentFlag.AlignRight,
        )
        layout.addWidget(proxy_editor)

        proxy_toggle_card = QFrame()
        proxy_toggle_card.setObjectName("Panel")
        proxy_toggle_layout = QVBoxLayout(proxy_toggle_card)
        proxy_toggle_layout.setContentsMargins(18, 14, 18, 14)
        proxy_toggle_layout.setSpacing(5)
        self.enable_system_proxy = QCheckBox(self.copy.auto_proxy_title)
        self.enable_system_proxy.setChecked(True)
        self.proxy_toggle_hint = QLabel(self.copy.auto_proxy_hint)
        self.proxy_toggle_hint.setObjectName("Subtitle")
        self.proxy_toggle_hint.setWordWrap(True)
        proxy_toggle_layout.addWidget(self.enable_system_proxy)
        proxy_toggle_layout.addWidget(self.proxy_toggle_hint)
        layout.addWidget(proxy_toggle_card)

        self.advanced_form = QFormLayout()
        self.advanced_form.setVerticalSpacing(12)
        self.listen_host = QLineEdit()
        self.listen_port = QLineEdit()
        self.inbound_host = QLineEdit()
        self.socks_port = QLineEdit()
        self.http_port = QLineEdit()
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
        self.advanced_form.addRow(self.copy.inbound_host, self.inbound_host)
        self.advanced_form.addRow(self.copy.socks_port, self.socks_port)
        self.advanced_form.addRow(self.copy.http_port, self.http_port)
        self.advanced_form.addRow(self.copy.log_level, self.log_level)
        self.advanced_form.addRow(self.copy.backend, self.backend)
        advanced_holder = QWidget()
        advanced_holder.setLayout(self.advanced_form)
        advanced_holder.hide()
        self.advanced_holder = advanced_holder
        layout.addWidget(advanced_holder)

        return frame

    def _build_stats_panel(self) -> QWidget:
        frame = QWidget()
        layout = QVBoxLayout(frame)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(12)

        stats_row = QHBoxLayout()
        stats_row.setSpacing(14)
        self.download_stat = self._build_stat_card(self.copy.download, "↓", "#22c55e")
        self.upload_stat = self._build_stat_card(self.copy.upload, "↑", "#0ea5e9")
        self.total_stat = self._build_stat_card(self.copy.total_usage, "▮", "#fb923c")
        stats_row.addWidget(self.download_stat["card"])
        stats_row.addWidget(self.upload_stat["card"])
        stats_row.addWidget(self.total_stat["card"])
        layout.addLayout(stats_row)

        self.active_connections_label = QLabel(f"{self.copy.active_connections}: 0")
        self.active_connections_label.setObjectName("Caption")
        self.active_connections_label.hide()
        layout.addWidget(self.active_connections_label)

        return frame

    def _build_stat_card(self, title: str, icon: str, color: str) -> dict[str, QWidget]:
        card = QFrame()
        card.setObjectName("StatCard")
        card.setMinimumHeight(122)
        layout = QHBoxLayout(card)
        layout.setContentsMargins(24, 18, 24, 18)
        layout.setSpacing(16)
        icon_label = QLabel(icon)
        icon_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        icon_label.setStyleSheet(
            f"min-width: 42px; min-height: 42px; max-width: 42px; max-height: 42px; border-radius: 21px; "
            f"background: rgba(14, 165, 233, 28); color: {color}; font-size: 28px; font-weight: 900;"
        )
        text_col = QVBoxLayout()
        text_col.setSpacing(9)
        heading = QLabel(title)
        heading.setObjectName("Section")
        value = QLabel("0 B")
        value.setStyleSheet("font-size: 28px; font-weight: 800; color: #2c3e50;")
        text_col.addWidget(heading)
        text_col.addWidget(value)
        layout.addWidget(icon_label)
        layout.addLayout(text_col, 1)
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
        if mode == ConnectionMode.TUNNEL.value:
            self.append_log("[ERROR] Windows Tunnel mode is not implemented yet.")
            mode = ConnectionMode.PROXY.value
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
        self.inbound_host.setText(config.inbound_host)
        self.socks_port.setText(str(config.socks_port))
        self.http_port.setText(str(config.http_port))
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
            inbound_host=self.inbound_host.text().strip(),
            socks_port=int(self.socks_port.text().strip()),
            http_port=int(self.http_port.text().strip()),
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
        status_text = self._status_badge_text(summary.headline)
        self.status_headline.setText(self.copy.status_headline(self.runtime.state, status_text))
        self.status_detail.setText(summary.detail)
        status_name = "running" if self.runtime.state == RuntimeState.RUNNING else "error" if self.runtime.state == RuntimeState.ERROR else "idle"
        self.status_card.setProperty("status", status_name)
        self.status_card.style().unpolish(self.status_card)
        self.status_card.style().polish(self.status_card)
        status_icon = "✓" if self.runtime.state == RuntimeState.RUNNING else "!" if self.runtime.state == RuntimeState.ERROR else "•"
        self.status_dot.setText(status_icon)
        self.status_dot.setStyleSheet(
            f"min-width: 44px; min-height: 44px; max-width: 44px; max-height: 44px; border-radius: 22px; "
            f"background: {palette[self.runtime.state]}; color: white; font-size: 24px; font-weight: 900;"
        )
        running = self.runtime.state in (RuntimeState.STARTING, RuntimeState.RUNNING, RuntimeState.STOPPING)
        self.connect_button.setText(self.copy.disconnect if running else self.copy.connect)
        self.connect_button.setEnabled(self._backend_supported and self.runtime.state != RuntimeState.STOPPING)
        self.disconnect_button.setEnabled(running)
        self.details_labels["Mode"].setText(self.copy.mode_title(ConnectionMode.PROXY.value if self.proxy_mode_button.property("active") == "true" else ConnectionMode.TUNNEL.value))
        self.details_labels["Connection"].setText(summary.detail)
        self.details_labels["Allowlist"].setText(summary.active_summary)
        self.details_labels["System Route"].setText(summary.route_summary)
        self.details_labels["Original Server"].setText(summary.original_server_summary)
        self.details_labels["Probe"].setText(summary.probe_summary)
        traffic = self.runtime.traffic_snapshot
        self.stats_panel.setVisible(self.runtime.state == RuntimeState.RUNNING)
        self.download_stat["value"].setText(self._format_bytes(traffic.bytes_downloaded))
        self.upload_stat["value"].setText(self._format_bytes(traffic.bytes_uploaded))
        self.total_stat["value"].setText(self._format_bytes(traffic.total_bytes))
        self.active_connections_label.setText(f"{self.copy.active_connections}: {traffic.active_connections}")
        self._render_workflow()
        self.details_card.setVisible(self._details_expanded)
        self.workflow_card.setVisible(self._workflow_expanded)
        self.details_toggle.setText(
            f"{'⌄' if self._details_expanded else '›'}  {self.copy.details}\n{summary.detail or '-'}     {self.copy.hide if self._details_expanded else self.copy.show}"
        )
        self.workflow_toggle.setText(
            f"{'⌄' if self._workflow_expanded else '›'}  {self.copy.workflow}\n{self.copy.workflow_subtitle(len(self.runtime.workflow_steps))}     {self.copy.hide if self._workflow_expanded else self.copy.show}"
        )
        if self.runtime.last_error:
            self.error_banner.setText(self.runtime.last_error)
            self.error_banner.show()
        else:
            self.error_banner.hide()

    def _status_badge_text(self, headline: str) -> str:
        if self.runtime.state == RuntimeState.RUNNING:
            if "SOCKS" in headline:
                return headline
            return headline or "Connected"
        if self.runtime.state == RuntimeState.STARTING:
            return "Connecting"
        if self.runtime.state == RuntimeState.STOPPING:
            return "Disconnecting"
        if self.runtime.state == RuntimeState.ERROR:
            return "Connection Failed"
        return self.copy.ready_headline

    def _render_workflow(self) -> None:
        signature = tuple(
            (step.key.value, step.state.value, step.detail)
            for step in self.runtime.workflow_steps
        )
        if signature == self._workflow_render_signature:
            return
        self._workflow_render_signature = signature
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
            row.setObjectName("Panel")
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

    def on_primary_action(self) -> None:
        if self.runtime.state in (RuntimeState.STARTING, RuntimeState.RUNNING):
            self.on_stop()
            return
        self.on_start()

    def on_stop(self) -> None:
        self.runtime.stop()
        self.append_log(f"[INFO] {self.copy.stop_requested}")

    def on_copy_diagnostic_dump(self) -> None:
        QApplication.clipboard().setText(self.runtime.diagnostic_dump())
        self.append_log(f"[INFO] {self.copy.diagnostic_dump_copied}")

    def on_clear_logs(self) -> None:
        self.logs.clear()
        self.append_log(f"[INFO] {self.copy.logs_cleared}")

    def on_show_logs(self) -> None:
        dialog = QDialog(self)
        dialog.setWindowTitle(self.copy.logs)
        dialog.resize(860, 560)
        layout = QVBoxLayout(dialog)
        layout.setContentsMargins(18, 18, 18, 18)
        layout.setSpacing(12)
        actions = QHBoxLayout()
        actions.setSpacing(10)
        copy_button = QPushButton(self.copy.copy_diagnostic_dump)
        copy_button.clicked.connect(self.on_copy_diagnostic_dump)
        clear_button = QPushButton(self.copy.clear_logs)
        clear_button.clicked.connect(self.on_clear_logs)
        actions.addWidget(copy_button)
        actions.addWidget(clear_button)
        actions.addStretch(1)
        layout.addLayout(actions)
        log_view = QPlainTextEdit()
        log_view.setReadOnly(True)
        log_view.setPlainText(self.logs.toPlainText())
        layout.addWidget(log_view, 1)
        dialog.exec()

    def on_toggle_language(self) -> None:
        next_language = AppLanguage.PERSIAN if self.current_language() == AppLanguage.ENGLISH else AppLanguage.ENGLISH
        index = self.language_picker.findData(next_language)
        if index >= 0:
            self.language_picker.setCurrentIndex(index)

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
        self._workflow_render_signature = None
        self._retranslate_ui()
        self.runtime.update_config(ui_language=self.current_language())
        self.refresh_ui_state()

    def _retranslate_ui(self) -> None:
        self.setWindowTitle(self.copy.app_title)
        self.title_label.setText(self.copy.app_title)
        self.subtitle_label.setText(self.copy.app_subtitle)
        self.language_button.setText("FA" if self.current_language() == AppLanguage.PERSIAN else "EN")
        self.connect_button.setText(self.copy.connect)
        self.logs_button.setText(self.copy.logs)
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
        self.connection_hint_label.setText(self.copy.ready_detail)
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
        for row, label_text in enumerate([
            self.copy.listen_host,
            self.copy.listen_port,
            self.copy.inbound_host,
            self.copy.socks_port,
            self.copy.http_port,
            self.copy.log_level,
            self.copy.backend,
        ]):
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
