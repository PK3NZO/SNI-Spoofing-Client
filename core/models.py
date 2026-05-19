from __future__ import annotations

from dataclasses import dataclass
from enum import Enum


class ConnectionMode(str, Enum):
    PROXY = "proxy"
    TUNNEL = "tunnel"


class WorkflowStepKey(str, Enum):
    WHITELIST = "whitelist"
    PROXY_CONFIG = "proxy_config"
    LOCAL_PROXY = "local_proxy"
    XRAY = "xray"
    SYSTEM_ROUTE = "system_route"
    PROBE = "probe"


class WorkflowStepState(str, Enum):
    PENDING = "pending"
    RUNNING = "running"
    SUCCESS = "success"
    FAILURE = "failure"
    SKIPPED = "skipped"


@dataclass(frozen=True)
class WorkflowStep:
    key: WorkflowStepKey
    title: str
    state: WorkflowStepState
    detail: str


@dataclass(frozen=True)
class ProxyRuntimeSummary:
    headline: str
    detail: str
    route_summary: str
    active_summary: str
    original_server_summary: str
    probe_summary: str


@dataclass(frozen=True)
class TrafficSnapshot:
    bytes_uploaded: int
    bytes_downloaded: int
    active_connections: int

    @property
    def total_bytes(self) -> int:
        return self.bytes_uploaded + self.bytes_downloaded


def default_workflow_steps() -> list[WorkflowStep]:
    return [
        WorkflowStep(WorkflowStepKey.WHITELIST, "Allowlist", WorkflowStepState.PENDING, "Waiting for validation"),
        WorkflowStep(WorkflowStepKey.PROXY_CONFIG, "Config", WorkflowStepState.PENDING, "Waiting for proxy link"),
        WorkflowStep(WorkflowStepKey.LOCAL_PROXY, "Local Proxy", WorkflowStepState.PENDING, "Waiting to start"),
        WorkflowStep(WorkflowStepKey.XRAY, "Xray Core", WorkflowStepState.PENDING, "Waiting to start"),
        WorkflowStep(WorkflowStepKey.SYSTEM_ROUTE, "System Route", WorkflowStepState.PENDING, "Waiting to configure"),
        WorkflowStep(WorkflowStepKey.PROBE, "Internet Probe", WorkflowStepState.PENDING, "Waiting to probe"),
    ]
