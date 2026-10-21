"""Demo identities. REAL authentication is out of scope here: in production the
user comes from a verified token (for example Entra ID / JWT), never from a header
the client can set freely."""
from dataclasses import dataclass


@dataclass(frozen=True)
class User:
    name: str
    role: str   # 'customer' | 'agent' | 'admin'


USERS = {
    "ana": User("ana", "customer"),
    "dora": User("dora", "customer"),
    "bruno": User("bruno", "agent"),
    "carla": User("carla", "admin"),
}
