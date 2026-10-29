"""Container entry point: uvicorn on port 8000, as an unprivileged user."""

import uvicorn

from .user import drop_root

if __name__ == "__main__":
    drop_root()
    uvicorn.run("plateau_accounts.app:app", host="0.0.0.0", port=8000, proxy_headers=False, access_log=False)
