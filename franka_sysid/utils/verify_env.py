from __future__ import annotations

import importlib
import sys


def _import_and_version(module_name: str) -> str:
    module = importlib.import_module(module_name)
    return getattr(module, "__version__", "unknown")


def main() -> None:
    print("Python:", sys.version.replace("\n", " "))

    # Core deps we expect for most scripts.
    for name in [
        "numpy",
        "scipy",
        "torch",
        "matplotlib",
        "hydra",
        "omegaconf",
        "yaml",
    ]:
        try:
            version = _import_and_version(name)
            print(f"{name}: {version}")
        except Exception as e:  # pragma: no cover
            print(f"{name}: FAILED ({e})")
            raise

    # Drake / manipulation stack (this is usually the tricky part).
    for name in ["drake", "pydrake", "manipulation"]:
        try:
            version = _import_and_version(name)
            print(f"{name}: {version}")
        except Exception as e:  # pragma: no cover
            print(f"{name}: FAILED ({e})")
            raise

    print("OK")


if __name__ == "__main__":
    main()


