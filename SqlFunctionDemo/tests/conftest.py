import sys
from pathlib import Path

# Make function_app.py and db.py importable when pytest runs from any folder.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
