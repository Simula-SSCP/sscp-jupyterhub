"""
A severely stripped-down version of data-8/nbpuller
"""

from concurrent.futures import ThreadPoolExecutor
from functools import lru_cache
from subprocess import check_output
from pathlib import Path
import shutil

import requests
from jupyter_server.base.handlers import JupyterHandler
from jupyter_server.utils import url_path_join
from nbgitpuller.pull import GitPuller
from tornado.concurrent import run_on_executor
from tornado.log import app_log
from tornado.web import authenticated


@lru_cache
def pull_thread():
    return ThreadPoolExecutor(1)


def pull_repo(repo_url):
    # discover default branch with git ls-remote
    out = check_output(["git", "ls-remote", "--symref", repo_url])
    for line in out.decode("utf8", "replace").splitlines():
        parts = line.strip().split()
        if parts and parts[0] == "ref:" and parts[-1] == "HEAD":
            branch_name = parts[1].split("/", 2)[-1]
            break
    else:
        branch_name = "main"
    repo_dir = repo_url.rsplit("/", 1)[-1]
    if repo_dir.endswith(".git"):
        repo_dir = repo_dir[:-4]

    repo_path = Path(repo_dir)

    # If the folder exists, but does NOT contain a .git folder, it's the "Status 128" culprit.
    if repo_path.exists() and not (repo_path / ".git").exists():
        app_log.warning(
            "Directory %s exists but is not a git repository. Removing it to prevent clone failure.",
            repo_dir,
        )
        shutil.rmtree(repo_path)

    app_log.info("Pulling %s", repo_url)

    import time

    max_retries = 10
    for attempt in range(max_retries):
        try:
            gp = GitPuller(repo_url, repo_dir, branch=branch_name)
            for line in gp.pull():
                app_log.info(line.rstrip("\n"))
            break  # Success, exit the loop
        except Exception as e:
            if "Recent .git/index.lock found" in str(e):
                app_log.warning(
                    "Git lock found, waiting to retry... (%d/%d)",
                    attempt + 1,
                    max_retries,
                )
                time.sleep(5)
            else:
                raise e  # Raise any other unexpected errors


def pull_everything():
    r = requests.get(
        "https://raw.githubusercontent.com/Simula-SSCP/sscp-jupyterhub/HEAD/repos.txt"
    )
    r.raise_for_status()
    for line in r.text.splitlines():
        line = line.strip()
        if line.startswith("#"):
            continue
        if not line:
            continue
        repo_url = line
        try:
            pull_repo(repo_url)
        except Exception:
            app_log.exception("Failed to pull repo %s", repo_url)


class PullEverythingHandler(JupyterHandler):
    @property
    def executor(self):
        return pull_thread()

    @authenticated
    @run_on_executor
    async def post(self):
        self.log.info("Updating all repos")
        pull_everything()
        self.log.info("Updated all repos")


def setup_handlers(web_app):
    base_url = web_app.settings.get("base_url", "/")
    web_app.add_handlers(
        ".*",
        [
            (url_path_join(base_url, "api/pull-repos"), PullEverythingHandler),
        ],
    )


def _load_jupyter_server_extension(nbapp):
    setup_handlers(nbapp.web_app)
    pull_thread().submit(pull_everything)


if __name__ == "__main__":
    pull_everything()
